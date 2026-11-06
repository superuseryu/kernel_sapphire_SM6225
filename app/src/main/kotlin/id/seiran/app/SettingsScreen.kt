@file:OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)

package id.seiran.app

import android.os.Build
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.FilterChip
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp

@Composable
fun SettingsScreen(theme: ThemeState) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .statusBarsPadding()
            .padding(horizontal = 16.dp)
            .padding(bottom = 104.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Text(
            "Settings",
            style = MaterialTheme.typography.displaySmall,
            modifier = Modifier.padding(top = 16.dp, start = 4.dp),
        )
        Card(
            modifier = Modifier.fillMaxWidth(),
            shape = RoundedCornerShape(24.dp),
            colors = CardDefaults.cardColors(
                containerColor = MaterialTheme.colorScheme.surfaceContainer,
            ),
        ) {
            Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Text("Theme", style = MaterialTheme.typography.titleMedium)
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    listOf("System", "Light", "Dark").forEachIndexed { i, label ->
                        FilterChip(
                            selected = theme.mode == i,
                            onClick = { theme.setMode(i) },
                            label = { Text(label) },
                        )
                    }
                }
            }
        }
        SwitchRow(
            "Dynamic color",
            "Use wallpaper colors (Android 12+)",
            theme.dynamic,
            Build.VERSION.SDK_INT >= 31,
        ) { theme.setDynamic(it) }
        SwitchRow(
            "AMOLED black",
            "Pure black background in dark mode",
            theme.amoled,
            true,
        ) { theme.setAmoled(it) }
        KeyColorCard(theme)
        ContributorsSection()
        CreditsCard()
    }
}

@Composable
private fun SwitchRow(
    title: String,
    sub: String,
    checked: Boolean,
    enabled: Boolean,
    onChange: (Boolean) -> Unit,
) {
    Card(
        shape = RoundedCornerShape(24.dp),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceContainer,
        ),
    ) {
        Row(
            Modifier
                .fillMaxWidth()
                .padding(16.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column(Modifier.weight(1f)) {
                Text(title, style = MaterialTheme.typography.titleMedium)
                Text(
                    sub,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            Switch(checked = checked, onCheckedChange = onChange, enabled = enabled)
        }
    }
}

@Composable
private fun KeyColorCard(theme: ThemeState) {
    val active = !(theme.dynamic && Build.VERSION.SDK_INT >= 31)
    val colors = listOf(0xFF5FA8C2, 0xFF6750A4, 0xFF4C8C4A, 0xFFE07B39, 0xFFD6638F, 0xFF3B6FD4)
        .map { it.toInt() }
    Card(
        modifier = Modifier
            .fillMaxWidth()
            .alpha(if (active) 1f else 0.38f),
        shape = RoundedCornerShape(24.dp),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceContainer,
        ),
    ) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Column {
                Text("Key color", style = MaterialTheme.typography.titleMedium)
                Text(
                    "Used when Dynamic color is off",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                colors.forEach { c ->
                    val picked = theme.seed == c
                    Box(
                        Modifier
                            .size(40.dp)
                            .clip(CircleShape)
                            .background(Color(c))
                            .then(
                                if (picked) {
                                    Modifier.border(3.dp, MaterialTheme.colorScheme.onSurface, CircleShape)
                                } else {
                                    Modifier
                                },
                            )
                            .clickable(enabled = active) { theme.setSeed(c) },
                    )
                }
            }
        }
    }
}

@Composable
private fun CreditsCard() {
    Card(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(24.dp),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceContainer,
        ),
    ) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text("Credits", style = MaterialTheme.typography.titleMedium)
            listOf(
                "Launcher icon: Paw by Mihimihi, from Flaticon (flaticon.com)",
                "Blur: Haze by Chris Banes (Apache-2.0)",
                "Theme colors: MaterialKolor by Jordon de Hoog (MIT)",
            ).forEach {
                Text(
                    it,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}
