package com.homeassistant.ha_alarm

import android.appwidget.AppWidgetManager
import android.content.Context
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider

class AlarmWidget : HomeWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: android.content.SharedPreferences
    ) {
        val stateLabel = widgetData.getString("state_label", "—") ?: "—"
        val updatedAt  = widgetData.getString("updated_at",  "")  ?: ""
        val stateKey   = widgetData.getString("state_key",   "unknown") ?: "unknown"

        for (widgetId in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.alarm_widget)

            // Texto
            views.setTextViewText(R.id.widget_state, stateLabel)
            views.setTextViewText(R.id.widget_time,  if (updatedAt.isNotEmpty()) "Actualizado: $updatedAt" else "")

            // Color del texto según estado
            val color = when (stateKey) {
                "disarmed"   -> android.graphics.Color.parseColor("#22c55e") // verde
                "armedAway",
                "triggered"  -> android.graphics.Color.parseColor("#ef4444") // rojo
                "armedHome",
                "arming"     -> android.graphics.Color.parseColor("#f97316") // naranja
                "armedNight" -> android.graphics.Color.parseColor("#a855f7") // morado
                "pending"    -> android.graphics.Color.parseColor("#facc15") // amarillo
                else         -> android.graphics.Color.parseColor("#94a3b8") // gris
            }
            views.setTextColor(R.id.widget_state, color)

            // Tap abre la app
            val intent = context.packageManager
                .getLaunchIntentForPackage(context.packageName)
            if (intent != null) {
                val pendingIntent = android.app.PendingIntent.getActivity(
                    context, 0, intent,
                    android.app.PendingIntent.FLAG_UPDATE_CURRENT or
                    android.app.PendingIntent.FLAG_IMMUTABLE
                )
                views.setOnClickPendingIntent(R.id.widget_state, pendingIntent)
            }

            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }
}