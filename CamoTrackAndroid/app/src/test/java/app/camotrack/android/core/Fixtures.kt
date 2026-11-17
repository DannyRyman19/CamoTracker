package app.camotrack.android.core

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonObject
import java.io.File
import java.io.IOException
import java.nio.file.Files

/** The bundled iOS data files, copied into src/test/resources. */
object Fixtures {
    fun resource(name: String): String? = Fixtures::class.java.classLoader!!.getResource(name)?.readText()

    val seeds = SeedSource { resource(it) }
    val games: List<Game> by lazy { GameRegistry.load(seeds) }
    val mw4: Game by lazy { games.first { it.id == "mw4" } }
    fun game(id: String): Game = games.first { it.id == id }

    /** No network in tests unless one is given. */
    val offline = Fetcher { throw IOException("offline") }

    fun tempDir(): File = Files.createTempDirectory("camotrack-test").toFile().also { it.deleteOnExit() }

    /** The bundled file [name] (without .json) with its top-level [blocks] (key to JSON) replaced. */
    fun overlaid(name: String, blocks: Map<String, String>): String {
        val obj = Json.parseToJsonElement(resource("$name.json")!!).jsonObject.toMutableMap()
        for ((key, json) in blocks) obj[key] = Json.parseToJsonElement(json)
        return JsonObject(obj).toString()
    }

    /** The bundled file with its version swapped. */
    fun withVersion(name: String, version: String): String {
        val obj = Json.parseToJsonElement(resource("$name.json")!!).jsonObject.toMutableMap()
        obj["version"] = JsonPrimitive(version)
        return JsonObject(obj).toString()
    }
}

/**
 * The iOS tests' setup: a private save and a private cache, with the
 * Multiplayer/Warzone files laid over the bundled ones in the cache.
 */
class Harness(val game: Game = Fixtures.mw4) {
    val store = InMemoryKeyValueStore()
    val cache: File = Fixtures.tempDir()
    var now = 1_800_000_000.0
    val mp = "multiplayer"

    fun model(
        blocks: Map<String, String> = emptyMap(),
        warzone: Map<String, String> = emptyMap(),
        fetcher: Fetcher = Fixtures.offline,
    ): GameTracker {
        write("multiplayer", blocks)
        write("warzone", warzone)
        return GameTracker(game, DataService(game, cache, Fixtures.seeds, fetcher), store, clock = { now })
    }

    fun plain(fetcher: Fetcher = Fixtures.offline): GameTracker =
        GameTracker(game, DataService(game, cache, Fixtures.seeds, fetcher), store, clock = { now })

    private fun write(mode: String, blocks: Map<String, String>) {
        val target = File(cache, "$mode.json")
        target.delete()
        if (blocks.isEmpty()) return
        target.writeText(Fixtures.overlaid(game.seedPrefix + mode, blocks))
    }
}

/** Answers with fixed bodies by last path component and records every URL asked. */
class RecordingFetcher(var bodies: Map<String, String> = emptyMap()) : Fetcher {
    val requests = mutableListOf<String>()
    /** Hosts that fail: with this HTTP status, or 0 for no answer. */
    var failingHosts: Map<String, Int> = emptyMap()

    override fun get(url: String): ByteArray {
        synchronized(requests) { requests += url }
        val host = java.net.URI(url).host
        failingHosts[host]?.let { status ->
            if (status == 0) throw IOException("cannot connect")
            throw HttpStatusException(url, status)
        }
        return (bodies[url.substringAfterLast('/')] ?: "{}").toByteArray()
    }

    fun count(file: String) = synchronized(requests) { requests.count { it.endsWith("/$file") } }
}
