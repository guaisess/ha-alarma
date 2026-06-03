import 'package:flutter/material.dart';
import 'models.dart';

// ─── Constantes de configuración ─────────────────────────────
const kTimeoutSeconds = 5;
const kPollSeconds    = 15;
const kMaxRetries     = 3;

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
