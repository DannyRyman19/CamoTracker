package app.camotrack.android.services

import app.camotrack.android.core.KeyValueStore
import app.camotrack.android.core.Manifest

/**
 * Content announcements as real pushes (iOS's PushRegistration). On Android
 * they come through Firebase Cloud Messaging once the app has a Firebase
 * project; until then nothing is registered, and the background refresh
 * posts each announcement itself.
 */
object Push {
    /** The token last registered with camo-track.app/api/push. */
    const val SENT_TOKEN_KEY = "ct_push_token_sent"

    fun isRegistered(store: KeyValueStore): Boolean = store.getString(SENT_TOKEN_KEY) != null

    /** A pushed announcement (one with an id) on a phone that gets pushes. */
    fun covers(store: KeyValueStore, announcement: Manifest.Announcement?): Boolean =
        announcement?.id != null && isRegistered(store)
}
