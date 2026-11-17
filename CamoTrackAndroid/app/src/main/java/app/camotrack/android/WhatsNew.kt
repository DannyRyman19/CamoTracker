package app.camotrack.android

import app.camotrack.android.core.KeyValueStore

/**
 * What's new in this version, shown once after an update (never on a fresh
 * install: onboarding covers that) and kept in Customise (iOS WhatsNew.swift).
 *
 * To announce a release: add its items under its version name in
 * [releases], with `ct.whatsnew.<id>.title` and `.body` in every language.
 * An update shows every release since the one the player last saw, newest
 * first. The first Android release has nothing "new", so the list starts empty.
 */
object WhatsNew {
    enum class Action { STREAM_OVERLAY, NOTIFICATIONS }

    /** [symbol] names the icon (see WhatsNewScreen). */
    data class Item(val id: String, val symbol: String, val action: Action? = null) {
        val titleKey: String get() = "ct.whatsnew.$id.title"
        val bodyKey: String get() = "ct.whatsnew.$id.body"
    }

    var releases: Map<String, List<Item>> = emptyMap()

    const val SEEN_KEY = "ct_whats_new_seen"
    const val FROM_KEY = "ct_whats_new_from"

    val version: String get() = BuildConfig.VERSION_NAME

    /** `a` is a later version than `b`, comparing each number ("1.0.10" > "1.0.9"). */
    fun newer(a: String, b: String): Boolean {
        val x = a.split('.').map { it.toIntOrNull() ?: 0 }
        val y = b.split('.').map { it.toIntOrNull() ?: 0 }
        for (i in 0 until maxOf(x.size, y.size)) {
            val d = x.getOrElse(i) { 0 } - y.getOrElse(i) { 0 }
            if (d != 0) return d > 0
        }
        return false
    }

    /** The releases after [seen] up to [version], newest first (with no [seen], every one up to [version]). */
    fun items(seen: String?, version: String = this.version): List<Item> =
        releases.keys
            .filter { key -> !newer(key, version) && (seen?.let { newer(key, it) } ?: true) }
            .sortedWith { a, b -> if (newer(a, b)) -1 else if (newer(b, a)) 1 else 0 }
            .flatMap { releases[it].orEmpty() }

    /** What the screen shows: everything since what this player last saw; once seen, the same again. */
    fun items(store: KeyValueStore, version: String = this.version): List<Item> {
        val seen = store.getString(SEEN_KEY)
        val fresh = items(if (seen == version) store.getString(FROM_KEY) else seen, version)
        return fresh.ifEmpty { items(null, version).take(3) }
    }

    /** After an update, for someone who'd already been through onboarding. */
    fun shouldShow(store: KeyValueStore, hasOnboarded: Boolean, version: String = this.version): Boolean {
        val seen = store.getString(SEEN_KEY)
        return hasOnboarded && seen != version && items(seen, version).isNotEmpty()
    }

    /** Seen (or nothing to see: a fresh install, which starts on this version). */
    fun markSeen(store: KeyValueStore, version: String = this.version) {
        val seen = store.getString(SEEN_KEY)
        if (seen != version) store.putString(FROM_KEY, seen)
        store.putString(SEEN_KEY, version)
    }
}
