package io.easynote.app

import android.content.Context
import android.net.Uri
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.action.clickable
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.cornerRadius
import androidx.glance.appwidget.lazy.LazyColumn
import androidx.glance.appwidget.lazy.items
import androidx.glance.appwidget.provideContent
import androidx.glance.background
import androidx.glance.color.ColorProvider
import androidx.glance.currentState
import androidx.glance.layout.Alignment
import androidx.glance.layout.Box
import androidx.glance.layout.Column
import androidx.glance.layout.Row
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.height
import androidx.glance.layout.padding
import androidx.glance.layout.size
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextStyle
import es.antonborri.home_widget.HomeWidgetGlanceState
import es.antonborri.home_widget.HomeWidgetGlanceStateDefinition
import es.antonborri.home_widget.actionStartActivity
import org.json.JSONArray

private data class RecentNote(val path: String, val title: String, val preview: String)

// Same palette as the app: a white index card, navy ink, a crimson rule.
private val card = ColorProvider(day = Color(0xFFFFFFFF), night = Color(0xFF1B2336))
private val ink = ColorProvider(day = Color(0xFF1F2A44), night = Color(0xFFE4E9F2))
private val muted = ColorProvider(day = Color(0xFF5E6A82), night = Color(0xFF97A3BA))
private val accent = ColorProvider(day = Color(0xFFC8344F), night = Color(0xFFF06B84))
private val rule = ColorProvider(day = Color(0xFFE5ECF6), night = Color(0xFF222D44))

/// Recent notes of this device. Shows the snapshot the app last saved; it
/// never syncs by itself. Tapping a note opens it, "+" starts a new one.
class RecentNotesWidget : GlanceAppWidget() {
    override val stateDefinition = HomeWidgetGlanceStateDefinition()

    override suspend fun provideGlance(context: Context, id: GlanceId) {
        provideContent { Content(context, currentState()) }
    }

    private fun parse(json: String): List<RecentNote> = try {
        val a = JSONArray(json)
        (0 until a.length()).map {
            val o = a.getJSONObject(it)
            RecentNote(o.getString("path"), o.optString("title"), o.optString("preview"))
        }
    } catch (e: Exception) {
        emptyList()
    }

    @Composable
    private fun Content(context: Context, state: HomeWidgetGlanceState) {
        val notes = parse(state.preferences.getString("recent", null) ?: "[]")
        Column(
            modifier = GlanceModifier.fillMaxSize().background(card).cornerRadius(12.dp)
                .padding(horizontal = 14.dp, vertical = 10.dp),
        ) {
            Row(
                modifier = GlanceModifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    "easynote",
                    modifier = GlanceModifier.defaultWeight()
                        .clickable(actionStartActivity<MainActivity>(context)),
                    style = TextStyle(color = ink, fontSize = 16.sp, fontWeight = FontWeight.Bold),
                )
                Box(
                    modifier = GlanceModifier.size(40.dp)
                        .clickable(actionStartActivity<MainActivity>(context, Uri.parse("easynote://new"))),
                    contentAlignment = Alignment.Center,
                ) {
                    Text("+", style = TextStyle(color = ink, fontSize = 24.sp))
                }
            }
            Spacer(GlanceModifier.height(4.dp))
            Box(GlanceModifier.fillMaxWidth().height(2.dp).background(accent)) {}
            if (notes.isEmpty()) {
                Text(
                    "Notes you open in easynote appear here.",
                    modifier = GlanceModifier.padding(top = 12.dp),
                    style = TextStyle(color = muted, fontSize = 13.sp),
                )
            } else {
                LazyColumn(modifier = GlanceModifier.fillMaxSize()) {
                    items(notes, itemId = { it.path.hashCode().toLong() }) { n ->
                        val open = Uri.parse("easynote://open?path=" + Uri.encode(n.path))
                        Column(
                            modifier = GlanceModifier.fillMaxWidth()
                                .clickable(actionStartActivity<MainActivity>(context, open)),
                        ) {
                            Column(modifier = GlanceModifier.fillMaxWidth().padding(vertical = 8.dp)) {
                                Text(
                                    n.title,
                                    maxLines = 1,
                                    style = TextStyle(color = ink, fontSize = 15.sp, fontWeight = FontWeight.Bold),
                                )
                                if (n.preview.isNotEmpty()) {
                                    Text(
                                        n.preview,
                                        maxLines = 2,
                                        style = TextStyle(color = muted, fontSize = 13.sp),
                                    )
                                }
                            }
                            Box(GlanceModifier.fillMaxWidth().height(1.dp).background(rule)) {}
                        }
                    }
                }
            }
        }
    }
}
