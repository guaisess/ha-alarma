import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:dio/dio.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:vibration/vibration.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'models.dart';

// ─── Servicio Home Assistant ──────────────────────────────────
class HaService {
  final Config config;
  HaService(this.config);

  Map<String, String> get _headers => {
    'Authorization': 'Bearer ${config.token}',
    'Content-Type':  'application/json',
  };

  Duration get _timeout => Duration(seconds: config.timeoutSeconds);

  Future<AlarmStateData> getState() async {
    final uri = Uri.parse('${config.url}/api/states/${config.entityId}');
    final res = await http.get(uri, headers: _headers).timeout(_timeout);
    if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');

    final data        = jsonDecode(res.body);
    final state       = parseState(data['state'] as String);
    final attrs       = data['attributes'] as Map<String, dynamic>? ?? {};
    final lastChanged = DateTime.parse(data['last_changed'] as String).toLocal();

    int? delay;
    if (attrs.containsKey('delay')) {
      delay = (attrs['delay'] as num?)?.toInt();
    }

    List<String> openSensors = [];
    if (attrs.containsKey('open_sensors')) {
      final raw = attrs['open_sensors'];
      if (raw is Map)  openSensors = raw.keys.map((k) => k.toString()).toList();
      if (raw is List) openSensors = raw.map((e) => e.toString()).toList();
    }

    return AlarmStateData(
      state: state, lastChanged: lastChanged,
      delay: delay,  openSensors: openSensors,
    );
  }

  Future<void> disarm()  => _call('alarm_disarm',  {'code': config.code});
  Future<void> armAway() => _call('alarm_arm_away', {});

  Future<void> _call(String service, Map<String, dynamic> extra) async {
    final uri  = Uri.parse('${config.url}/api/services/alarm_control_panel/$service');
    final body = jsonEncode({'entity_id': config.entityId, ...extra});
    final res  = await http.post(uri, headers: _headers, body: body).timeout(_timeout);
    if (res.statusCode != 200 && res.statusCode != 201) {
      throw Exception('HTTP ${res.statusCode}');
    }
  }
}

// ─── WebSocket para eventos en tiempo real ────────────────────
class HaWebSocketService {
  WebSocket? _ws;
  StreamSubscription? _sub;
  Timer? _reconnectTimer;
  bool _authenticated = false;
  bool _subscribed = false;
  int _msgId = 0;
  int _reconnectAttempts = 0;
  String? _url, _token, _entityId;

  static const _backoff = [1, 2, 4, 8, 15, 30];

  final void Function(AlarmStateData data) onStateChanged;
  final void Function(bool connected) onConnectionChanged;

  HaWebSocketService({required this.onStateChanged, required this.onConnectionChanged});

  String _toWsUrl(String httpUrl) {
    final wsUrl = httpUrl
        .replaceFirst('https://', 'wss://')
        .replaceFirst('http://', 'ws://');
    return '${wsUrl.replaceAll(RegExp(r'/$'), '')}/api/websocket';
  }

  Future<void> connect(String url, String token, String entityId) async {
    await disconnect();
    _url = url;
    _token = token;
    _entityId = entityId;
    _reconnectAttempts = 0;
    onConnectionChanged(false);
    try {
      final wsUrl = _toWsUrl(url);
      _ws = await WebSocket.connect(wsUrl).timeout(const Duration(seconds: 10));
      _sub = _ws!.listen(
        (data) => _handleMessage(data),
        onDone: _onDisconnected,
        onError: (e) {
          debugPrint('[HA WS] Error: $e');
          _onDisconnected();
        },
      );
    } catch (e) {
      debugPrint('[HA WS] Connection failed: $e');
      onConnectionChanged(false);
      _scheduleReconnect();
    }
  }

  void _onDisconnected() {
    _authenticated = false;
    _subscribed = false;
    onConnectionChanged(false);
    _scheduleReconnect();
  }

