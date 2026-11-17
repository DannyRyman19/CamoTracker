package app.camotrack.android.ui.hajin.scan

import android.content.Context
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.widget.Toast
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.core.content.FileProvider
import app.camotrack.android.AppState
import app.camotrack.android.hajin.scan.AndroidImages
import app.camotrack.android.hajin.scan.PhotoKind
import app.camotrack.android.hajin.scan.PhotoQuality
import app.camotrack.android.hajin.scan.PostMatchResult
import app.camotrack.android.hajin.scan.Pt
import app.camotrack.android.hajin.scan.ScanItem
import app.camotrack.android.hajin.scan.StashGrid
import app.camotrack.android.hajin.scan.StashRead
import app.camotrack.android.hajin.scan.StashScanner
import app.camotrack.android.hajin.scan.TextRead
import app.camotrack.android.hajin.scan.PostMatchReader
import app.camotrack.android.core.hajin.HajinStore
import app.camotrack.android.i18n.L
import app.camotrack.android.ui.Ink
import app.camotrack.android.ui.LocalPalette
import app.camotrack.android.ui.hajin.Hajin
import app.camotrack.android.ui.hajin.HajinColors
import app.camotrack.android.ui.sys
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import java.io.File

/**
 * The photo reader's flow (iOS HajinScanFlow + HajinScanHost): the intro
 * sheet, the picked photo and its framing screen, the reviews. One for the
 * app, started by any reader button; drawn over everything by
 * [HajinScanHost], so the Hajin screens underneath can come and go.
 */
object ScanFlow {
    var showsIntro by mutableStateOf(false)
    /** The photo being framed and read */
    var photo by mutableStateOf<PickedPhoto?>(null)
    /** A 3D Printer screen (no stash grid): read straight to the review */
    var textRead by mutableStateOf<TextRead?>(null)
    /** Working out what a picked photo shows */
    var sorting by mutableStateOf(false)

    /** The next picked photo replaces the framing screen's, rather than starting a scan. */
    internal var replacing = false
    internal var pickPhotos: () -> Unit = {}
    internal var takePhoto: () -> Unit = {}
    internal var hasCamera = false

    private var scanner: StashScanner? = null
    private val lock = Mutex()

    /** A reader button: the intro, which asks free players for an ad first. */
    fun requestScan() { showsIntro = true }

    /** Runs a blocking scanner call off the main thread, one at a time. */
    suspend fun <T> work(context: Context, block: (StashScanner) -> T): T = withContext(Dispatchers.Default) {
        lock.withLock {
            val s = scanner ?: StashScanner(context).also { scanner = it }
            block(s)
        }
    }

    /** The scan is over (Cancel, or the review applied): close everything and free the models. */
    fun end() {
        photo = null
        textRead = null
        sorting = false
        AppState.scope.launch(Dispatchers.Default) {
            lock.withLock {
                // Not if another scan has started meanwhile
                if (photo == null && !showsIntro) { scanner?.close(); scanner = null }
            }
        }
    }

    /** What My stash counts (resources, ingredients, valuables), for the readers. */
    fun stashItems(): List<ScanItem> =
        (Hajin.store.guide?.items ?: emptyList()).filter(HajinStore::inStash).map { ScanItem(it.id, it.name.resolved, it.kind, it.blueprint == true) }

    /** Every guide item (the backpack reader names gear and keys too). */
    fun guideItems(): List<ScanItem> =
        (Hajin.store.guide?.items ?: emptyList()).map { ScanItem(it.id, it.name.resolved, it.kind, it.blueprint == true) }

    /**
     * What the photo shows, from its text: a backpack goes to the framing
     * screen as one, a stash grid as the stash, anything else with have/need
     * counts (a 3D Printer recipe screen) straight to the review. No counts
     * either: framed as the stash, and the framing screen's switch puts a
     * wrong guess right. More photos than one: printer screens, read together.
     */
    fun route(context: Context, first: Bitmap, more: List<Bitmap> = emptyList()) {
        sorting = true
        AppState.scope.launch {
            val items = stashItems()
            val kind = runCatching { work(context) { it.route(first, items) } }.getOrElse { PhotoKind.Stash }
            when (kind) {
                PhotoKind.Backpack -> photo = PickedPhoto(first, postMatch = true)
                PhotoKind.Stash -> photo = PickedPhoto(first)
                is PhotoKind.Printer -> textRead = if (more.isEmpty()) kind.read
                    else runCatching { work(context) { it.readText(listOf(first) + more, items) } }.getOrDefault(kind.read)
            }
            sorting = false
        }
    }

