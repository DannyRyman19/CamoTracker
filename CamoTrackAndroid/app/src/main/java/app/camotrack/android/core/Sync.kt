package app.camotrack.android.core

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.intOrNull

/**
 * Progress as flat entries, each with the time it last changed, so two
 * devices merge entry by entry: ticking camos on a phone and a tablet keeps
 * both, and un-ticking one wins over an older tick elsewhere. The iOS
 * `SyncSnapshot`, in the same JSON layout.
 *
 * A stamp with no value is a deletion (an un-ticked camo, a cleared count),
 * kept so the other device learns about it.
 */
data class SyncSnapshot(val values: Map<String, Int> = emptyMap(), val stamps: Map<String, Double> = emptyMap()) {

    /** Stamps every entry that differs from this snapshot's with [now]. */
    fun updated(to: Map<String, Int>, now: Double): SyncSnapshot {
        val next = HashMap(stamps)
        for (key in to.keys + values.keys) if (to[key] != values[key]) next[key] = now
        return SyncSnapshot(to, next)
    }

    fun encoded(): String = CamoJson.encodeToString(Payload.serializer(), Payload(FORMAT, values, stamps))

    @Serializable
    private data class Payload(val format: Int? = null, val values: Map<String, Int> = emptyMap(), val stamps: Map<String, Double> = emptyMap())

    /** A stored snapshot as read back. */
    sealed interface Read {
        data class Value(val snapshot: SyncSnapshot) : Read
        /** Written by a newer build: never overwritten, sync waits for an update. */
        data object NewerFormat : Read
        /** Not a snapshot of any format this build knows (a cut-off write): replaced. */
        data object Unreadable : Read
    }

    companion object {
        /**
         * The format this build writes. Raise it when the layout changes in a
         * way an older build would misread: an older build then leaves the
         * newer copy alone instead of overwriting it with less.
         */
        const val FORMAT = 1

        /**
         * Each entry from whichever side changed it last. An entry neither
         * side has a stamp for (progress from before sync) is kept from
         * whichever side has it, local first, so turning sync on loses nothing.
         */
        fun merge(local: SyncSnapshot, remote: SyncSnapshot): SyncSnapshot {
            val values = HashMap<String, Int>()
            val stamps = HashMap<String, Double>()
            for (key in local.values.keys + remote.values.keys + local.stamps.keys + remote.stamps.keys) {
                val l = local.stamps[key] ?: 0.0
                val r = remote.stamps[key] ?: 0.0
                val value = when {
                    r > l -> remote.values[key]
                    l > r -> local.values[key]
                    else -> local.values[key] ?: remote.values[key]
                }
                val stamp = maxOf(l, r)
                if (value != null) values[key] = value
                if (stamp > 0) stamps[key] = stamp
            }
            return SyncSnapshot(values, stamps)
        }

        fun read(text: String): Read {
            val format = runCatching { CamoJson.parseToJsonElement(text).jsonObject["format"]?.jsonPrimitive?.intOrNull }
                .getOrElse { return Read.Unreadable }
            if ((format ?: 1) > FORMAT) return Read.NewerFormat
            val payload = runCatching { CamoJson.decodeFromString(Payload.serializer(), text) }.getOrElse { return Read.Unreadable }
            return Read.Value(SyncSnapshot(payload.values, payload.stamps))
        }
    }
}

enum class SyncStatus {
    /** Not Premium, or not switched on in Customise. */
    OFF,
    /** Switched on, but Google needs the player to sign in or agree again. */
    SIGNED_OUT,
    /** The stored copy is a newer format than this build understands; nothing is written until the app is updated. */
    NEEDS_UPDATE,
    /** Google Drive couldn't be reached; changes stay on this device until it can. */
    FAILED,
    SYNCED,
}

/**
 * One synced blob (a game's progress, or My DMZ): the local copy with its
 * stamps in the store under `<key>_stamps`, and the merge with what the
 * cloud holds. No network here: `services/GoogleSync.kt` reads and writes
 * the cloud copy around [merge].
 *
 * Stamps are kept for every player, Premium or not, so switching sync on
 * later already knows when each entry last changed.
 */
class SyncEngine(val key: String, private val store: KeyValueStore, private val clock: () -> Double = { System.currentTimeMillis() / 1000.0 }) {
    var snapshot: SyncSnapshot =
        store.getString("${key}_stamps")?.let { (SyncSnapshot.read(it) as? SyncSnapshot.Read.Value)?.snapshot } ?: SyncSnapshot()
        private set

    /** Progress saved before sync existed has no stamps: adopted as it is. */
    fun start(current: Map<String, Int>) {
        if (snapshot.values.isEmpty() && snapshot.stamps.isEmpty() && current.isNotEmpty()) {
            snapshot = SyncSnapshot(values = current)
            persist()
        }
    }

    /** Records a local save: stamps what changed. False when nothing did. */
    fun recordLocal(values: Map<String, Int>): Boolean {
        val next = snapshot.updated(values, clock())
        if (next == snapshot) return false
        snapshot = next
        persist()
        return true
    }

    /**
     * What one pass decided: values to show when another device changed
     * something, and the text to store when the cloud is missing anything.
     */
    data class Pass(val status: SyncStatus, val applied: Map<String, Int>? = null, val upload: String? = null)

    /**
     * Merges every cloud copy in ([remotes]: none yet, one, or several when
     * two devices each made the first). Every write comes out of this, so a
     * device that was off or signed out never replaces another's progress
     * with its own. [holdsWrites]: this device's save couldn't be read, so
     * it takes changes in but writes nothing.
     */
    fun merge(remotes: List<String>, holdsWrites: Boolean = false): Pass {
        var merged = snapshot
        var stale = remotes.size != 1
        for (text in remotes) {
            when (val read = SyncSnapshot.read(text)) {
                is SyncSnapshot.Read.Value -> {
                    merged = SyncSnapshot.merge(merged, read.snapshot)
                }
                SyncSnapshot.Read.NewerFormat -> return Pass(SyncStatus.NEEDS_UPDATE)
                SyncSnapshot.Read.Unreadable -> stale = true
            }
        }
        if (!stale) stale = (SyncSnapshot.read(remotes[0]) as SyncSnapshot.Read.Value).snapshot != merged
        var applied: Map<String, Int>? = null
        if (merged != snapshot) {
            if (merged.values != snapshot.values) applied = merged.values
            snapshot = merged
            persist()
        }
        return Pass(SyncStatus.SYNCED, applied, if (stale && !holdsWrites) merged.encoded() else null)
    }

    private fun persist() = store.putString("${key}_stamps", snapshot.encoded())
}
