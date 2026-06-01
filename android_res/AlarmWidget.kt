package com.homeassistant.ha_alarm

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.widget.RemoteViews
import android.app.PendingIntent

// ─── SharedPreferences de Flutter (shared_preferences plugin) ─
// Flutter shared_preferences ^2.x guarda en "FlutterSharedPreferences"
// con prefijo "flutter." en cada clave
private fun getFlutterPrefs(context: Context): SharedPreferences =
    context.getSharedPreferences(
        "FlutterSharedPreferences",
        Context.MODE_PRIVATE
    )

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

private fun launchIntent(context: Context): PendingIntent? {
    val intent = context.packageManager.getLaunchIntentForPackage(context.packageName)
        ?: return null
    return PendingIntent.getActivity(
        context, 0, intent,
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
    )
}

// ─── Widget 2×2 ───────────────────────────────────────────────
class AlarmWidget : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        try {
            val prefs      = getFlutterPrefs(context)
            // SharedPreferences de Flutter añade automáticamente "flutter." al guardar
            val stateLabel = prefs.getString("flutter.widget_state_label", "Alarma Casa") ?: "Alarma Casa"
            val updatedAt  = prefs.getString("flutter.widget_updated_at",  "") ?: ""
            val stateKey   = prefs.getString("flutter.widget_state_key",   "unknown") ?: "unknown"
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
        } catch (e: Exception) {
            // Si hay error, al menos no crashear - logs irían a logcat
            android.util.Log.e("AlarmWidget", "Error updating widget", e)
        }
    }

    companion object {
        fun updateAll(context: Context) {
            val intent = Intent(context, AlarmWidget::class.java).apply {
                action = AppWidgetManager.ACTION_APPWIDGET_UPDATE
                val ids = AppWidgetManager.getInstance(context)
                    .getAppWidgetIds(ComponentName(context, AlarmWidget::class.java))
                putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, ids)
            }
            context.sendBroadcast(intent)
        }
    }
}

// ─── Widget 2×1 ───────────────────────────────────────────────
class AlarmWidgetWide : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        try {
            val prefs      = getFlutterPrefs(context)
            val stateLabel = prefs.getString("flutter.widget_state_label", "Alarma Casa") ?: "Alarma Casa"
            val updatedAt  = prefs.getString("flutter.widget_updated_at",  "") ?: ""
            val stateKey   = prefs.getString("flutter.widget_state_key",   "unknown") ?: "unknown"
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
        } catch (e: Exception) {
            // Si hay error, al menos no crashear - logs irían a logcat
            android.util.Log.e("AlarmWidgetWide", "Error updating widget", e)
        }
    }

    companion object {
        fun updateAll(context: Context) {
            val intent = Intent(context, AlarmWidgetWide::class.java).apply {
                action = AppWidgetManager.ACTION_APPWIDGET_UPDATE
                val ids = AppWidgetManager.getInstance(context)
                    .getAppWidgetIds(ComponentName(context, AlarmWidgetWide::class.java))
                putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, ids)
            }
            context.sendBroadcast(intent)
        }
    }
}