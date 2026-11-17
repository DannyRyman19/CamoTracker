package app.camotrack.android.ui.screens

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import app.camotrack.android.ui.Ink

@Composable
internal fun Placeholder(text: String) =
    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { Text(text, color = Ink.muted) }
