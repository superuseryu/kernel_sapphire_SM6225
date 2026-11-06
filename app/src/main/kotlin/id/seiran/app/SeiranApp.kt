package id.seiran.app

import android.content.Context
import androidx.activity.ComponentActivity
import androidx.activity.SystemBarStyle
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import kotlin.concurrent.thread

@Composable
fun SeiranApp() {
    val ctx = LocalContext.current
    val sp = remember { ctx.getSharedPreferences("settings", Context.MODE_PRIVATE) }
    val theme = remember { ThemeState(sp) }
    val dark = isDark(theme)

    val activity = ctx as ComponentActivity
    DisposableEffect(dark) {
        activity.enableEdgeToEdge(
            statusBarStyle = SystemBarStyle.auto(
                android.graphics.Color.TRANSPARENT,
                android.graphics.Color.TRANSPARENT,
            ) { dark },
            navigationBarStyle = SystemBarStyle.auto(
                android.graphics.Color.TRANSPARENT,
                android.graphics.Color.TRANSPARENT,
            ) { dark },
        )
        onDispose { }
    }

    var tab by rememberSaveable { mutableIntStateOf(0) }
    var stats by remember { mutableStateOf<Stats?>(null) }
    var rootOk by remember { mutableStateOf(false) }
    val wantRoot = remember { sp.getBoolean("use_root", false) }

    // Reload whenever Home is shown. Root is only requested if it was granted before.
    LaunchedEffect(tab) {
        if (tab == 0) {
            val ask = rootOk || wantRoot
            thread {
                val r = ask && Sys.grantRoot()
                rootOk = r
                stats = Sys.load(r)
            }
        }
    }

    val onGrantRoot: () -> Unit = {
        thread {
            val r = Sys.grantRoot()
            rootOk = r
            if (r) sp.edit().putBoolean("use_root", true).apply()
            stats = Sys.load(r)
        }
    }

    SeiranTheme(theme, dark) {
        Surface(Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) {
            Box(Modifier.fillMaxSize()) {
                if (tab == 0) {
                    HomeScreen(stats, rootOk, onGrantRoot)
                } else {
                    SettingsScreen(theme)
                }
                NavPill(tab, { tab = it }, Modifier.align(Alignment.BottomCenter))
            }
        }
    }
}

@Composable
private fun NavPill(tab: Int, onSelect: (Int) -> Unit, modifier: Modifier) {
    Surface(
        modifier = modifier
            .navigationBarsPadding()
            .padding(bottom = 12.dp),
        shape = RoundedCornerShape(32.dp),
        color = MaterialTheme.colorScheme.surfaceContainer,
        tonalElevation = 6.dp,
        shadowElevation = 6.dp,
    ) {
        Row(Modifier.padding(8.dp), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            NavItem(Icons.Filled.Home, "Home", tab == 0) { onSelect(0) }
            NavItem(Icons.Filled.Settings, "Settings", tab == 1) { onSelect(1) }
        }
    }
}

@Composable
private fun NavItem(icon: ImageVector, label: String, selected: Boolean, onClick: () -> Unit) {
    val bg = if (selected) MaterialTheme.colorScheme.primaryContainer else Color.Transparent
    Row(
        Modifier
            .clip(RoundedCornerShape(24.dp))
            .background(bg)
            .clickable(onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(icon, contentDescription = label)
        if (selected) {
            Spacer(Modifier.width(8.dp))
            Text(label)
        }
    }
}
