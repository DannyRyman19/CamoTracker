package app.camotrack.android.services

import android.app.Activity
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import app.camotrack.android.BuildConfig
import app.camotrack.android.core.KeyValueStore
import app.camotrack.android.core.SyncEngine
import app.camotrack.android.core.SyncStatus
import com.google.android.gms.auth.api.identity.AuthorizationRequest
import com.google.android.gms.auth.api.identity.AuthorizationResult
import com.google.android.gms.auth.api.identity.ClearTokenRequest
import com.google.android.gms.auth.api.identity.Identity
import com.google.android.gms.common.api.Scope
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder
import kotlin.coroutines.resume

/**
 * Progress on every Android device the player signs in to with the same
 * Google account (iOS's iCloud sync): each game's progress and My DMZ, one
 * small file each in the app's own hidden folder of the player's Google
 * Drive (`appDataFolder`), which only this app can see and which counts as
 * the player's storage, not ours. Nothing goes to camo-track.app.
 *
 * A Premium feature, off until switched on in Customise (Google asks the
 * player to agree first). A pass merges what Drive holds with this device
 * entry by entry (`SyncEngine`), then writes the merged copy back if Drive
 * was missing anything; it runs when the app comes to the front and a moment
 * after every change.
 */
object GoogleSync {
    const val ENABLED_KEY = "ct_google_sync"
    private const val SCOPE = "https://www.googleapis.com/auth/drive.appdata"

    /** What Customise shows under the switch. */
    var status by mutableStateOf(SyncStatus.OFF)
        private set

    private class Entry(val engine: SyncEngine, var holdsWrites: () -> Boolean, var apply: (Map<String, Int>) -> Unit)

    private lateinit var app: Context
    private lateinit var store: KeyValueStore
    private val entries = LinkedHashMap<String, Entry>()
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val passLock = Mutex()
    private var pending: Job? = null

    fun start(context: Context, store: KeyValueStore) {
        app = context.applicationContext
        this.store = store
    }

    val isEnabled: Boolean get() = Premium.isPremium && store.getBoolean(ENABLED_KEY)

    /** The engine for [key], made on first use: its saved values can restore a save that won't read. */
    fun engine(key: String): SyncEngine = entries.getOrPut(key) { Entry(SyncEngine(key, store), { false }, {}) }.engine

    /** Hooks a game's progress (or My DMZ) up: what it holds now, and how to take another device's changes. */
    fun attach(key: String, current: Map<String, Int>, holdsWrites: () -> Boolean = { false }, apply: (Map<String, Int>) -> Unit) {
        val entry = entries.getOrPut(key) { Entry(SyncEngine(key, store), holdsWrites, apply) }
        entry.holdsWrites = holdsWrites
        entry.apply = apply
        entry.engine.start(current)
        if (isEnabled) syncSoon(0)
    }

    /** A local save: stamped for every player, and synced a moment later so a burst of taps is one write. */
    fun record(key: String, values: Map<String, Int>) {
        val entry = entries[key] ?: return
        if (entry.engine.recordLocal(values) && isEnabled) syncSoon(2000)
    }

    /** A pass now: the app back in front, Premium starting, sync switched on. */
    fun syncAll() {
        if (!::store.isInitialized) return
        if (!isEnabled) { pending?.cancel(); status = SyncStatus.OFF; return }
        syncSoon(0)
    }

    private fun syncSoon(afterMillis: Long) {
        pending?.cancel()
        pending = scope.launch {
            if (afterMillis > 0) delay(afterMillis)
            pass()
        }
    }

    // MARK: Switching on and off (Customise)

    /** Google's answer to "may this app keep its data in your Drive?". */
    sealed interface Consent {
        /** Already agreed on this device: sync is on. */
        data object Granted : Consent
        /** Google wants to ask the player: launch this, then hand the result to [finishConsent]. */
        class Ask(val intent: PendingIntent) : Consent
        data object Failed : Consent
    }

    suspend fun switchOn(): Consent {
        val result = authorize() ?: return Consent.Failed
        result.pendingIntent?.takeIf { result.hasResolution() }?.let { return Consent.Ask(it) }
        enable()
        return Consent.Granted
    }

    /** The player came back from Google's screen. True when they agreed. */
    fun finishConsent(resultCode: Int, data: Intent?): Boolean {
        if (resultCode != Activity.RESULT_OK) return false
        val agreed = runCatching { Identity.getAuthorizationClient(app).getAuthorizationResultFromIntent(data) }
            .getOrNull()?.accessToken != null
        if (agreed) enable()
        return agreed
    }

    private fun enable() {
        store.putBoolean(ENABLED_KEY, true)
        syncAll()
    }

    /** Sync off: progress stays on this device and in Drive as it is. */
    fun switchOff() {
        store.putBoolean(ENABLED_KEY, false)
        syncAll()
    }

    // MARK: The pass

    private suspend fun pass() = passLock.withLock {
        if (!isEnabled) { status = SyncStatus.OFF; return@withLock }
        val auth = authorize()
        val token = auth?.accessToken
        if (auth == null) { status = SyncStatus.FAILED; log("no answer from Google"); return@withLock }
        if (auth.hasResolution() || token == null) { status = SyncStatus.SIGNED_OUT; log("Google wants the player to agree"); return@withLock }
        var worst = SyncStatus.SYNCED
        for ((key, entry) in entries.toList()) {
            val result = runCatching { one(Drive(token), key, entry) }.getOrElse { error ->
                // A token Google no longer honours: forget it, and the next pass asks for a fresh one
                if (error is Drive.Refused) runCatching {
                    Identity.getAuthorizationClient(app).clearToken(ClearTokenRequest.builder().setToken(token).build())
                }
                log("$key failed: $error")
                SyncStatus.FAILED
            }
            if (result != SyncStatus.SYNCED && worst != SyncStatus.NEEDS_UPDATE) worst = result
        }
        status = worst
        log("pass done: $worst")
    }

