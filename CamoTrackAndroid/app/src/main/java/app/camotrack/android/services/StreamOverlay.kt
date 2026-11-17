package app.camotrack.android.services

import android.net.Uri
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import app.camotrack.android.core.GameTracker
import app.camotrack.android.core.KeyValueStore
import app.camotrack.android.core.MasteryCamo
import app.camotrack.android.core.WeaponEntry
import app.camotrack.android.i18n.L
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import java.net.HttpURLConnection
import java.net.URL
import java.security.SecureRandom
import android.util.Base64

/** What the overlay page shows, as the camo-track-overlay Worker accepts it (iOS's CamoOverlayPayload). */
@Serializable
data class OverlayPayload(
    val view: String,
    val game: String,
    val mode: String,
    val accent: String,
    val overview: Overview? = null,
    val weapon: Weapon? = null,
    val channel: String = "",
) {
    @Serializable data class Step(val name: String, val done: Int, val total: Int, val color: String)
    @Serializable data class Overview(val fraction: Double, val weaponCount: Int, val steps: List<Step>, val mastery: List<Step>)
    @Serializable data class Camo(val name: String, val image: String, val done: Boolean)
    @Serializable data class Next(val name: String, val detail: String, val done: Int, val total: Int)
    @Serializable data class Weapon(
        val name: String, val category: String, val badge: String = "", val image: String,
        val camos: List<Camo>, val done: Int, val total: Int, val next: Next? = null,
    )
}

/**
 * Camo Track's stream overlay (iOS StreamOverlay): free, off until switched
 * on. While on, the figures go to camo-track.app shortly after each change;
 * the player adds [pageUrl] to OBS. The link is a random id; the key, sent
 * only as the bearer token, is what lets this app change or remove it.
 * Same stored keys as on iPhone.
 */
object StreamOverlay {
    const val SERVER = "https://camo-track.app"

    enum class Content { overview, weapon }
    enum class Layout(val width: Int, val height: Int) { card(760, 340), vertical(320, 700), minimal(560, 250) }
    enum class Style { camo, glass, clean }
    sealed interface Status {
        data object Off : Status
        data object Waiting : Status
        data class Live(val at: Long) : Status
        data object Failed : Status
    }

    private object Keys {
        const val on = "ct_overlay_on"; const val id = "ct_overlay_id"; const val key = "ct_overlay_key"
        const val content = "ct_overlay_content"; const val mode = "ct_overlay_mode"; const val layout = "ct_overlay_layout"
        const val style = "ct_overlay_style"; const val qr = "ct_overlay_qr"; const val right = "ct_overlay_right"
        const val celebrate = "ct_overlay_celebrate"; const val channel = "ct_overlay_channel"
        fun weapon(game: String) = "ct_overlay_weapon_$game"
    }

    private lateinit var store: KeyValueStore
    private val scope = CoroutineScope(Dispatchers.Main.immediate)
    private val json = Json { encodeDefaults = true }
    private var pending: Job? = null
    private var lastSent: OverlayPayload? = null
    private var key = ""
    /** Builds what to send; set once the tracker exists. */
    var makePayload: (() -> OverlayPayload?)? = null

    var isOn by mutableStateOf(false); private set
    var id by mutableStateOf(""); private set
    var status by mutableStateOf<Status>(Status.Off); private set
    var content by mutableStateOf(Content.overview); private set
    var mode by mutableStateOf(""); private set
    var layout by mutableStateOf(Layout.card); private set
    var style by mutableStateOf(Style.camo); private set
    var showsQR by mutableStateOf(true); private set
    var alignsRight by mutableStateOf(false); private set
    var celebrates by mutableStateOf(true); private set
    var channel by mutableStateOf(""); private set
    /** Bumped when a weapon pick changes, so screens reading [weaponId] recompose. */
    var weaponRevision by mutableStateOf(0); private set

    fun start(store: KeyValueStore) {
        this.store = store
        id = store.getString(Keys.id) ?: ""
        key = store.getString(Keys.key) ?: ""
        isOn = store.getBoolean(Keys.on) && id.isNotEmpty() && key.isNotEmpty()
        status = if (isOn) Status.Waiting else Status.Off
        content = store.getString(Keys.content)?.let { runCatching { Content.valueOf(it) }.getOrNull() } ?: Content.overview
        mode = store.getString(Keys.mode) ?: ""
        layout = store.getString(Keys.layout)?.let { runCatching { Layout.valueOf(it) }.getOrNull() } ?: Layout.card
        style = store.getString(Keys.style)?.let { runCatching { Style.valueOf(it) }.getOrNull() } ?: Style.camo
        showsQR = if (store.contains(Keys.qr)) store.getBoolean(Keys.qr) else true
        alignsRight = store.getBoolean(Keys.right)
        celebrates = if (store.contains(Keys.celebrate)) store.getBoolean(Keys.celebrate) else true
        channel = store.getString(Keys.channel) ?: ""
    }

