// Versión 2026.11.4
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'constants.dart';

// ─── Estado de la alarma ──────────────────────────────────────
enum AlarmState {
  disarmed, armedAway, armedHome, armedNight, armedCustomBypass,
  arming, pending, triggered, unknown
}

AlarmState parseState(String s) {
  switch (s) {
    case 'disarmed':    return AlarmState.disarmed;
    case 'armed_away':  return AlarmState.armedAway;
    case 'armed_home':  return AlarmState.armedHome;
    case 'armed_night': return AlarmState.armedNight;
    case 'armed_custom_bypass': return AlarmState.armedCustomBypass;
    case 'arming':      return AlarmState.arming;
    case 'pending':     return AlarmState.pending;
    case 'triggered':   return AlarmState.triggered;
    default:            return AlarmState.unknown;
  }
}

// ─── Datos extendidos del estado ──────────────────────────────
class AlarmStateData {
  final AlarmState   state;
  final DateTime     lastChanged;
  final int?         delay;
  final List<String> openSensors;

  AlarmStateData({
    required this.state,
    required this.lastChanged,
    this.delay,
    this.openSensors = const [],
  });

  int  get elapsed     => DateTime.now().difference(lastChanged).inSeconds;
  int  get remaining   => delay != null ? (delay! - elapsed).clamp(0, delay!) : 0;
  bool get hasCountdown =>
      (state == AlarmState.arming || state == AlarmState.pending) && delay != null;

  Map<String, dynamic> toJson() => {
    'state':        state.name,
    'lastChanged':  lastChanged.toIso8601String(),
    'delay':        delay,
    'openSensors':  openSensors,
  };

  factory AlarmStateData.fromJson(Map<String, dynamic> json) => AlarmStateData(
    state:       parseState(json['state'] as String),
    lastChanged: DateTime.parse(json['lastChanged'] as String),
    delay:       json['delay'] as int?,
    openSensors: (json['openSensors'] as List?)?.cast<String>() ?? [],
  );
}

// ─── Zonas de Alarmo (solo informativas) ──────────────────────
class ZoneDef {
  final String   entityId, label, short; // short: abreviatura para el widget
  final IconData icon;
  /// input_boolean que marca que la zona la desarmó la automatización de robots
  final String?  autoFlagEntity;
  const ZoneDef({
    required this.entityId, required this.label, required this.short,
    required this.icon, this.autoFlagEntity,
  });
}

class ZoneData {
  final ZoneDef    def;
  final AlarmState state;
  final bool       autoDisarmed;
  final List<String> openSensors, bypassedSensors;
  const ZoneData({
    required this.def, required this.state, required this.autoDisarmed,
    this.openSensors = const [], this.bypassedSensors = const [],
  });

  /// Solo se puede armar una zona que un robot desarmó y aún no se rearmó
  bool get canArm => autoDisarmed && state == AlarmState.disarmed;
}

// ─── Tema ─────────────────────────────────────────────────────
enum AppThemeMode { system, light, dark }

AppThemeMode themeFromString(String? s) {
  switch (s) {
    case 'light':  return AppThemeMode.light;
    case 'dark':   return AppThemeMode.dark;
    default:       return AppThemeMode.system;
  }
}

String themeToString(AppThemeMode m) {
  switch (m) {
    case AppThemeMode.light:  return 'light';
    case AppThemeMode.dark:   return 'dark';
    case AppThemeMode.system: return 'system';
  }
}

ThemeMode toFlutterThemeMode(AppThemeMode m) {
  switch (m) {
    case AppThemeMode.light:  return ThemeMode.light;
    case AppThemeMode.dark:   return ThemeMode.dark;
    case AppThemeMode.system: return ThemeMode.system;
  }
}

// ─── Config ───────────────────────────────────────────────────
class Config {
  final String url, token, entityId, code, updateUrl;
  final int    timeoutSeconds;
  final bool   showArmModes;

  const Config({
    required this.url,
    required this.token,
    required this.entityId,
    required this.code,
    required this.updateUrl,
    this.timeoutSeconds = kTimeoutSeconds,
    this.showArmModes   = false,
  });

  bool get isValid => url.isNotEmpty && token.isNotEmpty && entityId.isNotEmpty;

