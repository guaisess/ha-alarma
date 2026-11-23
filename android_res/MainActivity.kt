// Versión 2026.11.12
package es.fernandezbadia.alarmacasa

import android.content.Intent
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "es.fernandezbadia.alarmacasa/widget"
    private val EXTRA_ACCION = "widget_action"

    private var channel: MethodChannel? = null
    // Acción pedida desde el widget cuando la app estaba cerrada (arranque en frío)
    private var accionPendiente: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        leerAccion(intent)
    }

    // Con la app ya abierta, el widget llega aquí (la actividad es singleTop)
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        val accion = intent.getStringExtra(EXTRA_ACCION)
        if (accion != null) {
            intent.removeExtra(EXTRA_ACCION)
            channel?.invokeMethod("widgetAction", accion)
        }
    }

    private fun leerAccion(intent: Intent?) {
        accionPendiente = intent?.getStringExtra(EXTRA_ACCION)
        // Se consume para que girar la pantalla no repita la acción
        intent?.removeExtra(EXTRA_ACCION)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        channel!!.setMethodCallHandler { call, result ->
            when (call.method) {
                "updateWidget" -> {
                    AlarmWidget.updateAll(applicationContext)
                    AlarmWidgetWide.updateAll(applicationContext)
                    result.success(null)
                }
                "getLaunchAction" -> {
                    result.success(accionPendiente)
                    accionPendiente = null
                }
                else -> result.notImplemented()
            }
        }
    }
}