  void _handleMessage(dynamic raw) {
    try {
      final msg = jsonDecode(raw as String) as Map<String, dynamic>;
      final type = msg['type'] as String;
      final entityId = _entityId;
      if (entityId == null) return;

      if (!_authenticated && type == 'auth_required') {
        _ws?.add(jsonEncode({'type': 'auth', 'access_token': _token}));
        return;
      }

      if (!_authenticated && type == 'auth_ok') {
        _authenticated = true;
        _ws?.add(jsonEncode({
          'id': ++_msgId,
          'type': 'subscribe_events',
          'event_type': 'state_changed',
        }));
        return;
      }

      if (!_authenticated && type == 'auth_invalid') {
        debugPrint('[HA WS] Auth invalid');
        return;
      }

      if (!_subscribed && type == 'result' && msg['success'] == true) {
        _subscribed = true;
        _reconnectAttempts = 0;
        onConnectionChanged(true);
        return;
      }

      if (_subscribed && type == 'event') {
        final event = msg['event'] as Map<String, dynamic>?;
        if (event == null) return;
        final eventData = event['data'] as Map<String, dynamic>?;
        if (eventData == null) return;
        final eventEntityId = eventData['entity_id'] as String?;
        if (eventEntityId != entityId) return;

        final newState = eventData['new_state'] as Map<String, dynamic>?;
        if (newState == null) return;

        final state = parseState(newState['state'] as String? ?? 'unknown');
        final attrs = newState['attributes'] as Map<String, dynamic>? ?? {};
        final lastChanged = DateTime.tryParse(newState['last_changed'] as String? ?? '')?.toLocal() ?? DateTime.now();

        int? delay;
        if (attrs.containsKey('delay')) delay = (attrs['delay'] as num?)?.toInt();

        List<String> openSensors = [];
        if (attrs.containsKey('open_sensors')) {
          final raw = attrs['open_sensors'];
          if (raw is Map)  openSensors = raw.keys.map((k) => k.toString()).toList();
          if (raw is List) openSensors = raw.map((e) => e.toString()).toList();
        }

        onStateChanged(AlarmStateData(
          state: state, lastChanged: lastChanged,
          delay: delay, openSensors: openSensors,
        ));
      }
    } catch (e) {
      debugPrint('[HA WS] Parse error: $e');
    }
  }

  void _scheduleReconnect() {
    if (_url == null || _token == null || _entityId == null) return;
    _reconnectTimer?.cancel();
    final seconds = _reconnectAttempts < _backoff.length
        ? _backoff[_reconnectAttempts] : _backoff.last;
    _reconnectAttempts++;
    debugPrint('[HA WS] Reconnect in ${seconds}s (attempt $_reconnectAttempts)');
    _reconnectTimer = Timer(Duration(seconds: seconds),
        () => connect(_url!, _token!, _entityId!));
  }

  Future<void> disconnect() async {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    await _sub?.cancel();
    _sub = null;
    await _ws?.close();
    _ws = null;
    _authenticated = false;
    _subscribed = false;
  }

  bool get isConnected => _subscribed;
}

// ─── Cache de estado ──────────────────────────────────────────
class StateCache {
  static const _key = 'cached_state';

  static Future<void> save(AlarmStateData data) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, jsonEncode(data.toJson()));
    } catch (e) {
      debugPrint('[Cache] Error saving: $e');
    }
  }

  static Future<AlarmStateData?> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null) return null;
      return AlarmStateData.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (e) {
      debugPrint('[Cache] Error loading: $e');
      return null;
    }
  }
}

// ─── Feedback (haptic + beep) ─────────────────────────────────
class FeedbackService {
  static Future<void> confirm() async {
    await SystemSound.play(SystemSoundType.click);
    if (await Vibration.hasVibrator() ?? false) {
      Vibration.vibrate(duration: 80);
    }
  }

  static Future<void> error() async {
    if (await Vibration.hasVibrator() ?? false) {
      Vibration.vibrate(pattern: [0, 100, 80, 100]);
    }
  }
}

// ─── Servicio de actualización ────────────────────────────────
class UpdateInfo {
  final String version, apkUrl;
  UpdateInfo({required this.version, required this.apkUrl});
}

class UpdateService {
  static bool _checkedThisSession = false;

  static bool _isNewer(String remote, String current) {
    List<int> parse(String v) =>
        v.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final r = parse(remote);
    final c = parse(current);
    for (int i = 0; i < 3; i++) {
      final rv = i < r.length ? r[i] : 0;
      final cv = i < c.length ? c[i] : 0;
      if (rv > cv) return true;
      if (rv < cv) return false;
    }
    return false;
  }

  static Future<UpdateInfo?> check(String url) async {
    if (_checkedThisSession) return null;
    _checkedThisSession = true;
    try {
      final res = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return null;
      final data          = jsonDecode(res.body);
      final remoteVersion = data['version'] as String;
      final apkUrl        = data['url'] as String;
      final info          = await PackageInfo.fromPlatform();
      final prefs         = await SharedPreferences.getInstance();
      if (prefs.getString('last_update_notified') == remoteVersion) return null;
      if (_isNewer(remoteVersion, info.version)) {
        return UpdateInfo(version: remoteVersion, apkUrl: apkUrl);
      }
    } catch (e) {
      debugPrint('[Update] Check failed: $e');
    }
    return null;
  }

  static Future<void> downloadAndInstall(
      String url, void Function(double) onProgress) async {
    if (Platform.isAndroid) {
      final status = await Permission.requestInstallPackages.request();
      if (!status.isGranted) throw Exception('Permiso de instalación denegado');
    }
    final dir  = await getExternalStorageDirectory();
    final path = '${dir!.path}/ha_alarm_update.apk';
    await Dio().download(url, path, onReceiveProgress: (recv, total) {
      if (total > 0) onProgress(recv / total);
    });
    await OpenFile.open(path);
  }
}

