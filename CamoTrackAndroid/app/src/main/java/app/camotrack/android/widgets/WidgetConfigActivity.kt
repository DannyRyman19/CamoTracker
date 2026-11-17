package app.camotrack.android.widgets

import android.appwidget.AppWidgetManager
import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.SystemBarStyle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.appwidget.GlanceAppWidgetManager
import androidx.glance.appwidget.state.getAppWidgetState
import androidx.glance.appwidget.state.updateAppWidgetState
import androidx.glance.state.PreferencesGlanceStateDefinition
import androidx.lifecycle.lifecycleScope
import app.camotrack.android.AppState
import app.camotrack.android.i18n.L
import app.camotrack.android.ui.AppPalette
import app.camotrack.android.ui.CamoTheme
import app.camotrack.android.ui.Ink
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking

/**
 * Setting up a widget (iOS's Edit Widget): the game it follows (the one open
 * in the app, or one game's own) and, for Mode progress, its mode. Optional:
 * a widget added without it follows the current game and the app's start mode.
 */
class WidgetConfigActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge(
            statusBarStyle = SystemBarStyle.dark(android.graphics.Color.TRANSPARENT),
            navigationBarStyle = SystemBarStyle.dark(android.graphics.Color.TRANSPARENT),
        )
        val appWidgetId = intent?.extras?.getInt(AppWidgetManager.EXTRA_APPWIDGET_ID, AppWidgetManager.INVALID_APPWIDGET_ID)
            ?: AppWidgetManager.INVALID_APPWIDGET_ID
        // Backing out leaves the widget as it is (or, on older phones, not added)
        setResult(RESULT_CANCELED, Intent().putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId))
        if (appWidgetId == AppWidgetManager.INVALID_APPWIDGET_ID) { finish(); return }

        val provider = AppWidgetManager.getInstance(this).getAppWidgetInfo(appWidgetId)?.provider?.className
        val picksMode = provider == ModeProgressReceiver::class.java.name
        val glanceId = runCatching { GlanceAppWidgetManager(this).getGlanceIdBy(appWidgetId) }.getOrNull()
        val saved = glanceId?.let { id ->
            runBlocking { runCatching { getAppWidgetState(this@WidgetConfigActivity, PreferencesGlanceStateDefinition, id) }.getOrNull() }
        }
        val games = AppState.games
        val modes = games.flatMap { it.modeIds }.distinct()
        val startGame = saved?.get(WidgetSync.GAME) ?: ""
        val startMode = saved?.get(WidgetSync.MODE)?.takeIf { it.isNotEmpty() } ?: AppState.mode

        setContent {
            CamoTheme(AppPalette()) {
                var game by remember { mutableStateOf(startGame) }
                var mode by remember { mutableStateOf(startMode) }
                Column(
                    Modifier.fillMaxSize().background(AppPalette().background).safeDrawingPadding()
                        .verticalScroll(rememberScrollState()).padding(20.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    Heading(L("widget.game"))
                    Option(L("widget.game.current"), game.isEmpty()) { game = "" }
                    games.forEach { g ->
                        val name = L("widget.game.${g.id}").takeIf { it != "widget.game.${g.id}" } ?: g.name.resolved()
                        Option(name, game == g.id) { game = g.id }
                    }
                    if (picksMode) {
                        Spacer(Modifier.height(12.dp))
                        Heading(L("widget.mode"))
                        // The game picked, or the current one, decides which modes there are
                        val shown = games.firstOrNull { it.id == game }?.modeIds ?: AppState.tracker.visibleModes
                        (shown.ifEmpty { modes }).forEach { m ->
                            Option(L("widget.mode.$m").takeIf { it != "widget.mode.$m" } ?: L("mw4.mode.$m"), mode == m) { mode = m }
                        }
                    }
                    Spacer(Modifier.height(16.dp))
                    Button(
                        onClick = { save(appWidgetId, game, if (picksMode) mode else null) },
                        modifier = Modifier.fillMaxWidth().height(50.dp),
                        colors = ButtonDefaults.buttonColors(containerColor = AppPalette().accent, contentColor = androidx.compose.ui.graphics.Color.White),
                    ) { Text(L("mw4.ui.done"), fontWeight = FontWeight.Bold, fontSize = 16.sp) }
                }
            }
        }
    }

    private fun save(appWidgetId: Int, game: String, mode: String?) {
        lifecycleScope.launch {
            runCatching {
                val manager = GlanceAppWidgetManager(this@WidgetConfigActivity)
                val id = manager.getGlanceIdBy(appWidgetId)
                updateAppWidgetState(this@WidgetConfigActivity, id) { prefs ->
                    prefs[WidgetSync.GAME] = game
                    if (mode != null) prefs[WidgetSync.MODE] = mode
                    prefs[WidgetSync.STAMP] = System.currentTimeMillis()
                }
                WidgetSync.widgets.forEach { widget ->
                    if (manager.getGlanceIds(widget.javaClass).contains(id)) widget.update(this@WidgetConfigActivity, id)
                }
            }
            setResult(RESULT_OK, Intent().putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId))
            finish()
        }
    }
}

@Composable
private fun Heading(text: String) {
    Text(text.uppercase(), color = Ink.muted, fontSize = 12.sp, fontWeight = FontWeight.Bold, modifier = Modifier.padding(top = 4.dp))
}

@Composable
private fun Option(label: String, selected: Boolean, onClick: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(10.dp)).background(AppPalette().surface)
            .clickable(onClick = onClick).padding(horizontal = 16.dp, vertical = 14.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(label, color = Ink.text, fontSize = 16.sp, modifier = Modifier.weight(1f))
        if (selected) Icon(Icons.Filled.Check, contentDescription = null, tint = AppPalette().accent)
    }
}
