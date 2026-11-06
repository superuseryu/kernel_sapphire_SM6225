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
import com.materialkolor.rememberDynamicColorScheme

class ThemeState(private val sp: SharedPreferences) {
    // 0 = system, 1 = light, 2 = dark
    var mode by mutableIntStateOf(sp.getInt("theme_mode", 0))
        private set
    var dynamic by mutableStateOf(sp.getBoolean("dynamic", true))
        private set
    var amoled by mutableStateOf(sp.getBoolean("amoled", false))
        private set
    var seed by mutableIntStateOf(sp.getInt("seed", 0xFF5FA8C2.toInt()))
        private set

    @JvmName("applyMode")
    fun setMode(v: Int) {
        mode = v
        sp.edit().putInt("theme_mode", v).apply()
    }

    @JvmName("applyDynamic")
    fun setDynamic(v: Boolean) {
        dynamic = v
        sp.edit().putBoolean("dynamic", v).apply()
    }

    @JvmName("applyAmoled")
    fun setAmoled(v: Boolean) {
        amoled = v
        sp.edit().putBoolean("amoled", v).apply()
    }

    @JvmName("applySeed")
    fun setSeed(v: Int) {
        seed = v
        sp.edit().putInt("seed", v).apply()
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
    } else {
        rememberDynamicColorScheme(seedColor = Color(t.seed), isDark = dark)
    }
    val scheme = if (dark && t.amoled) {
        base.copy(background = Color.Black, surface = Color.Black)
    } else {
        base
    }
    MaterialTheme(colorScheme = scheme, content = content)
}
