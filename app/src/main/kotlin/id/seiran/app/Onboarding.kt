package id.seiran.app

import android.os.Build
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
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
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
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
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.topjohnwu.superuser.Shell
import kotlinx.coroutines.delay

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

// Fades and lifts its content in after delayMs, so a step builds up piece by piece.
@Composable
private fun Reveal(delayMs: Int, content: @Composable () -> Unit) {
    var shown by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) {
        delay(delayMs.toLong())
        shown = true
    }
    val a by animateFloatAsState(if (shown) 1f else 0f, tween(450), label = "reveal")
    Box(
        Modifier.graphicsLayer {
            alpha = a
            translationY = (1f - a) * 28.dp.toPx()
        },
    ) { content() }
}

@Composable
private fun StepBar(step: Int, total: Int) {
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        for (i in 0 until total) {
            val c by animateColorAsState(
                if (i <= step) MaterialTheme.colorScheme.primary
                else MaterialTheme.colorScheme.surfaceContainerHighest,
                tween(300),
                label = "bar$i",
            )
            Box(
                Modifier
                    .weight(1f)
                    .height(4.dp)
                    .clip(RoundedCornerShape(2.dp))
                    .background(c),
            )
        }
    }
}

@Composable
private fun RootCard(rootOk: Boolean, checking: Boolean, label: String, onGrant: () -> Unit) {
    val scheme = MaterialTheme.colorScheme
    val bg by animateColorAsState(
        when {
            checking -> scheme.surfaceContainerHigh
            rootOk -> scheme.primaryContainer
            else -> scheme.errorContainer
        },
        tween(350),
        label = "rootBg",
    )
    val fg = when {
        checking -> scheme.onSurface
        rootOk -> scheme.onPrimaryContainer
        else -> scheme.onErrorContainer
    }
    Card(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(28.dp),
        colors = CardDefaults.cardColors(containerColor = bg, contentColor = fg),
    ) {
        Column(Modifier.padding(20.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(16.dp),
            ) {
                Box(
                    Modifier
                        .size(44.dp)
                        .clip(CircleShape)
                        .background(fg.copy(alpha = 0.12f)),
                    contentAlignment = Alignment.Center,
                ) {
                    if (checking) {
                        CircularProgressIndicator(
                            Modifier.size(22.dp),
                            color = fg,
                            strokeWidth = 2.5.dp,
                        )
                    } else {
                        Icon(
                            if (rootOk) Icons.Default.Check else Icons.Default.Close,
                            contentDescription = null,
                            tint = fg,
                        )
                    }
                }
                Column(Modifier.weight(1f)) {
                    Text(
                        when {
                            checking -> "Checking root access"
                            rootOk -> "Root access granted"
                            else -> "Root access not granted"
                        },
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.SemiBold,
                    )
                    Text(
                        when {
                            checking -> "Waiting for your root manager"
                            rootOk -> "Seiran can read and control kernel settings."
                            else -> "Allow Seiran in your root manager, then check again."
                        },
                        style = MaterialTheme.typography.bodyMedium,
                    )
                }
            }
            if (!rootOk) {
                Button(
                    onClick = onGrant,
                    enabled = !checking,
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(52.dp),
                ) { Text(label) }
            }
        }
    }
}

