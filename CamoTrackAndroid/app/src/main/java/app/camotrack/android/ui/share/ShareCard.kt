package app.camotrack.android.ui.share

import android.content.ClipData
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Diamond
import androidx.compose.material.icons.filled.Share
import androidx.compose.material.icons.filled.WorkspacePremium
import androidx.compose.material.icons.outlined.Diamond
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.graphics.ColorMatrix
import androidx.compose.ui.graphics.FilterQuality
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.Shadow
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.TransformOrigin
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.layer.drawLayer
import androidx.compose.ui.graphics.rememberGraphicsLayer
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import androidx.core.graphics.drawable.toBitmap
import app.camotrack.android.AppState
import app.camotrack.android.R
import app.camotrack.android.core.GameTracker
import app.camotrack.android.core.HexColor
import app.camotrack.android.core.Milestone
import app.camotrack.android.core.UnlockDate
import app.camotrack.android.core.WeaponEntry
import app.camotrack.android.i18n.L
import app.camotrack.android.ui.*
import coil.imageLoader
import coil.request.ImageRequest
import coil.request.SuccessResult
import com.google.zxing.BarcodeFormat
import com.google.zxing.EncodeHintType
import com.google.zxing.qrcode.QRCodeWriter
import com.google.zxing.qrcode.decoder.ErrorCorrectionLevel
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import java.io.File
import java.text.DateFormat
import java.util.Date

/** What's being shared: the Stats progress card, one weapon's card, or a milestone's. */
sealed interface ShareRequest {
    data object Progress : ShareRequest
    data class Weapon(val weaponId: Int, val mode: String) : ShareRequest
    data class Milestone(val milestone: app.camotrack.android.core.Milestone) : ShareRequest
}

/** The share card on screen, if any (shown over everything by [ShareSheetHost]). */
object Sharing {
    var request by mutableStateOf<ShareRequest?>(null)
    fun open(request: ShareRequest) { this.request = request }
}

/**
 * Progress and milestone cards to share (iOS ShareCard.swift): a picture of
 * where the player is, with the store link as a QR code and in the message
 * beside it, so every share is also a way in.
 */
object ShareCard {
    const val STORE_URL = "https://play.google.com/store/apps/details?id=app.camotrack.android"

    /** The message that goes with the picture, ending in the link. */
    fun message(line: String): String = line + "\n" + L("mw4.ui.share.tracked_with", STORE_URL)

    /** The store link as a QR code, one pixel per module (drawn without smoothing). */
    val qrCode: ImageBitmap? by lazy {
        runCatching {
            val matrix = QRCodeWriter().encode(STORE_URL, BarcodeFormat.QR_CODE, 0, 0,
                mapOf(EncodeHintType.ERROR_CORRECTION to ErrorCorrectionLevel.M, EncodeHintType.MARGIN to 0))
            val bitmap = Bitmap.createBitmap(matrix.width, matrix.height, Bitmap.Config.ARGB_8888)
            for (x in 0 until matrix.width) for (y in 0 until matrix.height) {
                bitmap.setPixel(x, y, if (matrix[x, y]) android.graphics.Color.BLACK else android.graphics.Color.WHITE)
            }
            bitmap.asImageBitmap()
        }.getOrNull()
    }

    suspend fun fetch(context: Context, url: String?): ImageBitmap? {
        if (url.isNullOrEmpty()) return null
        return runCatching {
            val result = context.imageLoader.execute(ImageRequest.Builder(context).data(url).allowHardware(false).build())
            (result as? SuccessResult)?.drawable?.toBitmap()?.asImageBitmap()
        }.getOrNull()
    }

    fun appIcon(context: Context): ImageBitmap? =
        runCatching { ContextCompat.getDrawable(context, R.mipmap.ic_launcher)?.toBitmap(120, 120)?.asImageBitmap() }.getOrNull()

