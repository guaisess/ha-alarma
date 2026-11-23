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
import 'constants.dart';
import 'models.dart';

// Versión 2026.11.1
// ─── Parseo común de un objeto "state" de HA (REST y WebSocket) ───
AlarmStateData parseStateData(Map<String, dynamic> data) {
  final attrs = data['attributes'] as Map<String, dynamic>? ?? {};
  final lastChanged =
      DateTime.tryParse(data['last_changed'] as String? ?? '')?.toLocal() ?? DateTime.now();

  int? delay;
  if (attrs.containsKey('delay')) delay = (attrs['delay'] as num?)?.toInt();

  List<String> openSensors = [];
  final raw = attrs['open_sensors'];
  if (raw is Map)  openSensors = raw.keys.map((k) => k.toString()).toList();
  if (raw is List) openSensors = raw.map((e) => e.toString()).toList();

  return AlarmStateData(
    state: parseState(data['state'] as String? ?? 'unknown'),
    lastChanged: lastChanged, delay: delay, openSensors: openSensors,
  );
}

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

    return parseStateData(jsonDecode(res.body) as Map<String, dynamic>);
  }

  Future<void> disarm()  => _call('alarm_disarm',  {'code': config.code});
  Future<void> armAway() => _call('alarm_arm_away', {});
  Future<void> armHome() => _call('alarm_arm_home', {});
  Future<void> armNight() => _call('alarm_arm_night', {});
  Future<void> armCustomBypass() => _call('alarm_arm_custom_bypass', {});

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
// Se suscribe con `subscribe_trigger` filtrando por la entidad en el
// servidor de HA, de modo que NO recibe todos los state_changed de la casa.
class HaWebSocketService {
  WebSocket? _ws;
  StreamSubscription? _sub;
  Timer? _reconnectTimer;
  bool _authenticated = false;
  bool _subscribed = false;
  bool _authFailed = false;
  int _msgId = 0;
  int _reconnectAttempts = 0;
  String? _url, _token, _entityId;

  final void Function(AlarmStateData data) onStateChanged;
  final void Function(bool connected) onConnectionChanged;
  final void Function()? onAuthError;

  HaWebSocketService({
    required this.onStateChanged,
    required this.onConnectionChanged,
    this.onAuthError,
  });

  String _toWsUrl(String httpUrl) {
    final wsUrl = httpUrl
        .replaceFirst('https://', 'wss://')
        .replaceFirst('http://', 'ws://');
    return '${wsUrl.replaceAll(RegExp(r'/$'), '')}/api/websocket';
  }

  /// Conexión pedida por el usuario/controlador: reinicia el backoff.
  Future<void> connect(String url, String token, String entityId) async {
    await disconnect();
    _url = url;
    _token = token;
    _entityId = entityId;
    _authFailed = false;
    _reconnectAttempts = 0;
    await _open();
  }

