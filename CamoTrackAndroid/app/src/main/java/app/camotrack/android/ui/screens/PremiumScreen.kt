package app.camotrack.android.ui.screens

import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.camotrack.android.AppState
import app.camotrack.android.i18n.L
import app.camotrack.android.services.Premium
import app.camotrack.android.ui.Ink
import app.camotrack.android.ui.LocalPalette
import app.camotrack.android.ui.ModeColors
import app.camotrack.android.ui.displayStyle
import app.camotrack.android.ui.isAccessibilityFontSize
import app.camotrack.android.ui.readableInset
import kotlinx.coroutines.launch

fun Context.findActivity(): Activity? = when (this) {
    is Activity -> this
    is ContextWrapper -> baseContext.findActivity()
    else -> null
}

/**
 * Premium (iOS PremiumView): what it gets you, yearly and lifetime, restore
 * and the links Play asks for beside a subscription. A Premium player gets
 * their plan, thanks and Manage subscription instead.
 */
@Composable
fun PremiumScreen() {
    val palette = LocalPalette.current
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var notice by remember { mutableStateOf<Premium.Notice?>(null) }
    var restoring by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) { Premium.loadProducts() }
    val red = ModeColors.dmz

    Column(Modifier.fillMaxSize().background(palette.background).statusBarsPadding()) {
        Row(Modifier.fillMaxWidth().padding(4.dp), verticalAlignment = Alignment.CenterVertically) {
            IconButton(onClick = { AppState.pop() }) { Icon(Icons.AutoMirrored.Filled.ArrowBack, L("mw4.ui.done"), tint = Ink.text) }
        }
        Column(Modifier.verticalScroll(rememberScrollState()).padding(horizontal = readableInset()).padding(horizontal = 20.dp, vertical = 8.dp), verticalArrangement = Arrangement.spacedBy(20.dp)) {
            if (Premium.isPremium) {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text(L("ct.premium.you_have"), style = displayStyle(26.sp), color = Ink.text)
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Icon(Icons.Filled.Verified, null, tint = ModeColors.dmzText, modifier = Modifier.size(20.dp))
                        Spacer(Modifier.width(6.dp))
                        Text(Premium.plan?.line ?: L("ct.premium.plan.unknown"), color = ModeColors.dmzText, fontWeight = FontWeight.SemiBold)
                    }
                    Text(L("ct.premium.thanks"), color = Ink.muted, fontSize = 14.sp)
                }
            } else {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text(L("mw4.ui.premium.title"), style = displayStyle(26.sp), color = Ink.text)
                    Text(L("mw4.ui.premium.subtitle"), color = Ink.muted, fontSize = 14.sp)
                }
            }
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Perk(Icons.Filled.Block, "mw4.ui.premium.perk_ads", red)
                Perk(Icons.Filled.AppShortcut, "mw4.ui.premium.perk_icons", red)
                Perk(Icons.Filled.Tune, "mw4.ui.premium.perk_customise", red)
                Perk(Icons.Filled.PushPin, "mw4.ui.premium.perk_pins", red)
                Perk(Icons.Filled.Favorite, "mw4.ui.premium.perk_support", red)
            }

            if (Premium.isPremium) {
                if (Premium.isSubscriber) {
                    OutlinedButton(onClick = {
                        context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(
                            "https://play.google.com/store/account/subscriptions?sku=${Premium.YEARLY}&package=${context.packageName}")))
                    }, Modifier.fillMaxWidth()) { Text(L("ct.premium.manage"), color = ModeColors.dmzText) }
                }
            } else if (Premium.offersFake) {
                Option(yearly = true, price = "£1.99" + L("mw4.ui.premium.per_year") + " (test)", red) { Premium.fakeBuy(); AppState.pop() }
                Option(yearly = false, price = "£7.99 (test)", red) { Premium.fakeBuy(); AppState.pop() }
                Text("Debug build: test purchases, nothing is charged.", color = Ink.muted, fontSize = 11.sp,
                     modifier = Modifier.fillMaxWidth(), textAlign = TextAlign.Center)
            } else if (Premium.products.isEmpty() && Premium.loadFailed) {
                Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally) {
                    Text(L("mw4.ui.premium.load_failed"), color = Ink.muted, fontSize = 14.sp, textAlign = TextAlign.Center)
                    TextButton(onClick = { scope.launch { Premium.loadProducts() } }) { Text(L("mw4.ui.premium.retry"), color = ModeColors.dmzText) }
                }
            } else if (Premium.products.isEmpty()) {
                Box(Modifier.fillMaxWidth().padding(20.dp), contentAlignment = Alignment.Center) { CircularProgressIndicator(color = red) }
            } else {
                Premium.products.sortedBy { it.productId != Premium.YEARLY }.forEach { product ->
                    val yearly = product.productId == Premium.YEARLY
                    val price = Premium.price(product.productId).orEmpty() + if (yearly) L("mw4.ui.premium.per_year") else ""
                    Option(yearly, price, red, enabled = !Premium.purchasing) {
                        val activity = context.findActivity() ?: return@Option
                        scope.launch { notice = Premium.buy(activity, product) }
                    }
                }
            }

            TextButton(onClick = {
                restoring = true
                scope.launch { notice = Premium.restore(); restoring = false }
            }, enabled = !restoring, modifier = Modifier.fillMaxWidth()) {
                if (restoring) CircularProgressIndicator(Modifier.size(16.dp), strokeWidth = 2.dp)
                Text(L("mw4.ui.premium.restore"), color = ModeColors.dmzText, fontWeight = FontWeight.SemiBold)
            }
            if (Premium.isPremium && Premium.offersFake) {
                TextButton(onClick = { Premium.resetFake() }, modifier = Modifier.fillMaxWidth()) {
                    Text("Reset test purchase (debug)", color = ModeColors.dmzText)
                }
            }
            if (!Premium.isPremium) {
                Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text(L("ct.android.premium.legal"), color = Ink.muted, fontSize = 11.sp, textAlign = TextAlign.Center)
                    Text(L("mw4.ui.premium.privacy"), color = Ink.muted, fontSize = 12.sp, fontWeight = FontWeight.SemiBold,
                         modifier = Modifier.clickable {
                             context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse("https://camo-track.app/privacy-policy")))
                         })
                }
            }
            Spacer(Modifier.height(24.dp))
        }
    }

    notice?.let { n ->
        AlertDialog(
            onDismissRequest = { notice = null },
            confirmButton = {
                TextButton(onClick = {
                    notice = null
                    if (n == Premium.Notice.Purchased || n == Premium.Notice.Restored) AppState.pop()
                }) { Text(L("mw4.ui.done")) }
            },
            title = { Text(n.title) }, text = { Text(n.message) },
        )
    }
}

