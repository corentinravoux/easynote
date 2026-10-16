package io.easynote.app

import es.antonborri.home_widget.HomeWidgetGlanceWidgetReceiver

class RecentNotesWidgetReceiver : HomeWidgetGlanceWidgetReceiver<RecentNotesWidget>() {
    override val glanceAppWidget = RecentNotesWidget()
}