  /// Abre el socket; NO toca el contador de reintentos (antes se reseteaba
  /// aquí y la reconexión quedaba fija en 1 s).
  Future<void> _open() async {
    final url = _url;
    if (url == null || _authFailed) return;
    onConnectionChanged(false);
    try {
      _ws = await WebSocket.connect(_toWsUrl(url))
          .timeout(const Duration(seconds: kWsConnectTimeoutSeconds));
      _sub = _ws!.listen(
        _handleMessage,
        onDone: _onDisconnected,
        onError: (e) {
          debugPrint('[HA WS] Error: $e');
          _onDisconnected();
        },
        cancelOnError: true,
      );
    } catch (e) {
      debugPrint('[HA WS] Connection failed: $e');
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
        // Filtro en servidor: solo cambios de estado de nuestra entidad
        _ws?.add(jsonEncode({
          'id': ++_msgId,
          'type': 'subscribe_trigger',
          'trigger': {'platform': 'state', 'entity_id': entityId},
        }));
        return;
      }

      if (!_authenticated && type == 'auth_invalid') {
        debugPrint('[HA WS] Auth invalid');
        _authFailed = true; // token incorrecto: reintentar no sirve
        _reconnectTimer?.cancel();
        onAuthError?.call();
        return;
      }

      if (!_subscribed && type == 'result') {
        if (msg['success'] == true) {
          _subscribed = true;
          _reconnectAttempts = 0;
          onConnectionChanged(true);
        } else {
          debugPrint('[HA WS] Suscripción rechazada: ${msg['error']}');
        }
        return;
      }

      if (_subscribed && type == 'event') {
        final trigger = (msg['event'] as Map<String, dynamic>?)?['variables']
            ?['trigger'] as Map<String, dynamic>?;
        final newState = trigger?['to_state'] as Map<String, dynamic>?;
        if (newState == null) return;
        onStateChanged(parseStateData(newState));
      }
    } catch (e) {
      debugPrint('[HA WS] Parse error: $e');
    }
  }

  void _scheduleReconnect() {
    if (_url == null || _authFailed) return;
    // onError + onDone pueden llegar seguidos: un solo reintento pendiente
    if (_reconnectTimer?.isActive ?? false) return;
    final seconds = kWsBackoff[_reconnectAttempts < kWsBackoff.length
        ? _reconnectAttempts : kWsBackoff.length - 1];
    _reconnectAttempts++;
    debugPrint('[HA WS] Reconnect in ${seconds}s (attempt $_reconnectAttempts)');
    _reconnectTimer = Timer(Duration(seconds: seconds), () async {
      await _cleanSocket();
      await _open();
    });
  }

  Future<void> _cleanSocket() async {
    await _sub?.cancel();
    _sub = null;
    await _ws?.close();
    _ws = null;
    _authenticated = false;
    _subscribed = false;
  }

  Future<void> disconnect() async {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    await _cleanSocket();
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
    if (await Vibration.hasVibrator()) {
      Vibration.vibrate(duration: 80);
    }
  }

  static Future<void> error() async {
    if (await Vibration.hasVibrator()) {
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
          .timeout(const Duration(seconds: kUpdateCheckTimeoutSeconds));
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
      'version': kBackupVersion,
      'timestamp': DateTime.now().toIso8601String(),
      'config': {
        'url':       prefs.getString('ha_url')       ?? '',
        'token':     await secure.read(key: 'ha_token') ?? prefs.getString('ha_token') ?? '',
        'entity':    prefs.getString('ha_entity')    ?? '',
        'code':      await secure.read(key: 'ha_code') ?? prefs.getString('ha_code') ?? '',
        'updateUrl': prefs.getString('ha_updateUrl') ?? '',
        'timeout':   prefs.getInt('ha_timeout')      ?? kTimeoutSeconds,
        'showArmModes': prefs.getBool('show_arm_modes') ?? false,
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

      if (config['url'] != null) await prefs.setString('ha_url', config['url'].toString());
      if (config['token'] != null) await secure.write(key: 'ha_token', value: config['token'].toString());
      if (config['entity'] != null) await prefs.setString('ha_entity', config['entity'].toString());
      if (config['code'] != null) await secure.write(key: 'ha_code', value: config['code'].toString());
      if (config['updateUrl'] != null) await prefs.setString('ha_updateUrl', config['updateUrl'].toString());
      if (config['timeout'] != null) await prefs.setInt('ha_timeout', (config['timeout'] as num).toInt());
      if (config['showArmModes'] is bool) await prefs.setBool('show_arm_modes', config['showArmModes']);
      if (config['theme'] != null) await prefs.setString('app_theme', config['theme'].toString());

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

      Directory backupDir = Directory(kBackupDir);
      try {
        if (!await backupDir.exists()) await backupDir.create(recursive: true);
      } catch (_) {
        // Sin permiso sobre Descargas (Android 11+): usar carpeta propia de la app
        final ext = await getExternalStorageDirectory();
        backupDir = Directory('${ext!.path}/backups');
        if (!await backupDir.exists()) await backupDir.create(recursive: true);
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
    AlarmState.armedCustomBypass: 'Armada (Vacaciones)',
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