@Composable
private fun RootStep(
    rootOk: Boolean,
    checking: Boolean,
    buttonLabel: String,
    onGrant: () -> Unit,
) {
    Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
        Reveal(0) { Text("Root access", style = MaterialTheme.typography.headlineMedium) }
        Reveal(80) {
            Text(
                "Seiran reads and controls kernel settings, so it needs root. " +
                    "Allow Seiran in your root manager (KernelSU-Next, Superuser). " +
                    "If you denied it before, enable it in the Superuser list, then come back.",
                style = MaterialTheme.typography.bodyLarge,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        Reveal(160) { RootCard(rootOk, checking, buttonLabel, onGrant) }
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
private fun WelcomeStep() {
    var go by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) { go = true }
    val line by animateFloatAsState(
        if (go) 1f else 0f,
        tween(800, delayMillis = 350),
        label = "underline",
    )
    val accent = MaterialTheme.colorScheme.primary
    Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
        Reveal(0) {
            Text(
                "WELCOME TO",
                style = MaterialTheme.typography.labelLarge,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        Reveal(80) {
            Text(
                "Seiran",
                style = MaterialTheme.typography.displayMedium,
                modifier = Modifier
                    .drawBehind {
                        drawLine(
                            accent,
                            Offset(0f, size.height),
                            Offset(size.width * 0.55f * line, size.height),
                            strokeWidth = 5.dp.toPx(),
                            cap = StrokeCap.Round,
                        )
                    }
                    .padding(bottom = 8.dp),
            )
        }
        Reveal(180) {
            Image(
                painterResource(R.drawable.banner),
                null,
                Modifier
                    .fillMaxWidth()
                    .height(220.dp)
                    .clip(RoundedCornerShape(28.dp)),
                contentScale = ContentScale.Crop,
            )
        }
        Reveal(300) {
            Text(
                "Kernel status and controls for sapphire, in one place.",
                style = MaterialTheme.typography.bodyLarge,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

@Composable
private fun ModeCard(
    label: String,
    mode: Int,
    selected: Boolean,
    modifier: Modifier,
    onClick: () -> Unit,
) {
    val scheme = MaterialTheme.colorScheme
    val border by animateColorAsState(
        if (selected) scheme.primary else scheme.outlineVariant,
        tween(250),
        label = "modeBorder",
    )
    Card(
        onClick = onClick,
        modifier = modifier,
        shape = RoundedCornerShape(20.dp),
        colors = CardDefaults.cardColors(containerColor = scheme.surfaceContainer),
        border = BorderStroke(if (selected) 2.dp else 1.dp, border),
    ) {
        Column(
            Modifier.padding(12.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            // 0 = system (both halves), 1 = light, 2 = dark
            Row(
                Modifier
                    .fillMaxWidth()
                    .height(64.dp)
                    .clip(RoundedCornerShape(12.dp)),
            ) {
                if (mode != 2) Box(Modifier.weight(1f).fillMaxSize().background(Color(0xFFF2F2F2)))
                if (mode != 1) Box(Modifier.weight(1f).fillMaxSize().background(Color(0xFF151515)))
            }
            Text(
                label,
                style = MaterialTheme.typography.labelLarge,
                color = if (selected) scheme.primary else scheme.onSurface,
            )
        }
    }
}

@Composable
private fun ThemeStep(theme: ThemeState) {
    Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
        Reveal(0) { Text("Theme", style = MaterialTheme.typography.headlineMedium) }
        Reveal(80) {
            Text(
                "Pick how Seiran looks. You can change this later in Settings.",
                style = MaterialTheme.typography.bodyLarge,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        Reveal(160) {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                listOf("System", "Light", "Dark").forEachIndexed { i, label ->
                    ModeCard(label, i, theme.mode == i, Modifier.weight(1f)) { theme.setMode(i) }
                }
            }
        }
        Reveal(240) {
            Card(
                modifier = Modifier.fillMaxWidth(),
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
    val haptic = LocalHapticFeedback.current
    val last = step == 2
    Column(
        Modifier
            .fillMaxSize()
            .statusBarsPadding()
            .navigationBarsPadding()
            .padding(horizontal = 24.dp, vertical = 16.dp),
    ) {
        StepBar(step, 3)
        AnimatedContent(
            targetState = step,
            modifier = Modifier
                .weight(1f)
                .fillMaxWidth()
                .padding(top = 28.dp),
            transitionSpec = {
                val d = if (targetState > initialState) 1 else -1
                (fadeIn(tween(300)) + slideInHorizontally(tween(300)) { it / 5 * d }) togetherWith
                    (fadeOut(tween(200)) + slideOutHorizontally(tween(300)) { -it / 5 * d })
            },
            label = "onboardingStep",
        ) { s ->
            Column(
                Modifier
                    .fillMaxSize()
                    .verticalScroll(rememberScrollState()),
            ) {
                when (s) {
                    0 -> WelcomeStep()
                    1 -> RootStep(rootOk, checking, "Grant root", onGrant)
                    else -> ThemeStep(theme)
                }
            }
        }
        Row(
            Modifier
                .fillMaxWidth()
                .padding(top = 16.dp),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            if (step > 0) {
                OutlinedButton(
                    onClick = {
                        haptic.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                        step -= 1
                    },
                    modifier = Modifier.height(56.dp),
                ) { Text("Back", style = MaterialTheme.typography.titleMedium) }
            }
            Spacer(Modifier.weight(1f))
            Button(
                onClick = {
                    haptic.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                    if (last) onFinish() else step += 1
                },
                enabled = step != 1 || rootOk,
                modifier = Modifier.height(56.dp),
            ) { Text(if (last) "Let's go" else "Next", style = MaterialTheme.typography.titleMedium) }
        }
    }
}
