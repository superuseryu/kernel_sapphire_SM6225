package id.seiran.app

import android.content.SharedPreferences
import android.os.Build
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.dynamicDarkColorScheme
import androidx.compose.material3.dynamicLightColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext

class ThemeState(private val sp: SharedPreferences) {
    // 0 = system, 1 = light, 2 = dark
    var mode by mutableIntStateOf(sp.getInt("theme_mode", 0))
        private set
    var dynamic by mutableStateOf(sp.getBoolean("dynamic", true))
        private set
    var amoled by mutableStateOf(sp.getBoolean("amoled", false))
        private set

    fun setMode(v: Int) {
        mode = v
        sp.edit().putInt("theme_mode", v).apply()
    }

    fun setDynamic(v: Boolean) {
        dynamic = v
        sp.edit().putBoolean("dynamic", v).apply()
    }

    fun setAmoled(v: Boolean) {
        amoled = v
        sp.edit().putBoolean("amoled", v).apply()
    }
}

@Composable
fun isDark(t: ThemeState): Boolean = when (t.mode) {
    1 -> false
    2 -> true
    else -> isSystemInDarkTheme()
}

@Composable
fun SeiranTheme(t: ThemeState, dark: Boolean, content: @Composable () -> Unit) {
    val ctx = LocalContext.current
    val base = if (t.dynamic && Build.VERSION.SDK_INT >= 31) {
        if (dark) dynamicDarkColorScheme(ctx) else dynamicLightColorScheme(ctx)
    } else if (dark) {
        darkColorScheme()
    } else {
        lightColorScheme()
    }
    val scheme = if (dark && t.amoled) {
        base.copy(background = Color.Black, surface = Color.Black)
    } else {
        base
    }
    MaterialTheme(colorScheme = scheme, content = content)
}
