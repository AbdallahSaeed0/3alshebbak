package com.shebbak.shebbak

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

/**
 * Home-screen widget: the next shows at the user's starred cinemas. The app
 * writes the lines (lib/services/home_widget_sync.dart) whenever it loads
 * showtimes; this only draws them. Tapping it opens the app.
 */
class NextShowWidget : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        val rows = listOf(R.id.widget_row_1, R.id.widget_row_2, R.id.widget_row_3)
        val lines = (widgetData.getString("next_rows", null) ?: "")
            .split('\n')
            .filter { it.isNotBlank() }

        for (id in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.next_show_widget).apply {
                setTextViewText(
                    R.id.widget_title,
                    widgetData.getString("next_title", null) ?: "الجاي في سينماتك",
                )
                rows.forEachIndexed { i, row ->
                    val line = lines.getOrNull(i)
                    setTextViewText(row, line ?: "")
                    setViewVisibility(row, if (line == null) View.GONE else View.VISIBLE)
                }
                setTextViewText(R.id.widget_empty, widgetData.getString("next_empty", null) ?: "")
                setViewVisibility(R.id.widget_empty, if (lines.isEmpty()) View.VISIBLE else View.GONE)
                setOnClickPendingIntent(
                    R.id.widget_root,
                    HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java),
                )
            }
            appWidgetManager.updateAppWidget(id, views)
        }
    }
}