    /** Writes the PNG to the cache and hands it and the message to the share sheet. */
    fun send(context: Context, image: ImageBitmap, message: String) {
        val dir = File(context.cacheDir, "share").apply { mkdirs() }
        val file = File(dir, "camo-track.png")
        val bitmap = image.asAndroidBitmap().let { if (it.config == Bitmap.Config.HARDWARE) it.copy(Bitmap.Config.ARGB_8888, false) else it }
        file.outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
        val uri = FileProvider.getUriForFile(context, "${context.packageName}.share", file)
        val send = Intent(Intent.ACTION_SEND).apply {
            type = "image/png"
            putExtra(Intent.EXTRA_STREAM, uri)
            putExtra(Intent.EXTRA_TEXT, message)
            clipData = ClipData.newRawUri("Camo Track", uri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        context.startActivity(Intent.createChooser(send, L("mw4.ui.share.title")))
    }

    // MARK: Progress

    data class Camo(val name: String, val gradient: List<Color>, val done: Int, val total: Int)
    data class Extra(val title: String, val done: Int, val total: Int)
    data class Track(val name: String?, val accent: Color, val fraction: Double, val camos: List<Camo>, val extras: List<Extra>)
    data class Tier(val name: String, val gradient: List<Color>, val achieved: Boolean)
    data class Mode(val id: String, val name: String, val accent: Color, val fraction: Double, val tiers: List<Tier>)
    data class Progress(
        val overall: Double, val tracks: List<Track>, val modes: List<Mode>,
        val global: Camo?, val gameCamos: List<Camo>, val hasMastery: Boolean,
    )

    fun progress(t: GameTracker): Progress {
        val visible = t.visibleModes
        val modes = visible.map { mode ->
            Mode(mode, modeName(mode), modeAccent(mode), t.trueCompletionFraction(mode),
                t.masteryCamos(mode).mapIndexed { index, camo -> Tier(camo.name, camo.colors, t.isMasteryAchieved(mode, index + 1)) })
        }
        val overall = if (modes.isEmpty()) 0.0 else modes.sumOf { it.fraction } / modes.size
        // MW4's camos are one track across modes; Black Ops modes are each their own
        val shared = t.game.sharedCamos == true
        val tracks = (if (shared) visible.take(1) else visible).map { mode ->
            val camos = t.completionistCamos(mode).mapIndexed { index, camo ->
                val count = if (index < GameTracker.COMPLETIONIST_STEP_COUNT) t.completionistCount(mode, index) else t.finalCamoCount(mode)
                val p = t.launchProgress(count, mode)
                Camo(camo.name, camo.colors, p.done, p.total)
            }.toMutableList()
            camos.lastOrNull()?.let { last ->
                if (last.done >= last.total) {
                    val full = t.fullRosterFinalProgress(mode)
                    camos += Camo(L("mw4.ui.stats.100_plus"), PlatinumColors, full.done, full.total)
                }
            }
            Track(if (shared) null else modeName(mode), modeAccent(mode), t.trueCompletionFraction(mode), camos,
                t.extraStats(mode).map { section ->
                    Extra(section.title?.resolved() ?: L("mw4.ui.section.camos"), section.rows.sumOf { it.done }, section.rows.sumOf { it.total })
                })
        }
        val gameCamos = t.gameCamoProgress.map { Camo(it.name.resolved(), colorsOf(it.gradient), it.done, it.total) }
        val global = if (t.game.hasAccountMastery) t.game.capstone?.let { capstone ->
            val colors = colorsOf(HexColor.parseAll(capstone.colors))
            val p = t.globalMasteryProgress
            Camo(capstone.name.resolved(), colors.ifEmpty { GoldColors }, p.done, p.total)
        } else null
        return Progress(overall, tracks, modes, global, gameCamos, t.game.hasAccountMastery)
    }

    fun progressMessage(t: GameTracker, data: Progress): String =
        message(L("mw4.ui.share.progress_line", (data.overall * 100).toInt()).replace("MW4", t.game.shortName))

    // MARK: Weapon

    data class WeaponCamo(val name: String, val swatch: ImageBitmap?, val done: Boolean)
    data class Step(val name: String, val gradient: List<Color>, val date: UnlockDate?, val took: String?)
    data class Weapon(
        val name: String, val className: String?, val level: Pair<String, String>?, val picture: ImageBitmap?,
        val mode: String?, val accent: Color, val camos: List<WeaponCamo>, val steps: List<Step>,
    ) {
        val done: Int get() = camos.count { it.done }
    }

    suspend fun weapon(context: Context, t: GameTracker, weapon: WeaponEntry, mode: String): Weapon = coroutineScope {
        val id = weapon.weaponId
        val items = t.camos(id, mode).flatMap(t::leafItems)
        val swatches = items.map { item -> async { fetch(context, item.imageURL) } }
        val picture = async { fetch(context, weapon.imageURL) }
        val camos = items.zip(swatches.awaitAll()).map { (item, swatch) ->
            WeaponCamo(item.name.resolved(), swatch, t.isCamoComplete(mode, id, item))
        }
        val track = t.completionist(mode)
        val chain = (0 until GameTracker.COMPLETIONIST_STEP_COUNT).map { track.steps[it] to t.isCompletionistComplete(mode, id, it) } +
            (if (t.finalEnabled(mode)) listOf(track.final to t.hasFinalCamo(mode, id)) else emptyList())
        val steps = chain.mapIndexedNotNull { step, (camo, done) ->
            if (!done) null else Step(camo.name, camo.colors, t.completionistUnlockedDate(mode, id, step), t.completionistDuration(mode, id, step)?.text())
        }
        Weapon(
            weapon.name.resolved(), t.category(id)?.name?.resolved(), levelLine(t, weapon), picture.await(),
            if (t.game.sharedCamos == true) null else mode, modeAccent(mode), camos, steps,
        )
    }

    private fun levelLine(t: GameTracker, weapon: WeaponEntry): Pair<String, String>? {
        if (t.quickTick) return null
        val id = weapon.weaponId
        val unlocks = t.countsUnlocks(id)
        val level = t.level(id)
        val max = t.maxLevel(weapon)
        val shown = if (unlocks) GameTracker.unlocks(level) else level
        val shownMax = if (unlocks) GameTracker.unlocks(max) else max
        val label = t.prestigeName(id)?.resolved() ?: L(if (unlocks) "mw4.ui.weapon_unlocks" else "mw4.ui.weapon_level")
        return label to "$shown/$shownMax"
    }

    fun weaponMessage(t: GameTracker, data: Weapon): String =
        message(L("mw4.ui.share.weapon_line", data.name, t.game.shortName, data.done, data.camos.size))

    // MARK: Milestone

    data class MilestoneCard(
        val banner: BannerText, val mode: String?, val weaponName: String?, val picture: ImageBitmap?, val camo: ImageBitmap?,
    )

    /** The weapon a milestone is about, and its camo's picture. */
    private fun details(m: Milestone): Pair<Int?, String?> = when (m) {
        is Milestone.CamosComplete -> m.weaponId to null
        is Milestone.CompletionistUnlocked -> m.weaponId to m.camo.imageURL
        is Milestone.FinalUnlocked -> m.weaponId to m.camo.imageURL
        is Milestone.WeaponMasteryUnlocked -> m.weaponId to m.camo.imageURL
        is Milestone.MasteryUnlocked -> null to m.camo.imageURL
        is Milestone.HundredPlus -> null to null
        is Milestone.GlobalMastery -> null to m.capstone.imageURL
    }

    suspend fun milestone(context: Context, t: GameTracker, m: Milestone): MilestoneCard = coroutineScope {
        val (weaponId, imageURL) = details(m)
        val weapon = weaponId?.let(t::weapon)
        val picture = async { fetch(context, weapon?.imageURL) }
        val camo = async { fetch(context, imageURL) }
        MilestoneCard(bannerText(m), m.shareMode, weapon?.name?.resolved(), picture.await(), camo.await())
    }

    fun milestoneMessage(t: GameTracker, m: Milestone, banner: BannerText): String {
        val context = listOfNotNull(t.game.shortName, m.shareMode?.let(::modeName)).joinToString(" ")
        val name = details(m).first?.let { t.weapon(it)?.name?.resolved() }
        val line = if (name != null) message(L("mw4.ui.share.milestone_weapon", banner.title, name))
        else message("${banner.title}. ${banner.subtitle}")
        return "$context: $line"
    }
}

// MARK: - The sheet

/** The card as it will be sent, with the Share button under it (iOS ShareCardSheet). */
@Composable
fun ShareSheetHost() {
    val request = Sharing.request ?: return
    val context = LocalContext.current
    val t = AppState.tracker
    var card by remember(request) { mutableStateOf<(@Composable () -> Unit)?>(null) }
    var message by remember(request) { mutableStateOf("") }
    var image by remember(request) { mutableStateOf<ImageBitmap?>(null) }
    val icon = remember { ShareCard.appIcon(context) }
    // The palette in force where the request was made, for cards drawn outside the screen's theme
    val palette = LocalPalette.current

    LaunchedEffect(request) {
        when (request) {
            ShareRequest.Progress -> {
                val data = ShareCard.progress(t)
                message = ShareCard.progressMessage(t, data)
                card = { ProgressCardView(data, icon) }
            }
            is ShareRequest.Weapon -> {
                val weapon = t.weapon(request.weaponId) ?: run { Sharing.request = null; return@LaunchedEffect }
                val data = ShareCard.weapon(context, t, weapon, request.mode)
                message = ShareCard.weaponMessage(t, data)
                card = { WeaponCardView(data, icon) }
            }
            is ShareRequest.Milestone -> {
                val data = ShareCard.milestone(context, t, request.milestone)
                message = ShareCard.milestoneMessage(t, request.milestone, data.banner)
                card = { MilestoneCardView(data, icon) }
            }
        }
    }

    Dialog(onDismissRequest = { Sharing.request = null }, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        CompositionLocalProvider(LocalPalette provides palette) {
            Column(Modifier.fillMaxSize().background(palette.background).systemBarsPadding()) {
                Row(Modifier.fillMaxWidth().height(52.dp).padding(horizontal = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                    TextButton(onClick = { Sharing.request = null }) { Text(L("mw4.ui.done"), color = CamoGold) }
                    Text(L("mw4.ui.share.title"), style = sys(17f, FontWeight.SemiBold), color = Ink.text, textAlign = TextAlign.Center,
                        modifier = Modifier.weight(1f))
                    Spacer(Modifier.width(72.dp))
                }
                Column(
                    Modifier.fillMaxSize().padding(20.dp),
                    horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(20.dp, Alignment.CenterVertically),
                ) {
                    val content = card
                    if (content == null) {
                        CircularProgressIndicator(color = CamoGold)
                    } else {
                        CardCapture(onCaptured = { image = it }, content = content)
                        val ready = image != null
                        Row(
                            Modifier.widthIn(max = 420.dp).fillMaxWidth().clip(RoundedCornerShape(12.dp))
                                .background(if (ready) CamoGold else CamoGold.copy(alpha = 0.4f))
                                .clickable(enabled = ready) { image?.let { ShareCard.send(context, it, message) } }
                                .padding(vertical = 14.dp),
                            horizontalArrangement = Arrangement.Center, verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Icon(Icons.Filled.Share, null, tint = palette.background, modifier = Modifier.size(18.dp))
                            Spacer(Modifier.width(8.dp))
                            Text(L("mw4.ui.share.button"), style = sys(17f, FontWeight.SemiBold), color = palette.background)
                        }
                    }
                }
            }
        }
    }
}

/**
 * Draws [content] as a 360 x 450 card at 3x (1080 x 1350, whatever the
 * phone's density), shown scaled to fit, and hands back the picture once
 * it's drawn.
 */
@Composable
private fun CardCapture(onCaptured: (ImageBitmap) -> Unit, content: @Composable () -> Unit) {
    val layer = rememberGraphicsLayer()
    val outer = LocalDensity.current
    BoxWithConstraints(Modifier.widthIn(max = 420.dp).fillMaxWidth()) {
        val width = minOf(maxWidth, ((maxHeight.value - 90f) * 0.8f).coerceAtLeast(200f).dp)
        val scale = with(outer) { width.toPx() } / 1080f
        Box(
            Modifier.align(Alignment.Center).size(width, width * 1.25f)
                .shadow(14.dp, RoundedCornerShape(12.dp)).clip(RoundedCornerShape(12.dp)),
        ) {
            CompositionLocalProvider(LocalDensity provides Density(3f, 1f)) {
                Box(
                    Modifier
                        .wrapContentSize(Alignment.TopStart, unbounded = true)
                        .graphicsLayer { scaleX = scale; scaleY = scale; transformOrigin = TransformOrigin(0f, 0f) }
                        .drawWithContent {
                            layer.record { this@drawWithContent.drawContent() }
                            drawLayer(layer)
                        }
                        .requiredSize(360.dp, 450.dp),
                ) { content() }
            }
        }
    }
    LaunchedEffect(Unit) {
        delay(400)
        onCaptured(layer.toImageBitmap())
    }
}

// MARK: - Card parts

@Composable
private fun CardFrame(glow: Color, content: @Composable ColumnScope.() -> Unit) {
    val palette = LocalPalette.current
    Column(
        Modifier.fillMaxSize()
            .background(palette.background)
            .background(Brush.radialGradient(listOf(glow.copy(alpha = 0.32f), Color.Transparent), center = Offset(540f, 0f), radius = 960f))
            .padding(20.dp),
        content = content,
    )
}

/** Today, as on the card's header. */
private fun today(): String = DateFormat.getDateInstance(DateFormat.MEDIUM, appLocale).format(Date())

/** The app's mark and name across the top; the mode when the card is about one. */
@Composable
private fun CardHeader(icon: ImageBitmap?, mode: String? = null) {
    val t = AppState.tracker
    val accent = hexColor(t.game.theme?.accent) ?: mode?.let(::modeAccent) ?: CamoGold
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        if (icon != null) Image(icon, null, Modifier.size(30.dp).clip(RoundedCornerShape(7.dp)))
        Column(Modifier.weight(1f)) {
            Text("Camo Track", style = displayStyle(15.sp), color = Ink.text, maxLines = 1)
            Row(horizontalArrangement = Arrangement.spacedBy(5.dp)) {
                Text(if (mode == null) t.game.name.resolved() else t.game.shortName, style = displayStyle(12.sp), color = accent, maxLines = 1)
                if (mode != null) Text(modeName(mode), style = displayStyle(12.sp), color = Ink.muted, maxLines = 1)
            }
        }
        Text(today(), style = sys(11f, FontWeight.SemiBold, mono = true), color = Ink.muted)
    }
}

/** The QR code and where it goes, along the foot. */
@Composable
private fun CardFooter() {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        ShareCard.qrCode?.let { qr ->
            Box(Modifier.clip(RoundedCornerShape(4.dp)).background(Color.White).padding(3.dp)) {
                Image(qr, null, Modifier.size(44.dp), filterQuality = FilterQuality.None)
            }
        }
        Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(L("mw4.ui.share.footer_title"), style = sys(12f, FontWeight.SemiBold), color = Ink.text)
            Text(L("mw4.ui.share.footer_subtitle"), style = sys(10.5f), color = Ink.muted)
        }
    }
}

