package com.homeassistant.ha_alarm

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider

class AlarmWidget : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences
    ) {
        val stateLabel = widgetData.getString("state_label", "Cargando...") ?: "Cargando..."
        val updatedAt  = widgetData.getString("updated_at",  "") ?: ""
        val stateKey   = widgetData.getString("state_key",   "unknown") ?: "unknown"
        val color      = colorForState(stateKey)
        val pending    = launchIntent(context)

        for (id in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.alarm_widget)
            views.setTextViewText(R.id.widget_state, stateLabel)
            views.setTextViewText(R.id.widget_time,
                if (updatedAt.isNotEmpty()) "Act: $updatedAt" else "")
            views.setTextColor(R.id.widget_state, color)
            if (pending != null) views.setOnClickPendingIntent(R.id.widget_state, pending)
            appWidgetManager.updateAppWidget(id, views)
        }
    }
}

class AlarmWidgetWide : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences
    ) {
        val stateLabel = widgetData.getString("state_label", "Cargando...") ?: "Cargando..."
        val updatedAt  = widgetData.getString("updated_at",  "") ?: ""
        val stateKey   = widgetData.getString("state_key",   "unknown") ?: "unknown"
        val color      = colorForState(stateKey)
        val pending    = launchIntent(context)

        for (id in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.alarm_widget_wide)
            views.setTextViewText(R.id.widget_wide_state, stateLabel)
            views.setTextViewText(R.id.widget_wide_time,
                if (updatedAt.isNotEmpty()) "Act: $updatedAt" else "")
            views.setTextColor(R.id.widget_wide_state, color)
            if (pending != null) {
                views.setOnClickPendingIntent(R.id.widget_wide_state, pending)
                views.setOnClickPendingIntent(R.id.widget_wide_icon,  pending)
            }
            appWidgetManager.updateAppWidget(id, views)
        }
    }
}

private fun colorForState(key: String): Int = when (key) {
    "disarmed"   -> android.graphics.Color.parseColor("#22c55e")
    "armedAway",
    "triggered"  -> android.graphics.Color.parseColor("#ef4444")
    "armedHome",
    "arming"     -> android.graphics.Color.parseColor("#f97316")
    "armedNight" -> android.graphics.Color.parseColor("#a855f7")
    "pending"    -> android.graphics.Color.parseColor("#facc15")
    else         -> android.graphics.Color.parseColor("#94a3b8")
}

private fun launchIntent(context: Context): android.app.PendingIntent? {
    val intent = context.packageManager.getLaunchIntentForPackage(context.packageName)
        ?: return null
    return android.app.PendingIntent.getActivity(
        context, 0, intent,
        android.app.PendingIntent.FLAG_UPDATE_CURRENT or
        android.app.PendingIntent.FLAG_IMMUTABLE
    )
}