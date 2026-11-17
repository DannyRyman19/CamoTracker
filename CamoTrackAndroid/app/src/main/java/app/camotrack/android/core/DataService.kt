package app.camotrack.android.core

import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.serialization.Serializable
import java.io.File
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL
import kotlin.coroutines.cancellation.CancellationException

/** Fetches one URL, throwing on a failed request or a non-2xx status. Must never answer from a local HTTP cache. */
fun interface Fetcher {
    @Throws(IOException::class)
    fun get(url: String): ByteArray
}

/** The data files bundled with the app (assets on Android), by file name ("bo7_weapons.json"). */
fun interface SeedSource {
    fun read(fileName: String): String?
}

class HttpStatusException(val url: String, val status: Int) : IOException("HTTP $status for $url")

/** The default [Fetcher]: always asks the server (jsDelivr sends max-age=604800). */
object HttpFetcher : Fetcher {
    override fun get(url: String): ByteArray {
        val connection = URL(url).openConnection() as HttpURLConnection
        try {
            connection.useCaches = false
            connection.setRequestProperty("Cache-Control", "no-cache")
            connection.connectTimeout = 15_000
            connection.readTimeout = 30_000
            val status = connection.responseCode
            if (status !in 200..299) throw HttpStatusException(url, status)
            return connection.inputStream.use { it.readBytes() }
        } finally {
            connection.disconnect()
        }
    }
}

/**
 * Fetches the weapon catalog and mode files from the CDN, versioned through
 * `manifest.json`, and caches each to disk so nothing re-downloads unless its
 * version bumps. A path jsDelivr fails is asked of GitHub once.
 */
