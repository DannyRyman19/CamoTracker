package app.camotrack.android.ui.hajin.scan

import android.content.ActivityNotFoundException
import android.content.ClipData
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.net.Uri
import android.os.Build
import android.widget.Toast
import androidx.core.content.FileProvider
import app.camotrack.android.BuildConfig
import app.camotrack.android.hajin.scan.ScanReport
import app.camotrack.android.i18n.L
import app.camotrack.android.ui.SupportMail
import java.io.File
import kotlin.math.max
import kotlin.math.roundToInt

/**
 * "Help improve the reader?" (iOS HajinScanReport.outgoing): the photo and
 * the reader's working as an email to support, offered after Update in the
 * review. Nothing leaves the phone unless the player sends it. With no email
 * app, the share sheet instead, with the address to send to.
 */
object ScanReportMail {
    const val SUBJECT = "MW4 Tracker: stash reader report"

    fun send(
        context: Context, report: ScanReport, photo: Bitmap?, had: Map<String, Int>, edited: Map<String, Int>,
        skipped: Set<String>, swapped: Map<String, String>,
    ) {
        val json = report.json(
            had, edited, skipped, swapped,
            app = "${BuildConfig.VERSION_NAME} (${BuildConfig.VERSION_CODE})", android = Build.VERSION.RELEASE,
            device = "${Build.MANUFACTURER} ${Build.MODEL}",
        )
        val dir = File(context.cacheDir, "scan/report-${System.currentTimeMillis()}").apply { mkdirs() }
        val files = mutableListOf<File>()
        photo?.let { p ->
            // The photo, at most 2400 px on its long side
            val scale = minOf(1.0, 2400.0 / max(p.width, p.height))
            val out = if (scale < 1) Bitmap.createScaledBitmap(p, (p.width * scale).roundToInt(), (p.height * scale).roundToInt(), true) else p
            val file = File(dir, "stash.jpg")
            runCatching { file.outputStream().use { out.compress(Bitmap.CompressFormat.JPEG, 85, it) } }.onSuccess { files += file }
        }
        File(dir, "stash-report.json").also { it.writeText(json); files += it }
        val uris = ArrayList<Uri>(files.map { FileProvider.getUriForFile(context, "${context.packageName}.share", it) })

        fun intent(mailOnly: Boolean) = Intent(Intent.ACTION_SEND_MULTIPLE).apply {
            type = "application/octet-stream"
            putExtra(Intent.EXTRA_EMAIL, arrayOf(SupportMail.ADDRESS))
            putExtra(Intent.EXTRA_SUBJECT, SUBJECT)
            putExtra(Intent.EXTRA_TEXT, if (mailOnly) L("mw4.ui.hajin.send_scan_body") else L("mw4.ui.hajin.send_scan_share", SupportMail.ADDRESS))
            putParcelableArrayListExtra(Intent.EXTRA_STREAM, uris)
            clipData = ClipData.newRawUri(null, uris[0]).also { c -> uris.drop(1).forEach { c.addItem(ClipData.Item(it)) } }
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            // Only email apps answer a mailto: selector
            if (mailOnly) selector = Intent(Intent.ACTION_SENDTO, Uri.parse("mailto:"))
        }
        try {
            context.startActivity(intent(mailOnly = true).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        } catch (_: ActivityNotFoundException) {
            try {
                context.startActivity(Intent.createChooser(intent(mailOnly = false), null).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            } catch (_: ActivityNotFoundException) {
                Toast.makeText(context, L("ct.android.no_mail"), Toast.LENGTH_LONG).show()
            }
        }
    }
}