    /** Photos from the picker: a new scan, or the framing screen's new photo. */
    internal fun picked(context: Context, uris: List<Uri>) {
        if (uris.isEmpty()) { replacing = false; return }
        val replace = replacing
        replacing = false
        AppState.scope.launch {
            val bitmaps = withContext(Dispatchers.IO) {
                // A new scan reads up to 10 printer screens; the framing screen takes one
                uris.take(if (replace) 1 else 10).mapNotNull { AndroidImages.decodeUpright(context, it) }
            }
            if (bitmaps.isEmpty()) {
                Toast.makeText(context, L("ct.android.hajin.scan_open_failed"), Toast.LENGTH_LONG).show()
                return@launch
            }
            showsIntro = false
            val current = photo
            if (replace && current != null) photo = PickedPhoto(bitmaps[0], current.frame.postMatch)
            else route(context, bitmaps[0], bitmaps.drop(1))
        }
    }

    /** A camera shot: kept with the recent photos for a rescan, then read. */
    internal fun captured(context: Context, file: File) {
        val replace = replacing
        replacing = false
        AppState.scope.launch {
            val bitmap = withContext(Dispatchers.IO) {
                AndroidImages.decodeUpright(context, Uri.fromFile(file))?.also { RecentPhotos.save(context, it) }.also { file.delete() }
            } ?: return@launch
            showsIntro = false
            val current = photo
            if (replace && current != null) photo = PickedPhoto(bitmap, current.frame.postMatch) else route(context, bitmap)
        }
    }

    /** One of the recent camera shots, read again. */
    internal fun recent(context: Context, file: File) {
        AppState.scope.launch {
            val bitmap = withContext(Dispatchers.IO) { AndroidImages.decodeUpright(context, Uri.fromFile(file)) } ?: return@launch
            showsIntro = false
            route(context, bitmap)
        }
    }
}

/** A photo being framed, with the framing screen's state kept beside it. */
class PickedPhoto(val bitmap: Bitmap, postMatch: Boolean = false) {
    val id = next++
    val frame = FrameState(postMatch)

    private companion object { var next = 0L }
}

/** What the framing screen has worked out for one photo (iOS HajinFrameState). */
class FrameState(postMatch: Boolean) {
    /** A backpack after a match (4 wide, to the post-match review) rather than the stash */
    var postMatch by mutableStateOf(postMatch)
    val columns: Int get() = if (postMatch) PostMatchReader.COLUMNS else StashGrid.COLUMNS
    var quality by mutableStateOf<List<PhotoQuality>>(emptyList())
    var corners by mutableStateOf(listOf(Pt(0.15, 0.25), Pt(0.85, 0.25), Pt(0.85, 0.75), Pt(0.15, 0.75)))
    var reading by mutableStateOf(false)
    /** Looking for the grid: true from the start, so the default frame never shows before the guess */
    var finding by mutableStateOf(true)
    var guessed = false
    /** Where the finder put the grid, before any dragging */
    var guess by mutableStateOf<List<Pt>?>(null)
    /** Set once the player drags a handle, so a late guess doesn't move it back */
    var moved = false
    /** Rows measured from the photo for the current frame (null until known) */
    var rowCount by mutableStateOf<Int?>(null)
    var result by mutableStateOf<StashRead?>(null)
    var postMatchResult by mutableStateOf<PostMatchResult?>(null)
}

/**
 * The last few stash photos taken with the camera, kept in the app (not the
 * gallery) so a scan can be run again on one (iOS HajinRecentPhotos).
 */
object RecentPhotos {
    const val LIMIT = 6