@Composable
private fun Perk(icon: ImageVector, key: String, color: Color) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.size(30.dp).background(color, CircleShape), contentAlignment = Alignment.Center) {
            Icon(icon, null, tint = Color.White, modifier = Modifier.size(16.dp))
        }
        Spacer(Modifier.width(12.dp))
        Text(L(key), color = Ink.text, fontSize = 14.sp)
    }
}

@Composable
private fun Option(yearly: Boolean, price: String, red: Color, enabled: Boolean = true, onClick: () -> Unit) {
    val palette = LocalPalette.current
    val ink = if (yearly) Color.White else Ink.text
    val modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp).background(if (yearly) red else palette.surface, RoundedCornerShape(12.dp))
        .clickable(enabled = enabled, onClick = onClick).padding(14.dp)
    val title: @Composable () -> Unit = {
        Text(L(if (yearly) "mw4.ui.premium.yearly" else "mw4.ui.premium.lifetime"), color = ink, fontWeight = FontWeight.SemiBold)
        Text(L(if (yearly) "mw4.ui.premium.yearly_hint" else "mw4.ui.premium.lifetime_hint"), color = ink.copy(alpha = 0.8f), fontSize = 12.sp)
    }
    val priceText: @Composable () -> Unit = {
        Text(price, color = ink, fontWeight = FontWeight.Bold, fontFamily = FontFamily.Monospace, fontSize = 16.sp)
    }
    // The price under the plan at the largest text sizes: beside it, it
    // squeezed "Yearly" to a letter a line
    if (isAccessibilityFontSize()) {
        Column(modifier, verticalArrangement = Arrangement.spacedBy(6.dp)) { title(); priceText() }
    } else {
        Row(modifier, verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) { title() }
            Spacer(Modifier.width(10.dp))
            priceText()
        }
    }
}