    fun changeContent(v: Content) { content = v; store.putString(Keys.content, v.name); refresh() }
    fun changeMode(v: String) { mode = v; store.putString(Keys.mode, v); refresh() }
    fun changeLayout(v: Layout) { layout = v; store.putString(Keys.layout, v.name) }
    fun changeStyle(v: Style) { style = v; store.putString(Keys.style, v.name) }
    fun changeShowsQR(v: Boolean) { showsQR = v; store.putBoolean(Keys.qr, v) }
    fun changeAlignsRight(v: Boolean) { alignsRight = v; store.putBoolean(Keys.right, v) }
    fun changeCelebrates(v: Boolean) { celebrates = v; store.putBoolean(Keys.celebrate, v) }
    fun changeChannel(v: String) { channel = v; store.putString(Keys.channel, v); refresh() }

    /** The weapon shown for `game` (each game keeps its own), null for none picked. */
    fun weaponId(game: String): Int? { weaponRevision; return store.getInt(Keys.weapon(game)) }
    fun setWeapon(weaponId: Int?, game: String) { store.putInt(Keys.weapon(game), weaponId); weaponRevision++; refresh() }

    // ── Links ──
    private fun withOptions(page: String): String {
        val b = Uri.parse(page).buildUpon()
        if (layout != Layout.card) b.appendQueryParameter("layout", layout.name)
        if (style != Style.camo) b.appendQueryParameter("style", style.name)
        if (!showsQR) b.appendQueryParameter("qr", "0")
        if (alignsRight) b.appendQueryParameter("align", "right")
        if (!celebrates) b.appendQueryParameter("celebrate", "0")
        return b.build().toString()
    }

    /** The page to add to OBS. */
    val pageUrl: String get() = withOptions("$SERVER/overlay/$id")

    /** The preview: this overlay's page when on, else the demo in the same look. */
    val previewUrl: String
        get() = if (isOn && id.isNotEmpty()) pageUrl else {
            val demo = withOptions("$SERVER/overlay/demo")
            if (content == Content.weapon) Uri.parse(demo).buildUpon().appendQueryParameter("view", "weapon").build().toString() else demo
        }

    private val feedUrl get() = "$SERVER/api/overlay/$id"

    /** As the Worker accepts it: no @, letters, digits, `_`, `.`, `-`, up to 40. */
    fun cleanChannel(typed: String): String {
        val name = typed.trim().trimStart('@')
        return if (name.isNotEmpty() && name.length <= 40 && name.all { it.isLetterOrDigit() && it.code < 128 || it in "_.-" }) name else ""
    }

    // ── Switching ──
    fun turnOn() {
        if (isOn) return
        if (id.isEmpty() || key.isEmpty()) mintLink()
        isOn = true; store.putBoolean(Keys.on, true)
        status = Status.Waiting; lastSent = null
        refresh(immediately = true)
    }

    fun turnOff() {
        if (!isOn) return
        isOn = false; store.putBoolean(Keys.on, false)
        status = Status.Off; pending?.cancel(); lastSent = null
        val url = feedUrl
        scope.launch { send("DELETE", url, null) }
    }

    /** A fresh link, for when the old one got out. The old one stops working. */
    fun replaceLink() {
        val old = feedUrl
        scope.launch { send("DELETE", old, null) }
        mintLink(); lastSent = null
        if (isOn) { status = Status.Waiting; refresh(immediately = true) }
    }

    private fun mintLink() {
        id = token(); key = token()
        store.putString(Keys.id, id); store.putString(Keys.key, key)
    }

    /** 144 random bits as URL-safe text (24 characters), as on iPhone. */
    private fun token(): String {
        val bytes = ByteArray(18).also { SecureRandom().nextBytes(it) }
        return Base64.encodeToString(bytes, Base64.NO_WRAP).replace('+', '-').replace('/', '_')
    }

    // ── Sending ──
    /** Sends the current figures if they differ from what the page has, after a short settle. */
    fun refresh(immediately: Boolean = false) {
        if (!isOn) return
        pending?.cancel()
        pending = scope.launch {
            if (!immediately) delay(1500)
            sendNow()
        }
    }

    private suspend fun sendNow() {
        val payload = makePayload?.invoke()?.copy(channel = cleanChannel(channel)) ?: return
        if (!isOn || payload == lastSent) return
        val sentTo = id
        val ok = send("PUT", feedUrl, json.encodeToString(payload))
        if (!isOn || sentTo != id) return
        if (ok) { lastSent = payload; status = Status.Live(System.currentTimeMillis()) } else status = Status.Failed
    }

    private suspend fun send(method: String, url: String, body: String?): Boolean = withContext(Dispatchers.IO) {
        runCatching {
            val c = URL(url).openConnection() as HttpURLConnection
            c.requestMethod = method; c.connectTimeout = 15000; c.readTimeout = 15000
            c.setRequestProperty("Authorization", "Bearer $key")
            if (body != null) {
                c.doOutput = true
                c.setRequestProperty("Content-Type", "application/json")
                c.outputStream.use { it.write(body.toByteArray()) }
            }
            val code = c.responseCode
            c.disconnect()
            code in 200..299
        }.getOrDefault(false)
    }
}

