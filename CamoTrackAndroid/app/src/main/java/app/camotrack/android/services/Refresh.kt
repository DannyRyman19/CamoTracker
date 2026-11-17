package app.camotrack.android.services

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import androidx.work.Constraints
import androidx.work.CoroutineWorker
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.NetworkType
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import app.camotrack.android.AssetSeeds
import app.camotrack.android.MainActivity
import app.camotrack.android.PrefsStore
import app.camotrack.android.R
import app.camotrack.android.core.DataService
import app.camotrack.android.core.GameRegistry
import app.camotrack.android.core.Manifest as DataManifest
import app.camotrack.android.i18n.L
import java.io.File
import java.util.concurrent.TimeUnit

/**
 * New seasons, events and camos while the app is closed (iOS's background
 * refresh): every few hours on a network, the picked game's manifest is
 * checked and newer files are downloaded and kept. If something changed and
 * the manifest doesn't mark it silent, a notification says so, in the
 * manifest's own words when it gives them. A push already sent for the same
 * announcement isn't repeated.
 */
object Refresh {
    private const val WORK = "camo-refresh"
    const val CHANNEL = "updates"

    fun schedule(context: Context) {
        val request = PeriodicWorkRequestBuilder<RefreshWorker>(6, TimeUnit.HOURS)
            .setConstraints(Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build())
            .build()
        WorkManager.getInstance(context).enqueueUniquePeriodicWork(WORK, ExistingPeriodicWorkPolicy.KEEP, request)
    }

    fun createChannel(context: Context) {
        val channel = NotificationChannel(CHANNEL, L("ct.android.channel.updates"), NotificationManager.IMPORTANCE_DEFAULT)
        context.getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
    }

    /** The notification's words, as on iOS: the manifest's where given, else built in. */
    fun text(catalogChanged: Boolean, changedModes: List<String>, announcement: DataManifest.Announcement?): Pair<String, String> {
        val areas = buildList {
            if (catalogChanged) add(L("mw4.ui.section.weapons"))
            changedModes.forEach { add(L("mw4.mode.$it")) }
        }
        val builtIn = if (areas.isEmpty()) L("mw4.notif.generic_body") else L("mw4.notif.body_format", areas.joinToString(", "))
        fun supplied(t: app.camotrack.android.core.LocalizedText?) = t?.resolved()?.trim()?.takeIf { it.isNotEmpty() }
        return (supplied(announcement?.title) ?: L("mw4.notif.title")) to (supplied(announcement?.body) ?: builtIn)
    }

    fun post(context: Context, title: String, body: String, link: String?) {
        if (ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) return
        val open = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            if (link != null) data = Uri.parse(link)
        }
        val tap = PendingIntent.getActivity(context, 0, open, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        val n = NotificationCompat.Builder(context, CHANNEL)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(title).setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setContentIntent(tap).setAutoCancel(true)
            .build()
        NotificationManagerCompat.from(context).notify(title.hashCode(), n)
    }
}

class RefreshWorker(context: Context, params: WorkerParameters) : CoroutineWorker(context, params) {
    override suspend fun doWork(): Result {
        val store = PrefsStore(applicationContext)
        val seeds = AssetSeeds(applicationContext)
        val game = GameRegistry.saved(GameRegistry.load(seeds), store)
        val data = DataService(game, File(File(applicationContext.filesDir, "data"), game.id), seeds)
        // What the app would start on (download or bundled, whichever is newer),
        // so a fresh install doesn't announce what it already has
        val known = game.modeIds.mapNotNull { mode -> data.load(mode)?.version?.let { mode to it } }.toMap()
        val result = runCatching { data.refreshIfNeeded(data.loadCatalog()?.version, known) }.getOrElse { return Result.retry() }
        val changed = result.modes.keys.sorted()
        if (result.catalog == null && changed.isEmpty()) return Result.success()
        val note = result.notification
        if (note?.silent == true || Push.covers(store, note)) return Result.success()
        val (title, body) = Refresh.text(result.catalog != null, changed, note)
        Refresh.post(applicationContext, title, body, note?.link)
        return Result.success()
    }
}