/** Text in a camo's colours, held still (a card is one frame). */
@Composable
private fun CamoText(text: String, gradient: List<Color>, style: TextStyle, modifier: Modifier = Modifier, textAlign: TextAlign? = null, maxLines: Int = 1) {
    val colors = if (gradient.size > 1) gradient else listOf(gradient.firstOrNull() ?: Ink.text, gradient.firstOrNull() ?: Ink.text)
    Text(
        text, modifier = modifier, maxLines = maxLines, overflow = TextOverflow.Ellipsis, textAlign = textAlign,
        style = style.copy(brush = Brush.horizontalGradient(colors), shadow = Shadow(colors.first().copy(alpha = 0.5f), blurRadius = 10f)),
    )
}

/** A completion ring without the app ring's animation. */
@Composable
private fun StillRing(fraction: Double, accent: Color, lineWidth: Float, modifier: Modifier) {
    val track = LocalPalette.current.surface2
    Canvas(modifier) {
        val stroke = lineWidth.dp.toPx()
        val inset = stroke / 2
        val arc = Size(size.width - stroke, size.height - stroke)
        drawCircle(track, radius = (size.minDimension - stroke) / 2, style = Stroke(stroke))
        if (fraction > 0) {
            val brush = if (fraction >= 1) Brush.sweepGradient(GoldColors + CamoGold) else Brush.linearGradient(listOf(accent, accent))
            rotate(-90f) {
                drawArc(brush, 0f, 360f * fraction.toFloat().coerceAtMost(1f), false, Offset(inset, inset), arc, style = Stroke(stroke, cap = StrokeCap.Round))
            }
        }
    }
}

