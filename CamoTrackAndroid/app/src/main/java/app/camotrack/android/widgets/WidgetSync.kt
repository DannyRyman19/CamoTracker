package app.camotrack.android.widgets

import android.content.Context
import androidx.datastore.preferences.core.longPreferencesKey
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.GlanceAppWidgetManager
import androidx.glance.appwidget.state.updateAppWidgetState
import app.camotrack.android.AppState
import app.camotrack.android.i18n.Strings
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File

/**
 * Keeps the widgets' snapshot in step with the app (iOS WidgetSync): rebuilt
 * shortly after any change to progress, the pin, the modes played, the game
 * or the language, written only when it actually differs, and the widgets
 * told to redraw.
 */
object WidgetSync {
    /** Each widget's own state: its picked game ("" or none: the current one) and mode, and a stamp bumped to redraw it. */
    val GAME = stringPreferencesKey("game")
    val MODE = stringPreferencesKey("mode")
    val STAMP = longPreferencesKey("stamp")

    private lateinit var app: Context
    private var pending: Job? = null

    fun start(context: Context) { app = context.applicationContext }

    /** Rebuilds the snapshot once changes settle (~0.6 s). */
    fun refresh() {
        if (!::app.isInitialized) return
        pending?.cancel()
        pending = AppState.scope.launch {
            delay(600)
            val snapshot = runCatching {
                AppState.tracker.widgetSnapshot(AppState.mode) { key, args -> Strings.get(key, *args) }
            }.getOrNull() ?: return@launch
            if (write(app, snapshot)) redraw(app)
        }
    }

    /** Writes the current game's file and this game's own; true when either changed. */
    suspend fun write(context: Context, snapshot: WidgetSnapshot): Boolean = withContext(Dispatchers.IO) {
        val text = WidgetSnapshot.encode(snapshot)
        var changed = false
        for (game in listOf(null, snapshot.game).distinct()) {
            val file = WidgetSnapshot.file(context, game)
            if (file.exists() && runCatching { file.readText() }.getOrNull() == text) continue
            file.parentFile?.mkdirs()
            val temp = File(file.parentFile, file.name + ".tmp")
            temp.writeText(text)
            if (!temp.renameTo(file)) { file.delete(); temp.renameTo(file) }
            changed = true
        }
        changed
    }

    val widgets: List<GlanceAppWidget> get() = listOf(PinnedWeaponWidget(), ModeProgressWidget(), CompletionWidget())

    /** Every placed widget re-reads its snapshot. */
    suspend fun redraw(context: Context) {
        val manager = GlanceAppWidgetManager(context)
        for (widget in widgets) {
            for (id in runCatching { manager.getGlanceIds(widget.javaClass) }.getOrDefault(emptyList())) {
                updateAppWidgetState(context, id) { it[STAMP] = System.currentTimeMillis() }
                widget.update(context, id)
            }
        }
    }
}
