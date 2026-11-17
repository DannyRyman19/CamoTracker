package app.camotrack.android.core.hajin

import app.camotrack.android.core.CamoJson
import app.camotrack.android.core.DataService
import app.camotrack.android.core.Fetcher
import app.camotrack.android.core.Game
import app.camotrack.android.core.HttpFetcher
import app.camotrack.android.core.SeedSource
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.serialization.Serializable
import java.io.File
import java.io.IOException
import kotlin.coroutines.cancellation.CancellationException

/**
 * Loads the Hajin guide: the bundled `hajin.json`, or the kept download when
 * it's newer, and fetches a newer one when the manifest's `guides` block
 * lists it (iOS DataService's guide half). Kept as `guide-hajin.json` in the
 * game's cache folder.
 */
class HajinGuideService(
    private val game: Game,
    private val cacheDir: File,
    private val seeds: SeedSource,
    private val fetcher: Fetcher = HttpFetcher,
) {
    @Serializable
    private data class Entry(val version: String, val path: String)

    /** Only the part of the manifest a guide needs; one without `guides` still decodes. */
    @Serializable
    private data class GuideManifest(val guides: Map<String, Entry>? = null)

    @Serializable
    private data class Versioned(val version: String)

    fun loadSeed(name: String = "hajin"): HajinGuide? = decode(seeds.read("$name.json"))

    fun loadCached(name: String = "hajin"): HajinGuide? = decode(cacheFile(name).takeIf { it.isFile }?.let { runCatching { it.readText() }.getOrNull() })

    /** The kept download, unless the app bundles a newer one. */
    fun load(name: String = "hajin"): HajinGuide? = DataService.newest(loadSeed(name), loadCached(name)) { it.version }

    /** Downloads the named guide when the manifest lists a newer version than `knownVersion`. Blocking IO. */
    suspend fun refresh(name: String = "hajin", knownVersion: String?): HajinGuide? {
        val manifest = CamoJson.decodeFromString(GuideManifest.serializer(), fetch("manifest.json").decodeToString())
        val entry = manifest.guides?.get(name) ?: return null
        if (!DataService.isNewer(entry.version, knownVersion)) return null
        val data = fetch(entry.path)
        val guide = CamoJson.decodeFromString(HajinGuide.serializer(), data.decodeToString())
        if (!DataService.isNewer(guide.version, knownVersion)) return null
        currentCoroutineContext().ensureActive()
        if (!keep(data, name, guide.version)) return null
        return guide
    }

    private suspend fun fetch(path: String): ByteArray = try {
        fetcher.get(game.dataURL + path)
    } catch (e: CancellationException) {
        throw e
    } catch (e: Exception) {
        currentCoroutineContext().ensureActive()
        fetcher.get(game.dataMirrorURL + path)
    }

    private fun keep(data: ByteArray, name: String, version: String): Boolean = synchronized(LOCK) {
        cacheDir.mkdirs()
        val target = cacheFile(name)
        val current = target.takeIf { it.isFile }?.let {
            runCatching { CamoJson.decodeFromString(Versioned.serializer(), it.readText()) }.getOrNull()
        }
        if (!DataService.canReplace(current?.version, version)) return false
        val temp = File(cacheDir, "guide-$name.json.tmp")
        temp.writeBytes(data)
        if (!temp.renameTo(target)) {
            target.delete()
            if (!temp.renameTo(target)) throw IOException("Couldn't write $target")
        }
        true
    }

    private fun cacheFile(name: String) = File(cacheDir, "guide-$name.json")

    private fun decode(text: String?): HajinGuide? =
        text?.let { runCatching { CamoJson.decodeFromString(HajinGuide.serializer(), it) }.getOrNull() }

    private companion object {
        val LOCK = Any()
    }
}