  static Future<Config> load() async {
    final p = await SharedPreferences.getInstance();
    final secure = const FlutterSecureStorage();
    final token  = await secure.read(key: 'ha_token') ?? p.getString('ha_token') ?? '';
    final code   = await secure.read(key: 'ha_code')  ?? p.getString('ha_code')  ?? '';
    // Migración: si quedan token/código en claro, pasarlos al almacén seguro y borrarlos
    if (p.containsKey('ha_token') || p.containsKey('ha_code')) {
      if (token.isNotEmpty) await secure.write(key: 'ha_token', value: token);
      if (code.isNotEmpty)  await secure.write(key: 'ha_code',  value: code);
      await p.remove('ha_token');
      await p.remove('ha_code');
    }
    return Config(
      url:            p.getString('ha_url')       ?? '',
      token:          token,
      entityId:       p.getString('ha_entity')    ?? '',
      code:           code,
      updateUrl:      p.getString('ha_updateUrl') ?? '',
      timeoutSeconds: p.getInt('ha_timeout')      ?? kTimeoutSeconds,
      showArmModes:   p.getBool('show_arm_modes') ?? false,
    );
  }

  Future<void> save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('ha_url',       url);
    await p.setString('ha_entity',    entityId);
    await p.setString('ha_updateUrl', updateUrl);
    await p.setInt('ha_timeout',      timeoutSeconds);
    await p.setBool('show_arm_modes', showArmModes);

    final secure = const FlutterSecureStorage();
    if (token.isNotEmpty) await secure.write(key: 'ha_token', value: token);
    if (code.isNotEmpty) await secure.write(key: 'ha_code', value: code);

    if (p.containsKey('ha_token')) await p.remove('ha_token');
    if (p.containsKey('ha_code'))  await p.remove('ha_code');
  }
}

// ─── Historial ────────────────────────────────────────────────
class HistoryEntry {
  final AlarmState state;
  final DateTime   timestamp;
  final String?    zone;   // null = alarma maestra
  final bool       robot;  // cambio hecho por la automatización de robots

  HistoryEntry({
    required this.state, required this.timestamp, this.zone, this.robot = false,
  });

  Map<String, dynamic> toJson() => {
    'state':     state.name,
    'timestamp': timestamp.toIso8601String(),
    if (zone != null) 'zone': zone,
    if (robot) 'robot': true,
  };

  // Tolerante con entradas antiguas (sin zona ni robot)
  static HistoryEntry fromJson(Map<String, dynamic> j) => HistoryEntry(
    state: AlarmState.values.firstWhere(
        (e) => e.name == j['state'], orElse: () => AlarmState.unknown),
    timestamp: DateTime.parse(j['timestamp'] as String),
    zone:  j['zone'] as String?,
    robot: j['robot'] == true,
  );
}

class HistoryService {
  static const _key     = 'alarm_history';
  static const _maxSize = kHistoryMaxSize;

  // Las operaciones se encadenan para que dos escrituras seguidas no se pisen
  static Future<void> _cola = Future.value();
  static Future<void> _serie(Future<void> Function() op) {
    final r = _cola.then((_) => op());
    _cola = r.then((_) {}, onError: (_) {});
    return r;
  }

  static Future<List<HistoryEntry>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw   = prefs.getStringList(_key) ?? [];
    return raw
        .map((s) => HistoryEntry.fromJson(jsonDecode(s) as Map<String, dynamic>))
        .toList();
  }

  static Future<void> _guardar(SharedPreferences prefs, List<HistoryEntry> entries) =>
      prefs.setStringList(_key, entries.map((e) => jsonEncode(e.toJson())).toList());

  /// Añade un cambio de estado (de la maestra o de una zona). No repite
  /// si el último registro de esa misma zona ya tenía ese estado.
  static Future<void> add(AlarmState state, {String? zone, bool robot = false}) =>
      _serie(() async {
        final entries = await load();
        final last = entries.where((e) => e.zone == zone).firstOrNull;
        if (last != null && last.state == state) return;
        entries.insert(0, HistoryEntry(
            state: state, timestamp: DateTime.now(), zone: zone, robot: robot));
        if (entries.length > _maxSize) entries.removeLast();
        await _guardar(await SharedPreferences.getInstance(), entries);
      });

  /// Marca como "de robot" el último desarme de una zona (la marca de HA
  /// se activa después del propio desarme).
  static Future<void> markRobot(String zone) => _serie(() async {
        final entries = await load();
        final i = entries.indexWhere((e) => e.zone == zone);
        if (i < 0 || entries[i].robot || entries[i].state != AlarmState.disarmed) return;
        final e = entries[i];
        entries[i] = HistoryEntry(
            state: e.state, timestamp: e.timestamp, zone: e.zone, robot: true);
        await _guardar(await SharedPreferences.getInstance(), entries);
      });

  static Future<void> clear() => _serie(() async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(_key);
      });
}
