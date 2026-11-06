package id.seiran.app

import android.os.Build
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.FilterChip
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.unit.dp
import com.topjohnwu.superuser.Shell

// libsu caches the main shell. If it was created without root, drop it first
// so a retry (after the user allows Seiran in the root manager) can succeed.
fun recheckRoot(): Boolean {
    try {
        val c = Shell.getCachedShell()
        if (c != null && !c.isRoot) c.close()
    } catch (_: Throwable) {
    }
    return Sys.grantRoot()
}

@Composable
private fun RootStep(
    rootOk: Boolean,
    checking: Boolean,
    buttonLabel: String,
    onGrant: () -> Unit,
) {
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Text("Root access", style = MaterialTheme.typography.headlineMedium)
        Text(
            "Seiran reads and controls kernel settings, so it needs root. " +
                "Allow Seiran in your root manager (KernelSU-Next, Superuser). " +
                "If you denied it before, enable it in the Superuser list, then come back.",
            style = MaterialTheme.typography.bodyLarge,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            if (checking) {
                CircularProgressIndicator(Modifier.size(20.dp), strokeWidth = 2.dp)
                Text("Checking root access", style = MaterialTheme.typography.titleMedium)
            } else if (rootOk) {
                Text(
                    "Root access granted",
                    style = MaterialTheme.typography.titleMedium,
                    color = MaterialTheme.colorScheme.primary,
                )
            } else {
                Text(
                    "Root access not granted",
                    style = MaterialTheme.typography.titleMedium,
                    color = MaterialTheme.colorScheme.error,
                )
            }
        }
        if (!rootOk) {
            Button(onClick = onGrant, enabled = !checking) { Text(buttonLabel) }
        }
    }
}

@Composable
fun RootGate(checking: Boolean, onGrant: () -> Unit) {
    Column(
        Modifier
            .fillMaxSize()
            .statusBarsPadding()
            .navigationBarsPadding()
            .padding(24.dp),
        verticalArrangement = Arrangement.Center,
    ) {
        RootStep(false, checking, "Check again", onGrant)
    }
}

@Composable
fun Onboarding(
    theme: ThemeState,
    rootOk: Boolean,
    checking: Boolean,
    onGrant: () -> Unit,
    onFinish: () -> Unit,
) {
    var step by rememberSaveable { mutableIntStateOf(0) }
    Column(
        Modifier
            .fillMaxSize()
            .statusBarsPadding()
            .navigationBarsPadding()
            .padding(24.dp),
    ) {
        Column(
            Modifier
                .weight(1f)
                .verticalScroll(rememberScrollState()),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            when (step) {
                0 -> {
                    Text(
                        "WELCOME TO",
                        style = MaterialTheme.typography.labelLarge,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Text("Seiran", style = MaterialTheme.typography.displayMedium)
                    Image(
                        painterResource(R.drawable.banner),
                        null,
                        Modifier
                            .fillMaxWidth()
                            .height(220.dp)
                            .clip(RoundedCornerShape(28.dp)),
                        contentScale = ContentScale.Crop,
                    )
                    Text(
                        "Kernel status and controls for sapphire, in one place.",
                        style = MaterialTheme.typography.bodyLarge,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                1 -> RootStep(rootOk, checking, "Grant root", onGrant)
                else -> {
                    Text("Theme", style = MaterialTheme.typography.headlineMedium)
                    Text(
                        "Pick how Seiran looks. You can change this later in Settings.",
                        style = MaterialTheme.typography.bodyLarge,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        listOf("System", "Light", "Dark").forEachIndexed { i, label ->
                            FilterChip(
                                selected = theme.mode == i,
                                onClick = { theme.setMode(i) },
                                label = { Text(label) },
                            )
                        }
                    }
                    Row(
                        Modifier.fillMaxWidth(),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Column(Modifier.weight(1f)) {
                            Text("Dynamic color", style = MaterialTheme.typography.titleMedium)
                            Text(
                                "Use wallpaper colors (Android 12+)",
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                        Switch(
                            checked = theme.dynamic,
                            onCheckedChange = { theme.setDynamic(it) },
                            enabled = Build.VERSION.SDK_INT >= 31,
                        )
                    }
                }
            }
        }
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            if (step > 0) {
                OutlinedButton(onClick = { step -= 1 }) { Text("Back") }
            }
            Spacer(Modifier.weight(1f))
            val last = step == 2
            Button(
                onClick = { if (last) onFinish() else step += 1 },
                enabled = step != 1 || rootOk,
            ) { Text(if (last) "Let's go" else "Next") }
        }
    }
}
