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
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.LifecycleOwner
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
    var checking by remember { mutableStateOf(true) }
    var onboarded by remember { mutableStateOf(sp.getBoolean("onboarded", false)) }

    // Root is required. The check runs at launch, on demand, and again
    // whenever the app returns to the foreground while root is missing.
    val runCheck: () -> Unit = {
        checking = true
        thread {
            val r = recheckRoot()
            rootOk = r
            checking = false
        }
    }

    LaunchedEffect(Unit) { runCheck() }

    DisposableEffect(activity) {
        val obs = object : LifecycleEventObserver {
            override fun onStateChanged(source: LifecycleOwner, event: Lifecycle.Event) {
                if (event == Lifecycle.Event.ON_RESUME && !rootOk && !checking) runCheck()
            }
        }
        activity.lifecycle.addObserver(obs)
        onDispose { activity.lifecycle.removeObserver(obs) }
    }

    LaunchedEffect(tab, rootOk) {
        if (tab == 0 && rootOk) thread { stats = Sys.load(true) }
    }

    SeiranTheme(theme, dark) {
        Surface(Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) {
            Box(Modifier.fillMaxSize()) {
                if (!onboarded) {
                    Onboarding(
                        theme = theme,
                        rootOk = rootOk,
                        checking = checking,
                        onGrant = runCheck,
                        onFinish = {
                            sp.edit().putBoolean("onboarded", true).apply()
                            onboarded = true
                        },
                    )
                } else if (!rootOk) {
                    RootGate(checking = checking, onGrant = runCheck)
                } else {
                    if (tab == 0) {
                        HomeScreen(stats, true, runCheck)
                    } else {
                        SettingsScreen(theme)
                    }
                    NavPill(tab, { tab = it }, Modifier.align(Alignment.BottomCenter))
                }
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
    val fg = if (selected) MaterialTheme.colorScheme.onPrimaryContainer else MaterialTheme.colorScheme.onSurface
    Row(
        Modifier
            .clip(RoundedCornerShape(24.dp))
            .background(bg)
            .clickable(onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(icon, contentDescription = label, tint = fg)
        if (selected) {
            Spacer(Modifier.width(8.dp))
            Text(label, color = fg)
        }
    }
}