    private fun folder(context: Context) = File(context.filesDir, "ScanPhotos").apply { mkdirs() }

    /** Newest first. */
    fun all(context: Context): List<File> =
        (folder(context).listFiles() ?: emptyArray()).filter { it.extension == "jpg" }.sortedByDescending { it.name }

    fun save(context: Context, bitmap: Bitmap) {
        val name = "%013d.jpg".format(System.currentTimeMillis())
        runCatching { File(folder(context), name).outputStream().use { bitmap.compress(Bitmap.CompressFormat.JPEG, 85, it) } }
        all(context).drop(LIMIT).forEach { it.delete() }
    }

    fun remove(file: File) { file.delete() }

    /** A small copy for the strip. */
    fun thumbnail(file: File): Bitmap? = runCatching {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(file.path, bounds)
        val sample = maxOf(1, maxOf(bounds.outWidth, bounds.outHeight) / 300)
        BitmapFactory.decodeFile(file.path, BitmapFactory.Options().apply { inSampleSize = sample })
    }.getOrNull()
}

/**
 * Presents the stash photo reader (intro, framing screen, reviews) when a
 * reader button starts it. Drawn once, at the app root, over the tabs.
 */
@Composable
fun HajinScanHost() {
    val context = LocalContext.current
    val picker = rememberLauncherForActivityResult(ActivityResultContracts.PickMultipleVisualMedia(10)) { uris ->
        ScanFlow.picked(context, uris)
    }
    var shot by remember { mutableStateOf<File?>(null) }
    val camera = rememberLauncherForActivityResult(ActivityResultContracts.TakePicture()) { ok ->
        val file = shot
        shot = null
        if (ok && file != null) ScanFlow.captured(context, file) else { file?.delete(); ScanFlow.replacing = false }
    }
    // The text model, fetched by Play services if it isn't there yet
    LaunchedEffect(ScanFlow.showsIntro) { if (ScanFlow.showsIntro) app.camotrack.android.hajin.scan.MlKitTextReader.requestModel(context) }
    SideEffect {
        ScanFlow.hasCamera = context.packageManager.hasSystemFeature(PackageManager.FEATURE_CAMERA_ANY)
        ScanFlow.pickPhotos = {
            runCatching { picker.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)) }
        }
        ScanFlow.takePhoto = {
            val dir = File(context.cacheDir, "scan").apply { mkdirs() }
            val file = File(dir, "camera-${System.currentTimeMillis()}.jpg")
            val uri = FileProvider.getUriForFile(context, "${context.packageName}.share", file)
            shot = file
            runCatching { camera.launch(uri) }.onFailure {
                shot = null; ScanFlow.replacing = false
                Toast.makeText(context, L("ct.android.hajin.scan_no_camera"), Toast.LENGTH_LONG).show()
            }
        }
    }

    ScanFlow.photo?.let { picked ->
        key(picked.id) { FrameScreen(picked) }
    }
    ScanFlow.textRead?.let { read ->
        BackHandler { ScanFlow.end() }
        StashReview(
            found = read.counts, cash = read.cash, level = read.level,
            onBack = null, onDone = { ScanFlow.end() },
        )
    }
    if (ScanFlow.showsIntro) {
        BackHandler { ScanFlow.showsIntro = false }
        ScanIntro(onClose = { ScanFlow.showsIntro = false })
    }
    if (ScanFlow.sorting) SortingOverlay()
}

/** Over everything while a picked photo is looked at. */
@Composable
private fun SortingOverlay() {
    BackHandler {}
    Box(
        Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.55f))
            .clickable(interactionSource = remember { MutableInteractionSource() }, indication = null) {},
        contentAlignment = Alignment.Center,
    ) {
        Row(
            Modifier.clip(CircleShape).background(LocalPalette.current.surface2).padding(horizontal = 18.dp, vertical = 12.dp),
            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            CircularProgressIndicator(Modifier.size(20.dp), color = HajinColors.accent, strokeWidth = 2.5.dp)
            Text(L("mw4.ui.hajin.scan_reading"), style = sys(15f, FontWeight.SemiBold), color = Ink.text)
        }
    }
}
