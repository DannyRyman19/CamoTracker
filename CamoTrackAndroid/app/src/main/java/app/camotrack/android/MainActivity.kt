package app.camotrack.android

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.BackHandler
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil.compose.AsyncImage

// The iPhone app's colours (Theme.swift): near-black ground, MW4's pink accent
private val Background = Color(0xFF0C0F0E)
private val Surface = Color(0xFF171C1A)
private val Ink = Color(0xFFEDEFEA)
private val InkMuted = Color(0xFF8B958D)
private val Accent = Color(0xFFE0457F)

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            MaterialTheme(colorScheme = darkColorScheme(background = Background, surface = Surface, primary = Accent)) {
                Surface(Modifier.fillMaxSize(), color = Background) { App() }
            }
        }
    }
}

@Composable
private fun App() {
    var tracker by remember { mutableStateOf<Tracker?>(null) }
    var error by remember { mutableStateOf<String?>(null) }
    var open by remember { mutableStateOf<Weapon?>(null) }
    LaunchedEffect(Unit) {
        runCatching { CamoData.mode("multiplayer.json") }
            .onSuccess { tracker = it }
            .onFailure { error = it.message ?: it.toString() }
    }
    BackHandler(open != null) { open = null }
    val t = tracker
    when {
        error != null -> Message("Couldn't load the camos: $error")
        t == null -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { CircularProgressIndicator(color = Accent) }
        open != null -> WeaponScreen(open!!, t.camos(open!!.weaponId))
        else -> WeaponList(t) { open = it }
    }
}

@Composable
private fun Message(text: String) =
    Box(Modifier.fillMaxSize().padding(24.dp), contentAlignment = Alignment.Center) { Text(text, color = InkMuted) }

@Composable
private fun WeaponList(tracker: Tracker, onOpen: (Weapon) -> Unit) {
    LazyColumn(contentPadding = WindowInsets.systemBars.asPaddingValues(), modifier = Modifier.fillMaxSize()) {
        item {
            Text("MW4 Multiplayer", color = Accent, fontSize = 28.sp, fontWeight = FontWeight.Black,
                 modifier = Modifier.padding(start = 16.dp, top = 16.dp, bottom = 8.dp))
        }
        tracker.weapons.categories.forEach { category ->
            item(key = "c${category.categoryId}") {
                Text(category.name.resolved().uppercase(), color = InkMuted, fontSize = 12.sp, fontWeight = FontWeight.Bold,
                     modifier = Modifier.padding(start = 16.dp, top = 18.dp, bottom = 6.dp))
            }
            items(category.weapons, key = { "w${it.weaponId}" }) { weapon ->
                WeaponCard(weapon, tracker.camos(weapon.weaponId).size) { onOpen(weapon) }
            }
        }
    }
}

@Composable
private fun WeaponCard(weapon: Weapon, camoCount: Int, onClick: () -> Unit) {
    Row(
        Modifier.padding(horizontal = 12.dp, vertical = 5.dp).fillMaxWidth()
            .clip(RoundedCornerShape(10.dp)).background(Surface).clickable(onClick = onClick).padding(12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        AsyncImage(weapon.imageURL, contentDescription = null, contentScale = ContentScale.Fit,
                   modifier = Modifier.size(width = 72.dp, height = 44.dp))
        Spacer(Modifier.width(12.dp))
        Column(Modifier.weight(1f)) {
            Text(weapon.name.resolved(), color = Ink, fontSize = 16.sp, fontWeight = FontWeight.Bold)
            Text("$camoCount camos · max level ${weapon.maxLevel}", color = InkMuted, fontSize = 12.sp)
        }
    }
}

@Composable
private fun WeaponScreen(weapon: Weapon, camos: List<Camo>) {
    Column(Modifier.fillMaxSize().padding(WindowInsets.systemBars.asPaddingValues())) {
        AsyncImage(weapon.imageURL, contentDescription = null, contentScale = ContentScale.Fit,
                   modifier = Modifier.fillMaxWidth().height(140.dp).padding(16.dp))
        Text(weapon.name.resolved(), color = Ink, fontSize = 26.sp, fontWeight = FontWeight.Black, modifier = Modifier.padding(horizontal = 16.dp))
        LazyVerticalGrid(GridCells.Adaptive(96.dp), contentPadding = PaddingValues(12.dp)) {
            items(camos, key = { it.itemId }) { camo ->
                Column(Modifier.padding(6.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                    AsyncImage(camo.imageURL, contentDescription = null, contentScale = ContentScale.Crop,
                               modifier = Modifier.size(84.dp).clip(RoundedCornerShape(14.dp)).background(Surface))
                    Text(camo.name.resolved(), color = Ink, fontSize = 12.sp, maxLines = 1, modifier = Modifier.padding(top = 4.dp))
                }
            }
        }
    }
}
