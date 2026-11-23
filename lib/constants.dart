import 'package:flutter/material.dart';
import 'models.dart';

// ─── Constantes de configuración ─────────────────────────────
// Versión 1.5.1
const kTimeoutSeconds = 5;   // Timeout REST por defecto
const kPollSeconds    = 15;  // Sondeo REST sin WebSocket
const kPollWsSeconds  = 30;  // Sondeo REST con WebSocket conectado
const kMaxRetries     = 3;
const kWsConnectTimeoutSeconds = 10;           // Timeout de conexión WebSocket
const kWsBackoff      = [1, 2, 4, 8, 15, 30];  // Esperas de reconexión (s)
const kUpdateCheckTimeoutSeconds = 10;         // Timeout de comprobación de versión
const kLabelRefreshSeconds = 5;                // Refresco de la etiqueta "Hace Xs"
const kHistoryMaxSize = 50;                    // Entradas máximas del historial
const kNotifChannelId   = 'ha_alarm_channel';
const kNotifChannelName = 'Alarma Casa HA';
const kBackupDir        = '/storage/emulated/0/Download/Alarma Casa Backups';
const kBackupVersion    = '1.2';

// ─── Colores ──────────────────────────────────────────────────
const kBg      = Color(0xFF0f172a);
const kSurface = Color(0xFF1e293b);
const kGreen   = Color(0xFF22c55e);
const kRed     = Color(0xFFef4444);
const kYellow  = Color(0xFFfacc15);
const kBlue    = Color(0xFF3b82f6);
const kOrange  = Color(0xFFf97316);
const kText    = Color(0xFFf1f5f9);
const kSubtext = Color(0xFF94a3b8);
const kPurple  = Color(0xFFa855f7);

// ─── Info de cada estado ──────────────────────────────────────
const stateInfo = {
  AlarmState.disarmed:   {'label': 'Desarmada',     'color': kGreen,   'icon': Icons.lock_open_rounded},
  AlarmState.armedAway:  {'label': 'Armada',         'color': kRed,     'icon': Icons.lock_rounded},
  AlarmState.armedHome:  {'label': 'Armada (Casa)',  'color': kOrange,  'icon': Icons.home_rounded},
  AlarmState.armedNight: {'label': 'Armada (Noche)', 'color': kPurple,  'icon': Icons.bedtime_rounded},
  AlarmState.armedCustomBypass: {'label': 'Armada (Vacaciones)', 'color': kBlue, 'icon': Icons.flight_rounded},
  AlarmState.arming:     {'label': 'Armando...',     'color': kOrange,  'icon': Icons.lock_clock_outlined},
  AlarmState.pending:    {'label': 'Entrada...',     'color': kYellow,  'icon': Icons.timer_outlined},
  AlarmState.triggered:  {'label': '¡ALARMA!',       'color': kRed,     'icon': Icons.warning_rounded},
  AlarmState.unknown:    {'label': 'Sin conexión',   'color': kSubtext, 'icon': Icons.help_outline_rounded},
};