// ── The figures (iOS TrackerViewModel.streamOverlayPayload) ──

private fun hex(argb: Int) = String.format("#%06X", argb and 0xFFFFFF)

fun MasteryCamo.displayName(): String = dataName() ?: L(nameKey)

/** The overlay's figures for `content` in `modeRaw` (empty or unplayed: `fallbackMode`). */
fun GameTracker.overlayPayload(content: StreamOverlay.Content, modeRaw: String, weaponId: Int?, fallbackMode: String): OverlayPayload? {
    if (catalog == null) return null
    val mode = modeRaw.takeIf { it in visibleModes } ?: fallbackMode
    val base = OverlayPayload(view = content.name, game = game.shortName, mode = L(modeNameKey(mode)), accent = hex(modeAccent(mode)))
    if (content == StreamOverlay.Content.weapon) {
        val id = weaponId ?: return null
        val weapon = weapon(id) ?: return null
        val row = camos(id, mode).flatMap(::leafItems).map {
            OverlayPayload.Camo(it.name.resolved(), it.imageURL ?: "", isCamoComplete(mode, id, it))
        } + completionistCamos(mode).mapIndexed { step, camo ->
            OverlayPayload.Camo(camo.displayName(), camo.imageURL ?: "", overlayCompletionistDone(mode, id, step))
        } + prestigeCamos.mapIndexed { i, camo ->
            OverlayPayload.Camo(prestigeCamoName(camo, id).resolved(), prestigeCamoImageURL(camo, id) ?: "", isPrestigeCamoComplete(id, i))
        }
        val levelText = L("ct.overlay.level", level(id), maxLevel(weapon))
        val badge = prestigeName(id)?.let { "${it.resolved()} · $levelText" } ?: levelText
        return base.copy(weapon = OverlayPayload.Weapon(
            name = weapon.name.resolved(), category = category(id)?.name?.resolved() ?: "", badge = badge,
            image = weapon.imageURL ?: "", camos = row, done = row.count { it.done }, total = row.size,
            next = overlayNext(weapon, mode),
        ))
    }
    val roster = launchRoster
    val steps = completionistCamos(mode).mapIndexed { i, camo ->
        OverlayPayload.Step(camo.displayName(), launchProgress(completionistCount(mode, i)).done, roster, hex(camo.color))
    }
    val mastery = if (!game.hasAccountMastery) emptyList() else masteryCamos(mode).take(3).mapIndexed { i, camo ->
        val tier = i + 1
        val p = masteryProgress(mode, tier)
        val total = maxOf(p.total, 1)
        OverlayPayload.Step(camo.displayName(), if (isMasteryAchieved(mode, tier)) total else minOf(p.done, p.total), total, hex(camo.color))
    }
    return base.copy(overview = OverlayPayload.Overview(trueCompletionFraction(mode), weaponCount(mode), steps, mastery))
}

/** A Completionist camo on this weapon; the final one counts the way the card's diamonds do. */
fun GameTracker.overlayCompletionistDone(mode: String, weaponId: Int, step: Int): Boolean =
    if (step >= 3) hasFinalCamo(mode, weaponId) else isCompletionistComplete(mode, weaponId, step)

/** What the weapon is on now: the next camo with its challenge and count, else the next Completionist camo. */
fun GameTracker.overlayNext(weapon: WeaponEntry, mode: String): OverlayPayload.Next? {
    val id = weapon.weaponId
    val camo = camos(id, mode).flatMap(::leafItems).firstOrNull { !isCamoComplete(mode, id, it) }
    if (camo != null) {
        val req = camo.requirement
        if (req != null) {
            val detail = req.byMode?.firstOrNull { it.mode == mode }?.description?.resolved() ?: req.description.resolved()
            return OverlayPayload.Next(camo.name.resolved(), detail, camoAmount(mode, id, camo), maxOf(req.amount, 1))
        }
        militaryLevel(mode, id, camo)?.let { lvl ->
            val gate = levelGate(lvl, id)
            val detail = if (gate.countsUnlocks) L("mw4.ui.camo_unlocks_reach", gate.value) else L("mw4.ui.camo_level_reach", gate.value)
            return OverlayPayload.Next(camo.name.resolved(), detail, minOf(level(id), lvl), maxOf(lvl, 1))
        }
        return OverlayPayload.Next(camo.name.resolved(), "", 0, 1)
    }
    val camosC = completionistCamos(mode)
    val step = camosC.indices.firstOrNull { !overlayCompletionistDone(mode, id, it) } ?: return null
    val req = completionistRequirement(mode, id, step)
    if (req != null) {
        return OverlayPayload.Next(camosC[step].displayName(), req.description.resolved(),
            minOf(completionistAmount(mode, id, step), req.amount), maxOf(req.amount, 1))
    }
    return OverlayPayload.Next(camosC[step].displayName(), "", 0, 1)
}