// ─── Servicio de Backup/Restore ───────────────────────────────
class BackupService {
  static String _generateFilename() {
    final now = DateTime.now();
    final date = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final time = '${now.hour.toString().padLeft(2, '0')}-${now.minute.toString().padLeft(2, '0')}-${now.second.toString().padLeft(2, '0')}';
    return 'alarma_backup_$date\_$time.json';
  }

  static Future<String> export({bool includeHistory = false}) async {
    final prefs = await SharedPreferences.getInstance();
    final secure = const FlutterSecureStorage();

    final backup = {
      'version': '1.1',
      'timestamp': DateTime.now().toIso8601String(),
      'config': {
        'url':       prefs.getString('ha_url')       ?? '',
        'token':     await secure.read(key: 'ha_token') ?? prefs.getString('ha_token') ?? '',
        'entity':    prefs.getString('ha_entity')    ?? '',
        'code':      await secure.read(key: 'ha_code') ?? prefs.getString('ha_code') ?? '',
        'updateUrl': prefs.getString('ha_updateUrl') ?? '',
        'timeout':   prefs.getInt('ha_timeout')      ?? 5,
        'theme':     prefs.getString('app_theme')    ?? 'system',
      },
    };

    if (includeHistory) {
      final historyRaw = prefs.getStringList('alarm_history') ?? [];
      backup['history'] = historyRaw.map((s) => jsonDecode(s)).toList();
    }

    return jsonEncode(backup);
  }

  static Future<bool> import(String jsonString) async {
    try {
      final data = jsonDecode(jsonString) as Map<String, dynamic>;
      final config = data['config'] as Map<String, dynamic>? ?? {};

      final prefs = await SharedPreferences.getInstance();
      final secure = const FlutterSecureStorage();

      if (config['url'] != null) await prefs.setString('ha_url', config['url']);
      if (config['token'] != null) await secure.write(key: 'ha_token', value: config['token']);
      if (config['entity'] != null) await prefs.setString('ha_entity', config['entity']);
      if (config['code'] != null) await secure.write(key: 'ha_code', value: config['code']);
      if (config['updateUrl'] != null) await prefs.setString('ha_updateUrl', config['updateUrl']);
      if (config['timeout'] != null) await prefs.setInt('ha_timeout', config['timeout']);
      if (config['theme'] != null) await prefs.setString('app_theme', config['theme']);

      if (data['history'] is List) {
        final history = (data['history'] as List)
            .map((e) => jsonEncode(e))
            .toList()
            .cast<String>();
        await prefs.setStringList('alarm_history', history);
      }

      if (prefs.containsKey('ha_token')) await prefs.remove('ha_token');
      if (prefs.containsKey('ha_code'))  await prefs.remove('ha_code');

      return true;
    } catch (e) {
      debugPrint('[Backup] Import error: $e');
      return false;
    }
  }

  static Future<String?> saveBackupFile({bool includeHistory = false}) async {
    try {
      final backup = await export(includeHistory: includeHistory);

      final downloadsPath = '/storage/emulated/0/Download';
      final backupDir = Directory('$downloadsPath/Alarma Casa Backups');

      if (!await backupDir.exists()) {
        await backupDir.create(recursive: true);
      }

      final filename = _generateFilename();
      final file = File('${backupDir.path}/$filename');
      await file.writeAsString(backup);
      return file.path;
    } catch (e) {
      debugPrint('[Backup] Save error: $e');
      return null;
    }
  }

  static Future<bool> loadBackupFile(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) return false;
      final content = await file.readAsString();
      return await import(content);
    } catch (e) {
      debugPrint('[Backup] Load error: $e');
      return false;
    }
  }
}

// ─── Servicio de Widget Android ───────────────────────────────
class WidgetService {
  static const _channel = MethodChannel('com.homeassistant.ha_alarm/widget');

  static const _labels = {
    AlarmState.disarmed:   'Desarmada',
    AlarmState.armedAway:  'Armada',
    AlarmState.armedHome:  'Armada (Casa)',
    AlarmState.armedNight: 'Armada (Noche)',
    AlarmState.arming:     'Armando...',
    AlarmState.pending:    'Entrada...',
    AlarmState.triggered:  '¡ALARMA!',
    AlarmState.unknown:    'Sin conexión',
  };

  static Future<void> update(AlarmState state) async {
    try {
      final now  = DateTime.now();
      final hora = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('widget_state_label', _labels[state] ?? '—');
      await prefs.setString('widget_state_key',   state.name);
      await prefs.setString('widget_updated_at',  hora);

      try {
        await _channel.invokeMethod('updateWidget');
      } catch (channelError) {
        debugPrint('[Widget] Channel error: $channelError');
      }
    } catch (e) {
      debugPrint('[Widget] Update error: $e');
    }
  }

  static Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      prefs.setString('widget_state_label', _labels[AlarmState.unknown] ?? 'Sin conexión');
      prefs.setString('widget_state_key',   'unknown');
      prefs.setString('widget_updated_at',  '');
    } catch (e) {
      debugPrint('[Widget] Init error: $e');
    }
  }
}
