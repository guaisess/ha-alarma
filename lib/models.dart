import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

// ─── Estado de la alarma ──────────────────────────────────────
enum AlarmState {
  disarmed, armedAway, armedHome, armedNight,
  arming, pending, triggered, unknown
}

AlarmState parseState(String s) {
  switch (s) {
    case 'disarmed':    return AlarmState.disarmed;
    case 'armed_away':  return AlarmState.armedAway;
    case 'armed_home':  return AlarmState.armedHome;
    case 'armed_night': return AlarmState.armedNight;
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

  const Config({
    required this.url,
    required this.token,
    required this.entityId,
    required this.code,
    required this.updateUrl,
    this.timeoutSeconds = 5,
  });

  bool get isValid => url.isNotEmpty && token.isNotEmpty && entityId.isNotEmpty;

  static Future<Config> load() async {
    final p = await SharedPreferences.getInstance();
    return Config(
      url:            p.getString('ha_url')       ?? '',
      token:          p.getString('ha_token')     ?? '',
      entityId:       p.getString('ha_entity')    ?? '',
      code:           p.getString('ha_code')      ?? '',
      updateUrl:      p.getString('ha_updateUrl') ?? '',
      timeoutSeconds: p.getInt('ha_timeout')      ?? 5,
    );
  }

  Future<void> save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('ha_url',       url);
    await p.setString('ha_token',     token);
    await p.setString('ha_entity',    entityId);
    await p.setString('ha_code',      code);
    await p.setString('ha_updateUrl', updateUrl);
    await p.setInt('ha_timeout',      timeoutSeconds);
  }
}

// ─── Historial ────────────────────────────────────────────────
class HistoryEntry {
  final AlarmState state;
  final DateTime   timestamp;

  HistoryEntry({required this.state, required this.timestamp});

  Map<String, dynamic> toJson() => {
    'state':     state.name,
    'timestamp': timestamp.toIso8601String(),
  };

  static HistoryEntry fromJson(Map<String, dynamic> j) => HistoryEntry(
    state: AlarmState.values.firstWhere(
        (e) => e.name == j['state'], orElse: () => AlarmState.unknown),
    timestamp: DateTime.parse(j['timestamp'] as String),
  );
}

class HistoryService {
  static const _key     = 'alarm_history';
  static const _maxSize = 50;

  static Future<List<HistoryEntry>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw   = prefs.getStringList(_key) ?? [];
    return raw
        .map((s) => HistoryEntry.fromJson(jsonDecode(s) as Map<String, dynamic>))
        .toList();
  }

  static Future<void> add(AlarmState state) async {
    final prefs   = await SharedPreferences.getInstance();
    final raw     = prefs.getStringList(_key) ?? [];
    final entries = raw
        .map((s) => HistoryEntry.fromJson(jsonDecode(s) as Map<String, dynamic>))
        .toList();

    if (entries.isNotEmpty && entries.first.state == state) return;

    entries.insert(0, HistoryEntry(state: state, timestamp: DateTime.now()));
    if (entries.length > _maxSize) entries.removeLast();

    await prefs.setStringList(
        _key, entries.map((e) => jsonEncode(e.toJson())).toList());
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