    /**
     * Debug builds only (`--ez debug_sync_wipe true`): sync off, and every
     * file this app keeps in the signed-in account's Drive removed, so test
     * progress doesn't stay behind to merge into real progress later.
     */
    fun debugWipeDrive() {
        if (!BuildConfig.DEBUG) return
        switchOff()
        scope.launch {
            passLock.withLock {
                val token = authorize()?.accessToken
                if (token == null) { log("wipe: not signed in"); return@withLock }
                val removed = runCatching {
                    withContext(Dispatchers.IO) { Drive(token).run { all().onEach(::delete).size } }
                }.getOrElse { log("wipe failed: $it"); return@withLock }
                log("wipe: removed $removed files from Drive")
            }
        }
    }

    /** Debug builds say what each pass did (`adb logcat -s CamoSync`). */
    private fun log(message: String) {
        if (BuildConfig.DEBUG) android.util.Log.d("CamoSync", message)
    }

    private suspend fun one(drive: Drive, key: String, entry: Entry): SyncStatus {
        val name = "$key.json"
        val files = withContext(Dispatchers.IO) { drive.find(name).map { it to drive.read(it) } }
        // Merged here, on the main thread, with whatever was ticked while Drive answered
        val pass = entry.engine.merge(files.map { it.second }, entry.holdsWrites())
        log("$key: ${files.size} in Drive, ${entry.engine.snapshot.values.size} entries here" +
            (pass.applied?.let { ", took in ${it.size}" } ?: "") + (pass.upload?.let { ", writing ${it.length} bytes" } ?: ", nothing to write"))
        pass.applied?.let(entry.apply)
        pass.upload?.let { text ->
            withContext(Dispatchers.IO) {
                if (files.isEmpty()) drive.create(name, text) else drive.update(files[0].first, text)
                // Two devices each made the first copy: one file from here on
                files.drop(1).forEach { runCatching { drive.delete(it.first) } }
            }
        }
        return pass.status
    }

    /** Google's say-so, without showing anything; null when Play services can't be asked. */
    private suspend fun authorize(): AuthorizationResult? = suspendCancellableCoroutine { continuation ->
        val request = AuthorizationRequest.builder().setRequestedScopes(listOf(Scope(SCOPE))).build()
        runCatching {
            Identity.getAuthorizationClient(app).authorize(request)
                .addOnSuccessListener { if (continuation.isActive) continuation.resume(it) }
                .addOnFailureListener { if (continuation.isActive) continuation.resume(null) }
        }.onFailure { if (continuation.isActive) continuation.resume(null) }
    }
}

/** The four Google Drive calls sync needs, on the app's own hidden folder. */
internal class Drive(private val token: String) {
    /** Google turned the token down (expired, or access taken away). */
    class Refused : IOException("Drive refused the token")

    /** The ids of every file called [name] (one, unless two devices raced), oldest first. */
    fun find(name: String): List<String> {
        val query = URLEncoder.encode("name = '$name'", "UTF-8")
        val text = call("GET", "$API/files?spaces=appDataFolder&q=$query&orderBy=createdTime&fields=files(id)&pageSize=20")
        val files = JSONObject(text).optJSONArray("files") ?: return emptyList()
        return (0 until files.length()).map { files.getJSONObject(it).getString("id") }
    }

    /** Every file in the app's folder, whatever it is called. */
    fun all(): List<String> {
        val files = JSONObject(call("GET", "$API/files?spaces=appDataFolder&fields=files(id)&pageSize=100")).optJSONArray("files") ?: return emptyList()
        return (0 until files.length()).map { files.getJSONObject(it).getString("id") }
    }

    fun read(id: String): String = call("GET", "$API/files/$id?alt=media")

    fun create(name: String, content: String) {
        val boundary = "camotrack-${System.nanoTime()}"
        val meta = JSONObject().put("name", name).put("parents", org.json.JSONArray().put("appDataFolder")).toString()
        val body = "--$boundary\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n$meta\r\n" +
            "--$boundary\r\nContent-Type: application/json\r\n\r\n$content\r\n--$boundary--"
        call("POST", "$UPLOAD/files?uploadType=multipart", body, "multipart/related; boundary=$boundary")
    }

    fun update(id: String, content: String) { call("PATCH", "$UPLOAD/files/$id?uploadType=media", content, "application/json") }

    fun delete(id: String) { call("DELETE", "$API/files/$id") }

    private fun call(method: String, url: String, body: String? = null, type: String? = null): String {
        val c = URL(url).openConnection() as HttpURLConnection
        try {
            // HttpURLConnection has no PATCH: Drive takes it as an override on POST
            c.requestMethod = if (method == "PATCH") "POST" else method
            if (method == "PATCH") c.setRequestProperty("X-HTTP-Method-Override", "PATCH")
            c.connectTimeout = 15000; c.readTimeout = 20000
            c.setRequestProperty("authorization", "Bearer $token")
            if (body != null) {
                c.doOutput = true
                c.setRequestProperty("content-type", type)
                c.outputStream.use { it.write(body.toByteArray()) }
            }
            val code = c.responseCode
            if (code == 401 || code == 403) throw Refused()
            if (code !in 200..299) throw IOException("Drive answered $code")
            return c.inputStream.bufferedReader().use { it.readText() }
        } finally { c.disconnect() }
    }

    private companion object {
        const val API = "https://www.googleapis.com/drive/v3"
        const val UPLOAD = "https://www.googleapis.com/upload/drive/v3"
    }
}