@Composable
private fun Tile(gradient: List<Color>, done: Int, modifier: Modifier, content: @Composable ColumnScope.() -> Unit) {
    val palette = LocalPalette.current
    Column(
        modifier.clip(RoundedCornerShape(6.dp)).background(palette.surface)
            .border(1.dp, (gradient.firstOrNull() ?: Ink.muted).copy(alpha = if (done > 0) 0.55f else 0.15f), RoundedCornerShape(6.dp)),
        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center, content = content,
    )
}

// MARK: - Progress card

@Composable
private fun ProgressCardView(data: ShareCard.Progress, icon: ImageBitmap?) {
    val compact = data.tracks.size > 1
    CardFrame(data.modes.firstOrNull()?.accent ?: ModeColors.multiplayer) {
        CardHeader(icon)
        Spacer(Modifier.height(if (compact) 8.dp else 14.dp))
        if (compact) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Box(Modifier.size(48.dp), contentAlignment = Alignment.Center) {
                    StillRing(data.overall, CamoGold, 6f, Modifier.fillMaxSize())
                    Text(percentText(data.overall), style = sys(14f, FontWeight.Bold, mono = true), color = Ink.text)
                }
                Text(L("mw4.ui.stats.overall").uppercase(appLocale), style = sys(12f, FontWeight.Bold), color = Ink.muted)
            }
        } else {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                Box(Modifier.size(92.dp), contentAlignment = Alignment.Center) {
                    StillRing(data.overall, CamoGold, 9f, Modifier.fillMaxSize())
                    Text(percentText(data.overall), style = sys(22f, FontWeight.Bold, mono = true), color = Ink.text)
                }
                Column(verticalArrangement = Arrangement.spacedBy(7.dp)) {
                    for (mode in data.modes) {
                        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                            Icon(modeIcon(mode.id), null, tint = mode.accent, modifier = Modifier.size(13.dp))
                            Text(mode.name, style = sys(12f, FontWeight.SemiBold), color = Ink.text, maxLines = 1, modifier = Modifier.weight(1f))
                            if (data.hasMastery) Row(horizontalArrangement = Arrangement.spacedBy(2.dp)) {
                                for (tier in mode.tiers) {
                                    Icon(if (tier.achieved) Icons.Filled.Diamond else Icons.Outlined.Diamond, null,
                                        tint = if (tier.achieved) tier.gradient.firstOrNull() ?: mode.accent else Ink.muted.copy(alpha = 0.5f),
                                        modifier = Modifier.size(10.dp))
                                }
                            }
                            Text(percentText(mode.fraction), style = sys(12f, FontWeight.Bold, mono = true), color = mode.accent,
                                textAlign = TextAlign.End, modifier = Modifier.width(38.dp))
                        }
                    }
                    data.global?.let { global ->
                        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                            Icon(Icons.Filled.WorkspacePremium, null, tint = global.gradient.firstOrNull() ?: CamoGold, modifier = Modifier.size(13.dp))
                            CamoText(global.name, global.gradient, displayStyle(12.sp), Modifier.weight(1f))
                            Text("${global.done}/${global.total}", style = sys(12f, FontWeight.Bold, mono = true),
                                color = if (global.done > 0) Ink.text else Ink.muted)
                        }
                    }
                }
            }
        }
        Spacer(Modifier.height(if (compact) 8.dp else 14.dp))
        Column(verticalArrangement = Arrangement.spacedBy(if (compact) 8.dp else 0.dp)) {
            for (track in data.tracks) {
                if (track.name != null) {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.padding(bottom = 4.dp)) {
                        Text(track.name, style = sys(11f, FontWeight.Bold), color = track.accent)
                        Spacer(Modifier.weight(1f))
                        if (track.extras.isNotEmpty()) {
                            Text(track.extras.joinToString(" · ") { "${it.title} ${it.done}/${it.total}" }, style = sys(10f, FontWeight.SemiBold, mono = true),
                                color = Ink.muted, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f, fill = false))
                        }
                        Text(percentText(track.fraction), style = sys(11f, FontWeight.Bold, mono = true), color = track.accent)
                    }
                }
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    for (camo in track.camos) {
                        Tile(camo.gradient, camo.done, Modifier.weight(1f).padding(0.dp)) {
                            Spacer(Modifier.height(if (data.tracks.size >= 4) 3.dp else if (compact) 5.dp else 8.dp))
                            // Shrunk to fit its tile, as iOS's minimumScaleFactor (one line, never cut)
                            val fit = (12f / camo.name.length).coerceIn(0.6f, 1f)
                            CamoText(camo.name, camo.gradient, displayStyle((if (compact) 9.5f else 11f).times(fit).sp), Modifier.padding(horizontal = 2.dp))
                            Spacer(Modifier.height(if (compact) 1.dp else 3.dp))
                            Text("${camo.done}/${camo.total}", style = sys(if (compact) 11f else 13f, FontWeight.Bold, mono = true),
                                color = if (camo.done > 0) Ink.text else Ink.muted, maxLines = 1)
                            Spacer(Modifier.height(if (data.tracks.size >= 4) 3.dp else if (compact) 5.dp else 8.dp))
                        }
                    }
                }
            }
        }
        if (data.gameCamos.isNotEmpty()) {
            Spacer(Modifier.height(if (compact) 8.dp else 14.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                for (camo in data.gameCamos) {
                    Tile(camo.gradient, camo.done, Modifier.weight(1f)) {
                        Row(Modifier.padding(horizontal = 4.dp, vertical = 6.dp), horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                            CamoText(camo.name, camo.gradient, displayStyle(11.sp), Modifier.weight(1f, fill = false))
                            Text("${camo.done}/${camo.total}", style = sys(12f, FontWeight.Bold, mono = true), color = if (camo.done > 0) Ink.text else Ink.muted)
                        }
                    }
                }
            }
        }
        Spacer(Modifier.weight(1f))
        CardFooter()
    }
}

