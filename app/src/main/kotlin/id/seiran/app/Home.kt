@file:OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)

package id.seiran.app

import android.os.Build
import androidx.compose.foundation.Image
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

// SHA-256 of pub.raw, the Ed25519 key that signs the release zips
const val SIGNER_FP = "4db3a8eed2aa932528556ef95e186542f96d85c64e95289e1ee5dc0c633f54db"

@Composable
fun HomeScreen(stats: Stats?, rootOk: Boolean, onGrantRoot: () -> Unit) {
    val ctx = LocalContext.current
    val version = remember {
        runCatching { ctx.packageManager.getPackageInfo(ctx.packageName, 0).versionName }
            .getOrNull() ?: "?"
    }
    val kernel = remember { System.getProperty("os.version") ?: "unknown" }
    var infoOpen by rememberSaveable { mutableStateOf(false) }
    val dash = "\u2014"

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
            "Seiran",
            style = MaterialTheme.typography.displaySmall,
            modifier = Modifier.padding(top = 16.dp, start = 4.dp),
        )
        Banner(kernel, version)

        if (stats != null && stats.zramAlgo == null && !rootOk) {
            RootCard(onGrantRoot)
        }

        val s = stats
        Row(Modifier.height(IntrinsicSize.Min), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            Tile(
                "zram",
                s?.zramAlgo ?: dash,
                listOfNotNull(
                    s?.zramRecomp?.let { "recomp $it" },
                    s?.zramMb?.let { "$it MB" },
                ).joinToString(" \u2022 ").ifEmpty { null },
                Modifier.weight(1f).fillMaxHeight(),
            )
            Tile(
                "I/O scheduler",
                s?.io ?: dash,
                s?.cpuidle?.let { "cpuidle $it" },
                Modifier.weight(1f).fillMaxHeight(),
            )
        }
        Row(Modifier.height(IntrinsicSize.Min), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            Tile(
                "cpufreq",
                s?.gov0 ?: dash,
                s?.gov4?.let { "policy4 $it" },
                Modifier.weight(1f).fillMaxHeight(),
            )
            Tile(
                "Battery",
                s?.health ?: dash,
                s?.battery,
                Modifier.weight(1f).fillMaxHeight(),
            )
        }
        Row(Modifier.height(IntrinsicSize.Min), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            Tile(
                "UFS health",
                if (s?.ufsA != null && s.ufsB != null) "A ${s.ufsA} / B ${s.ufsB}" else dash,
                null,
                Modifier.weight(1f).fillMaxHeight(),
            )
            Tile(
                "mem_sleep",
                s?.memSleep ?: dash,
                null,
                Modifier.weight(1f).fillMaxHeight(),
            )
        }

        DeviceCard(infoOpen, { infoOpen = !infoOpen }, kernel, version)
        SignerCard()
    }
}

@Composable
private fun Banner(kernel: String, version: String) {
    Box(
        Modifier
            .fillMaxWidth()
            .height(180.dp)
            .clip(RoundedCornerShape(28.dp)),
    ) {
        Image(
            painter = painterResource(R.drawable.banner),
            contentDescription = null,
            contentScale = ContentScale.Crop,
            modifier = Modifier.fillMaxSize(),
        )
        Column(
            Modifier
                .align(Alignment.BottomStart)
                .padding(12.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            Chip("Kernel $kernel")
            Chip("App v$version")
        }
    }
}

@Composable
private fun Chip(text: String) {
    Surface(shape = RoundedCornerShape(50), color = Color.Black.copy(alpha = 0.6f)) {
        Text(
            text,
            color = Color.White,
            style = MaterialTheme.typography.labelLarge,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.padding(horizontal = 12.dp, vertical = 6.dp),
        )
    }
}

@Composable
private fun RootCard(onGrant: () -> Unit) {
    Card(
        shape = RoundedCornerShape(24.dp),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.errorContainer,
            contentColor = MaterialTheme.colorScheme.onErrorContainer,
        ),
    ) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text("Root access needed", style = MaterialTheme.typography.titleMedium)
            Text(
                "Some values cannot be read without root. Allow Seiran in KernelSU-Next " +
                    "(Superuser), then tap the button.",
                style = MaterialTheme.typography.bodyMedium,
            )
            Button(onClick = onGrant) { Text("Grant root") }
        }
    }
}

@Composable
private fun Tile(title: String, value: String, sub: String?, modifier: Modifier) {
    Card(
        modifier = modifier,
        shape = RoundedCornerShape(24.dp),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceContainer,
        ),
    ) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(
                title,
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Text(value, style = MaterialTheme.typography.titleMedium)
            if (sub != null) {
                Text(
                    sub,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}

@Composable
private fun DeviceCard(open: Boolean, onToggle: () -> Unit, kernel: String, version: String) {
    val chipset = if (Build.VERSION.SDK_INT >= 31) Build.SOC_MODEL else Build.HARDWARE
    Card(
        modifier = Modifier
            .clip(RoundedCornerShape(24.dp))
            .clickable(onClick = onToggle),
        shape = RoundedCornerShape(24.dp),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceContainer,
        ),
    ) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Text(
                    "Device info",
                    style = MaterialTheme.typography.titleMedium,
                    modifier = Modifier.weight(1f),
                )
                Text(if (open) "\u25B4" else "\u25BE", style = MaterialTheme.typography.titleMedium)
            }
            if (open) {
                InfoRow("Device", "${Build.MANUFACTURER} ${Build.MODEL} (${Build.DEVICE})")
                InfoRow("Chipset", chipset)
                InfoRow("Kernel", kernel)
                InfoRow("Android", "${Build.VERSION.RELEASE} (API ${Build.VERSION.SDK_INT})")
                InfoRow("App", "v$version")
            }
        }
    }
}

@Composable
private fun InfoRow(label: String, value: String) {
    Column {
        Text(
            label,
            style = MaterialTheme.typography.labelMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Text(value, style = MaterialTheme.typography.bodyMedium)
    }
}

@Composable
private fun SignerCard() {
    Card(
        shape = RoundedCornerShape(24.dp),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceContainer,
        ),
    ) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Text("Release signer (Ed25519)", style = MaterialTheme.typography.titleMedium)
            Text(
                SIGNER_FP,
                fontFamily = FontFamily.Monospace,
                fontSize = 11.sp,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}
