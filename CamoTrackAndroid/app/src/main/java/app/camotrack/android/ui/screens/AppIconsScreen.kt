package app.camotrack.android.ui.screens

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.camotrack.android.AppState
import app.camotrack.android.Route
import app.camotrack.android.i18n.L
import app.camotrack.android.services.AppIconChoice
import app.camotrack.android.services.AppIcons
import app.camotrack.android.services.Premium
import app.camotrack.android.ui.Ink
import app.camotrack.android.ui.LocalPalette

/**
 * Customise > App icon (iOS AppIconPicker): every icon, the earned ones to
 * pick from, the rest showing what unlocks them. Locked ones keep their
 * colours, dimmed: the goal is the point.
 */
@Composable
fun AppIconsScreen() {
    val palette = LocalPalette.current
    val t = AppState.tracker
    AppState.revision
    val context = LocalContext.current
    var current by remember { mutableStateOf(AppIcons.current(AppState.store)) }
    Column(Modifier.fillMaxSize().background(palette.background).statusBarsPadding()) {
        SettingsTopBar(L("mw4.ui.app_icon.title"))
        LazyVerticalGrid(GridCells.Adaptive(96.dp), contentPadding = PaddingValues(16.dp),
                         horizontalArrangement = Arrangement.spacedBy(14.dp), verticalArrangement = Arrangement.spacedBy(18.dp)) {
            item(span = { GridItemSpan(maxLineSpan) }) {
                Text(L("mw4.ui.app_icon.footer"), color = Ink.muted, fontSize = 13.sp)
            }
            items(AppIconChoice.entries) { choice ->
                val earned = choice.isEarned(t)
                val needsPremium = earned && choice.needsPremium && !Premium.isPremium
                val selected = choice == current
                Column(
                    Modifier.clickable(enabled = earned) {
                        if (needsPremium) { AppState.push(Route.Premium); return@clickable }
                        if (choice != current) { AppIcons.pick(context, AppState.store, choice); current = choice }
                    },
                    horizontalAlignment = Alignment.CenterHorizontally,
                ) {
                    Box {
                        Image(painterResource(choice.preview), choice.title(t),
                              Modifier.fillMaxWidth().aspectRatio(1f).clip(RoundedCornerShape(18.dp))
                                  .alpha(if (earned) 1f else 0.5f)
                                  .border(BorderStroke(if (selected) 3.dp else 1.dp, if (selected) palette.accent else Color.White.copy(alpha = 0.08f)),
                                          RoundedCornerShape(18.dp)))
                        if (!earned || needsPremium) {
                            Box(Modifier.align(Alignment.TopEnd).padding(5.dp).size(22.dp)
                                .background(if (earned) palette.accent else Color.Black.copy(alpha = 0.6f), CircleShape),
                                contentAlignment = Alignment.Center) {
                                Icon(if (earned) Icons.Filled.AutoAwesome else Icons.Filled.Lock, null, tint = Color.White, modifier = Modifier.size(12.dp))
                            }
                        }
                    }
                    Spacer(Modifier.height(6.dp))
                    Text(choice.title(t), color = if (earned) Ink.text else Ink.muted, fontSize = 12.sp, fontWeight = FontWeight.SemiBold,
                         maxLines = 1, overflow = TextOverflow.Ellipsis)
                    Text(if (earned) (if (needsPremium) L("mw4.ui.app_icon.premium") else " ") else choice.requirement(t),
                         color = Ink.muted, fontSize = 11.sp, textAlign = TextAlign.Center, maxLines = 2, minLines = 2)
                }
            }
        }
    }
}