// MARK: - Milestone card

@Composable
private fun MilestoneCardView(data: ShareCard.MilestoneCard, icon: ImageBitmap?) {
    val banner = data.banner
    val gradient = banner.gradient.ifEmpty { GoldColors }
    val main = gradient.first()
    Box(Modifier.fillMaxSize()) {
        CardFrame(main) {
            CardHeader(icon, data.mode)
            Spacer(Modifier.weight(1f))
            Box(Modifier.fillMaxWidth().height(150.dp), contentAlignment = Alignment.Center) {
                when {
                    data.picture != null -> Image(data.picture, null, Modifier.widthIn(max = 300.dp).heightIn(max = 140.dp), contentScale = ContentScale.Fit)
                    data.camo != null -> Image(data.camo, null, Modifier.size(130.dp).clip(RoundedCornerShape(26.dp)), contentScale = ContentScale.Crop)
                    else -> Icon(banner.icon, null, tint = main, modifier = Modifier.size(80.dp))
                }
            }
            Spacer(Modifier.weight(1f))
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(14.dp, Alignment.CenterHorizontally), verticalAlignment = Alignment.CenterVertically) {
                if (data.picture != null && data.camo != null) {
                    Image(data.camo, null, Modifier.size(54.dp).clip(RoundedCornerShape(12.dp)).border(1.5.dp, main.copy(alpha = 0.6f), RoundedCornerShape(12.dp)),
                        contentScale = ContentScale.Crop)
                }
                CamoText(banner.title, gradient, displayStyle(30.sp), textAlign = TextAlign.Center, maxLines = 2, modifier = Modifier.weight(1f, fill = false))
            }
            Text(
                data.weaponName ?: banner.subtitle,
                style = if (data.weaponName == null) sys(14f) else displayStyle(20.sp),
                color = if (data.weaponName == null) Ink.muted else Ink.text, textAlign = TextAlign.Center,
                modifier = Modifier.fillMaxWidth().padding(top = 8.dp, start = 10.dp, end = 10.dp),
            )
            Spacer(Modifier.weight(1f))
            CardFooter()
        }
        // Inset and rounded: apps show shared pictures with rounded corners
        Box(Modifier.fillMaxSize().padding(10.dp).border(2.dp, Brush.linearGradient(gradient.map { it.copy(alpha = 0.45f) }), RoundedCornerShape(22.dp)))
    }
}

