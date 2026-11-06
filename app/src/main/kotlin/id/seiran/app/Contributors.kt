package id.seiran.app

import android.content.Context
import android.graphics.BitmapFactory
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectTransformGestures
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import kotlin.concurrent.thread
import org.json.JSONArray

private class Person(val login: String, val name: String, val avatar: ImageBitmap?)

private fun loadPeople(ctx: Context): List<Person> = try {
    val txt = ctx.assets.open("contributors.json").bufferedReader().use { it.readText() }
    val arr = JSONArray(txt)
    List(arr.length()) { i ->
        val o = arr.getJSONObject(i)
        val login = o.getString("login")
        val bmp = if (o.optBoolean("avatar")) {
            try {
                ctx.assets.open("avatars/$login.webp").use { BitmapFactory.decodeStream(it) }?.asImageBitmap()
            } catch (e: Exception) {
                null
            }
        } else {
            null
        }
        Person(login, o.optString("name", login), bmp)
    }
} catch (e: Exception) {
    emptyList()
}

// Hex packing from the centre outwards: 1, 6, 12, ... bubbles per ring.
private fun hexCenters(n: Int, step: Float): List<Offset> {
    val dirs = arrayOf(1 to 0, 1 to -1, 0 to -1, -1 to 0, -1 to 1, 0 to 1)
    val axial = ArrayList<Pair<Int, Int>>()
    axial.add(0 to 0)
    var k = 1
    while (axial.size < n) {
        var q = -k
        var r = k
        for (side in 0 until 6) {
            for (j in 0 until k) {
                axial.add(q to r)
                q += dirs[side].first
                r += dirs[side].second
            }
        }
        k++
    }
    return axial.take(n).map { (q, r) -> Offset(step * (q + r / 2f), step * 0.8660254f * r) }
}

@Composable
private fun ContributorWall(people: List<Person>, onSelect: (Person) -> Unit, modifier: Modifier) {
    val density = LocalDensity.current
    val avatar = 56.dp
    val avatarPx = with(density) { avatar.toPx() }
    val step = avatarPx * 1.15f
    val centers = remember(people.size, step) { hexCenters(people.size, step) }
    val reach = remember(centers) { (centers.maxOfOrNull { it.getDistance() } ?: 0f) + avatarPx }
    var scale by remember { mutableFloatStateOf(1f) }
    var offset by remember { mutableStateOf(Offset.Zero) }
    var box by remember { mutableStateOf(IntSize.Zero) }

    Box(
        modifier
            .clipToBounds()
            .onSizeChanged { box = it }
            .pointerInput(reach) {
                detectTransformGestures { centroid, pan, zoom, _ ->
                    val c = Offset(box.width / 2f, box.height / 2f)
                    val next = (scale * zoom).coerceIn(0.6f, 3f)
                    val rel = centroid - c
                    val moved = rel - (rel - offset) * (next / scale) + pan
                    val lim = reach * next
                    offset = Offset(moved.x.coerceIn(-lim, lim), moved.y.coerceIn(-lim, lim))
                    scale = next
                }
            },
        contentAlignment = Alignment.Center,
    ) {
        people.forEachIndexed { i, p ->
            Box(
                Modifier
                    .size(avatar)
                    .graphicsLayer {
                        val half = minOf(box.width, box.height) / 2f
                        val pos = offset + centers[i] * scale
                        val fade = ((pos.getDistance() - half * 0.7f) / (half * 0.5f).coerceAtLeast(1f))
                            .coerceIn(0f, 1f)
                        val s = scale * (1f - 0.65f * fade)
                        scaleX = s
                        scaleY = s
                        translationX = pos.x
                        translationY = pos.y
                        alpha = 1f - 0.5f * fade
                    }
                    .clip(CircleShape)
                    .background(MaterialTheme.colorScheme.surfaceContainerHighest)
                    .clickable { onSelect(p) },
                contentAlignment = Alignment.Center,
            ) {
                val bmp = p.avatar
                if (bmp != null) {
                    Image(
                        bitmap = bmp,
                        contentDescription = p.name,
                        contentScale = ContentScale.Crop,
                        modifier = Modifier.fillMaxSize(),
                    )
                } else {
                    Text(
                        p.name.take(1).uppercase(),
                        style = MaterialTheme.typography.titleLarge,
                        fontWeight = FontWeight.Bold,
                    )
                }
            }
        }
    }
}

@Composable
fun ContributorsSection(modifier: Modifier = Modifier) {
    val ctx = LocalContext.current
    val uri = LocalUriHandler.current
    var people by remember { mutableStateOf<List<Person>>(emptyList()) }
    var picked by remember { mutableStateOf<Person?>(null) }
    LaunchedEffect(Unit) { thread { people = loadPeople(ctx.applicationContext) } }

    Card(
        modifier = modifier.fillMaxWidth(),
        shape = RoundedCornerShape(24.dp),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceContainer,
        ),
    ) {
        Column(Modifier.padding(16.dp)) {
            Text("Contributors", style = MaterialTheme.typography.titleMedium)
            Text(
                "People and projects Seiran builds on. Pinch, drag, tap a face.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            ContributorWall(
                people,
                { picked = it },
                Modifier
                    .fillMaxWidth()
                    .height(340.dp)
                    .padding(top = 8.dp),
            )
        }
    }

    picked?.let { p ->
        AlertDialog(
            onDismissRequest = { picked = null },
            title = { Text(p.name) },
            text = { Text("github.com/" + p.login) },
            confirmButton = {
                TextButton(onClick = {
                    runCatching { uri.openUri("https://github.com/" + p.login) }
                    picked = null
                }) { Text("Open GitHub") }
            },
            dismissButton = { TextButton(onClick = { picked = null }) { Text("Close") } },
        )
    }
}