class DataService(
    private val game: Game,
    private val cacheDir: File,
    private val seeds: SeedSource,
    private val fetcher: Fetcher = HttpFetcher,
) {
    data class RefreshResult(
        val catalog: WeaponCatalog?,
        val modes: Map<String, ModeFile>,
        val notification: Manifest.Announcement?,
    )

    init {
        cacheDir.mkdirs()
    }

    // Weapon catalog

    fun loadSeedCatalog(): WeaponCatalog? = decode(seeds.read(game.seedPrefix + "weapons.json"))
    fun loadCachedCatalog(): WeaponCatalog? = decode(readCache("weapons"))

    /** The kept download, unless the app bundles a newer one. */
    fun loadCatalog(): WeaponCatalog? = newest(loadSeedCatalog(), loadCachedCatalog()) { it.version }

    // Mode files

    fun loadSeed(mode: String): ModeFile? = decode(seeds.read(game.seedPrefix + mode + ".json"))
    fun loadCached(mode: String): ModeFile? = decode(readCache(mode))
    fun load(mode: String): ModeFile? = newest(loadSeed(mode), loadCached(mode)) { it.version }

    /**
     * Fetches the manifest and every file whose version is higher than the
     * app's. Every file is downloaded and decoded before any is kept, one that
     * fails is skipped, and only when nothing at all came down does the error
     * reach the caller. Blocking IO: call it off the main thread.
     */
    suspend fun refreshIfNeeded(knownCatalogVersion: String?, knownModeVersions: Map<String, String>): RefreshResult {
        val manifest = CamoJson.decodeFromString(Manifest.serializer(), fetch("manifest.json").decodeToString())

        var failure: Exception? = null
        var catalogDownload: Pair<WeaponCatalog, ByteArray>? = null
        if (isNewer(manifest.catalog.version, knownCatalogVersion)) {
            try {
                val data = fetch(manifest.catalog.path)
                val catalog = CamoJson.decodeFromString(WeaponCatalog.serializer(), data.decodeToString())
                if (isNewer(catalog.version, knownCatalogVersion)) catalogDownload = catalog to data
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                failure = e
            }
        }

        val modeDownloads = linkedMapOf<String, Pair<ModeFile, ByteArray>>()
        for ((mode, entry) in manifest.modes) {
            if (!isNewer(entry.version, knownModeVersions[mode])) continue
            try {
                val data = fetch(entry.path)
                val file = CamoJson.decodeFromString(ModeFile.serializer(), data.decodeToString())
                if (isNewer(file.version, knownModeVersions[mode])) modeDownloads[mode] = file to data
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                failure = failure ?: e
            }
        }
        if (failure != null && catalogDownload == null && modeDownloads.isEmpty()) throw failure
        // A check stopped part-way (a game switch) keeps nothing
        currentCoroutineContext().ensureActive()

        var newCatalog: WeaponCatalog? = null
        if (catalogDownload != null && keep(catalogDownload.second, "weapons", catalogDownload.first.version)) {
            newCatalog = catalogDownload.first
        }
        val updated = linkedMapOf<String, ModeFile>()
        for ((mode, download) in modeDownloads) {
            if (keep(download.second, mode, download.first.version)) updated[mode] = download.first
        }
        return RefreshResult(newCatalog, updated, manifest.notification)
    }

    /** jsDelivr first; on any failure the same path from GitHub, once. */
    private suspend fun fetch(path: String): ByteArray = try {
        fetcher.get(game.dataURL + path)
    } catch (e: CancellationException) {
        throw e
    } catch (e: Exception) {
        currentCoroutineContext().ensureActive()
        fetcher.get(game.dataMirrorURL + path)
    }

    /** Writes a download to the cache unless a newer copy is already kept. */
    private fun keep(data: ByteArray, name: String, version: String): Boolean = synchronized(KEEP_LOCK) {
        val current = readCache(name)?.let { runCatching { CamoJson.decodeFromString(Versioned.serializer(), it) }.getOrNull() }
        if (!canReplace(current?.version, version)) return false
        val target = cacheFile(name)
        val temp = File(cacheDir, "$name.json.tmp")
        temp.writeBytes(data)
        if (!temp.renameTo(target)) {
            target.delete()
            if (!temp.renameTo(target)) throw IOException("Couldn't write $target")
        }
        true
    }

    @Serializable
    private data class Versioned(val version: String)

    private fun cacheFile(name: String) = File(cacheDir, "$name.json")

    private fun readCache(name: String): String? = cacheFile(name).takeIf { it.isFile }?.let { runCatching { it.readText() }.getOrNull() }

    private inline fun <reified T> decode(text: String?): T? =
        text?.let { runCatching { CamoJson.decodeFromString<T>(it) }.getOrNull() }

    companion object {
        private val KEEP_LOCK = Any()

        /** Where a game's downloads are kept under the app's files dir (MW4's keeps its own folder name). */
        fun defaultCacheDir(filesDir: File, game: Game): File =
            if (game.isMW4) File(filesDir, "MW4CamoTracker") else File(File(filesDir, "CamoTracker"), game.id)

        /** The bundled seed when it's newer than the kept download, else the download (or whichever exists). */
        fun <T> newest(seed: T?, cached: T?, version: (T) -> String): T? {
            if (seed != null && cached != null && isNewer(version(seed), version(cached))) return seed
            return cached ?: seed
        }

        /**
         * Dotted versions compared number by number ("0.8.12" > "0.8.9"); any
         * version beats none; a part that isn't a number counts as 0. Must
         * match `Tools/publish_data.py`'s `is_newer`.
         */
        fun isNewer(version: String, known: String?): Boolean {
            if (known == null) return true
            val a = parts(version)
            val b = parts(known)
            for (i in 0 until maxOf(a.size, b.size)) {
                val x = a.getOrElse(i) { 0 }
                val y = b.getOrElse(i) { 0 }
                if (x != y) return x > y
            }
            return false
        }

        /** Swift's `split(separator: ".")` drops empty parts; `Int("x")` fails to 0. */
        private fun parts(version: String): List<Int> =
            version.split(".").filter { it.isNotEmpty() }.map { swiftInt(it) ?: 0 }

        /** Swift's `Int(String)`: optional sign then decimal digits only. */
        private fun swiftInt(s: String): Int? {
            if (!Regex("[+-]?[0-9]+").matches(s)) return null
            return s.toIntOrNull()
        }

        /** Whether a downloaded version may replace the current one: anything but an older one. */
        fun canReplace(current: String?, version: String): Boolean = current == null || !isNewer(current, version)
    }
}