// MARK: - Weapon card

private val Grayscale = ColorFilter.colorMatrix(ColorMatrix().apply { setToSaturation(0f) })

@Composable
private fun WeaponCardView(data: ShareCard.Weapon, icon: ImageBitmap?) {
    val palette = LocalPalette.current
    CardFrame(data.accent) {
        CardHeader(icon, data.mode)
        Spacer(Modifier.height(10.dp))
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                Text(data.name, style = displayStyle(24.sp), color = Ink.text, maxLines = 1, overflow = TextOverflow.Ellipsis)
                data.className?.let { Text(it, style = sys(11.5f, FontWeight.SemiBold), color = Ink.muted, maxLines = 1) }
                data.level?.let { (label, value) ->
                    Row(horizontalArrangement = Arrangement.spacedBy(5.dp), verticalAlignment = Alignment.CenterVertically) {
                        Text(label, style = sys(11.5f, FontWeight.SemiBold), color = Ink.muted, maxLines = 1)
                        Text(value, style = sys(12f, FontWeight.Bold, mono = true), color = data.accent, maxLines = 1)
                    }
                }
            }
            Box(Modifier.size(50.dp), contentAlignment = Alignment.Center) {
                StillRing(if (data.camos.isEmpty()) 0.0 else data.done.toDouble() / data.camos.size, data.accent, 5f, Modifier.fillMaxSize())
                Text("${data.done}/${data.camos.size}", style = sys(12f, FontWeight.Bold, mono = true), color = Ink.text)
            }
        }
        data.picture?.let {
            Spacer(Modifier.height(10.dp))
            Image(it, null, Modifier.fillMaxWidth().heightIn(max = 92.dp), contentScale = ContentScale.Fit)
        }
        Spacer(Modifier.height(10.dp))
        // Military on one row, Specials on the next, as MW4 has 8 + 3
        Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp)) {
            for (row in data.camos.chunked(8)) {
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    for (camo in row) {
                        val shape = RoundedCornerShape(7.dp)
                        Box(Modifier.size(33.dp).clip(shape).background(palette.surface2)
                            .then(if (camo.done) Modifier.border(1.2.dp, data.accent.copy(alpha = 0.7f), shape) else Modifier)) {
                            camo.swatch?.let {
                                Image(it, null, Modifier.fillMaxSize().alpha(if (camo.done) 1f else 0.28f), contentScale = ContentScale.Crop,
                                    colorFilter = if (camo.done) null else Grayscale)
                            }
                        }
                    }
                }
            }
        }
        if (data.steps.isNotEmpty()) {
            Spacer(Modifier.height(10.dp))
            Column(
                Modifier.fillMaxWidth().clip(RoundedCornerShape(6.dp)).background(palette.surface).padding(horizontal = 10.dp, vertical = 8.dp),
                verticalArrangement = Arrangement.spacedBy(7.dp),
            ) {
                for (step in data.steps) {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Icon(Icons.Filled.Diamond, null, tint = step.gradient.firstOrNull() ?: data.accent, modifier = Modifier.size(10.dp))
                        CamoText(step.name, step.gradient, displayStyle(14.sp), Modifier.weight(1f))
                        step.date?.let { Text(it.text(), style = sys(11f, FontWeight.SemiBold, mono = true), color = Ink.muted) }
                        step.took?.let {
                            Text(it, style = sys(11.5f, FontWeight.Bold, mono = true), color = Ink.text, textAlign = TextAlign.End,
                                modifier = Modifier.widthIn(min = 58.dp))
                        }
                    }
                }
            }
        }
        Spacer(Modifier.weight(1f))
        CardFooter()
    }
}

