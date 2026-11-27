package app.camotrack.android.services

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import androidx.core.content.ContextCompat
import app.camotrack.android.BuildConfig
import app.camotrack.android.PrefsStore
import app.camotrack.android.core.KeyValueStore
import app.camotrack.android.core.Manifest as DataManifest
import app.camotrack.android.i18n.Strings
import com.google.firebase.FirebaseApp
import com.google.firebase.messaging.FirebaseMessaging
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL

/**
 * Content announcements as real pushes (iOS's PushRegistration), through
 * Firebase Cloud Messaging: the phone's token goes to camo-track.app/api/push
 * with its language, and Tools/send_push.py's announcement arrives as a data
 * message that `PushService` turns into the notification.
 *
 * A build without app/google-services.json has no Firebase: nothing is
 * registered, and the background refresh posts each announcement itself.
 */
object Push {
    /** The token last registered with camo-track.app/api/push. */
    const val SENT_TOKEN_KEY = "ct_push_token_sent"
    /** The language it was registered in: a change of language registers again. */
    private const val SENT_LANG_KEY = "ct_push_lang_sent"
    private const val API = "https://camo-track.app/api/push/register"
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    /** Once per launch, as on iPhone, so the server knows the phone is still there. */
    @Volatile private var sentThisLaunch = false

    fun isRegistered(store: KeyValueStore): Boolean = store.getString(SENT_TOKEN_KEY) != null

    /** A pushed announcement (one with an id) on a phone that gets pushes. */
    fun covers(store: KeyValueStore, announcement: DataManifest.Announcement?): Boolean =
        announcement?.id != null && isRegistered(store)

    private fun allowed(context: Context) =
        ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED

    /**
     * Registers this phone once notifications are allowed: at launch, and
     * again whenever the app comes back (the permission may just have been
     * given). With notifications off the phone is forgotten here, so the
     * background refresh doesn't stay quiet for a push that can't show.
     */
    fun sync(context: Context, store: KeyValueStore) {
        val app = context.applicationContext
        if (FirebaseApp.getApps(app).isEmpty()) return
        if (!allowed(app)) { store.remove(SENT_TOKEN_KEY); return }
        val lang = Strings.language
        if (sentThisLaunch && isRegistered(store) && store.getString(SENT_LANG_KEY) == lang) return
        FirebaseMessaging.getInstance().token.addOnSuccessListener { token -> register(store, token, lang) }
    }

    /** Firebase gave the phone a new token (a restore, a reinstall, a cleared app). */
    fun tokenChanged(context: Context, token: String) {
        val app = context.applicationContext
        val store = PrefsStore(app)
        if (allowed(app)) register(store, token, Strings.language) else store.remove(SENT_TOKEN_KEY)
    }

    /** What the Worker is told: the token, the language, the version. Nothing about the player. */
    fun registration(token: String, lang: String, version: String): String =
        JSONObject().put("platform", "android").put("token", token).put("lang", lang).put("version", version).toString()

    private fun register(store: KeyValueStore, token: String, lang: String) {
        if (token.isEmpty()) return
        scope.launch {
            val ok = runCatching {
                val c = URL(API).openConnection() as HttpURLConnection
                try {
                    c.requestMethod = "POST"; c.connectTimeout = 15000; c.readTimeout = 15000
                    c.doOutput = true
                    c.setRequestProperty("content-type", "application/json")
                    c.outputStream.use { it.write(registration(token, lang, BuildConfig.VERSION_NAME).toByteArray()) }
                    c.responseCode in 200..299
                } finally { c.disconnect() }
            }.getOrDefault(false)
            if (ok) {
                store.putString(SENT_TOKEN_KEY, token)
                store.putString(SENT_LANG_KEY, lang)
                sentThisLaunch = true
            }
        }
    }
}

/** Firebase's side: a new token, or an announcement arriving. */
class PushService : FirebaseMessagingService() {
    override fun onNewToken(token: String) = Push.tokenChanged(this, token)

    override fun onMessageReceived(message: RemoteMessage) {
        val data = message.data
        val title = data["title"].orEmpty().trim()
        val body = data["body"].orEmpty().trim()
        if (title.isNotEmpty() || body.isNotEmpty()) {
            Refresh.post(this, title, body, data["link"]?.takeIf { it.startsWith("mw4camo://mode/") })
        }
        // The data the announcement is about, so it's there when the app opens
        Refresh.now(this)
    }
}
