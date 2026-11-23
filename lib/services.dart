// Versión 2026.11.12
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:vibration/vibration.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'constants.dart';
import 'models.dart';

// Versión 2026.11.12
// ─── Parseo común de un objeto "state" de HA (REST y WebSocket) ───
AlarmStateData parseStateData(Map<String, dynamic> data) {
  final attrs = data['attributes'] as Map<String, dynamic>? ?? {};
  final lastChanged =
      DateTime.tryParse(data['last_changed'] as String? ?? '')?.toLocal() ?? DateTime.now();

  int? delay;
  if (attrs.containsKey('delay')) delay = (attrs['delay'] as num?)?.toInt();

  return AlarmStateData(
    state: parseState(data['state'] as String? ?? 'unknown'),
    lastChanged: lastChanged, delay: delay,
    openSensors: sensorsFromAttr(attrs['open_sensors']),
  );
}

/// Alarmo manda los sensores como mapa {entidad: estado} o como lista
List<String> sensorsFromAttr(dynamic raw) {
  if (raw is Map)  return raw.keys.map((k) => k.toString()).toList();
  if (raw is List) return raw.map((e) => e.toString()).toList();
  return const [];
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

  /// Estado crudo de una entidad; null si no existe o falla (las zonas son opcionales)
  Future<Map<String, dynamic>?> _getRaw(String entityId) async {
    try {
      final res = await http.get(Uri.parse('${config.url}/api/states/$entityId'),
          headers: _headers).timeout(_timeout);
      if (res.statusCode != 200) return null;
      return jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  /// Estados completos (state + attributes) de las zonas y sus marcas de robot
  Future<Map<String, Map<String, dynamic>>> getZoneStates() async {
    final ids = [
      for (final z in kZones) ...[z.entityId, if (z.autoFlagEntity != null) z.autoFlagEntity!],
    ];
    final raws = await Future.wait(ids.map(_getRaw));
    return {
      for (var i = 0; i < ids.length; i++)
        if (raws[i] != null) ids[i]: raws[i]!,
    };
  }

  /// Nombres legibles de sensores; '' si no se pudo obtener (se evita repetir la consulta)
  Future<Map<String, String>> getFriendlyNames(List<String> ids) async {
    final raws = await Future.wait(ids.map(_getRaw));
    return {
      for (var i = 0; i < ids.length; i++)
        ids[i]: ((raws[i]?['attributes'] as Map?)?['friendly_name'] as String?) ?? '',
    };
  }

  /// Avisa a HA del token FCM de este móvil (evento que registra una automatización)
  Future<void> registerFcmToken(String name, String token) async {
    final res = await http.post(
      Uri.parse('${config.url}/api/events/$kFcmEvent'),
      headers: _headers,
      body: jsonEncode({'nombre': name, 'token': token}),
    ).timeout(_timeout);
    if (res.statusCode != 200 && res.statusCode != 201) {
      throw Exception('HTTP ${res.statusCode}');
    }
  }

  /// Arma una zona concreta (solo para zonas que no se rearmaron solas)
  Future<void> armZone(String entityId) => _call('alarm_arm_away',
      config.code.isNotEmpty ? {'code': config.code} : {}, entityId: entityId);

  Future<void> disarm()  => _call('alarm_disarm',  {'code': config.code});
  Future<void> armAway() => _call('alarm_arm_away', {});
  Future<void> armHome() => _call('alarm_arm_home', {});
  Future<void> armNight() => _call('alarm_arm_night', {});
  Future<void> armCustomBypass() => _call('alarm_arm_custom_bypass', {});

  Future<void> _call(String service, Map<String, dynamic> extra, {String? entityId}) async {
    final uri  = Uri.parse('${config.url}/api/services/alarm_control_panel/$service');
    final body = jsonEncode({'entity_id': entityId ?? config.entityId, ...extra});
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
  String? _url, _token;
  List<String> _entityIds = const [];

  final void Function(String entityId, Map<String, dynamic> newState) onEntityChanged;
  final void Function(bool connected) onConnectionChanged;
  final void Function()? onAuthError;

  HaWebSocketService({
    required this.onEntityChanged,
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
  Future<void> connect(String url, String token, List<String> entityIds) async {
    await disconnect();
    _url = url;
    _token = token;
    _entityIds = entityIds;
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
      if (_entityIds.isEmpty) return;

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
          'trigger': {'platform': 'state', 'entity_id': _entityIds},
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
        final id = newState['entity_id'] as String?;
        if (id != null) onEntityChanged(id, newState);
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

// ─── Registro automático del token FCM en HA ──────────────────
class FcmRegistrationService {
  static const _keyDone = 'fcm_registered'; // "nombre|token" ya enviado

  /// Envía el token a HA si hay nombre de dispositivo y no se envió ya.
  /// Se llama al obtener/renovar el token y al guardar la configuración.
  static Future<void> sync() async {
    try {
      final cfg   = await Config.load();
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('fcm_token') ?? '';
      if (!cfg.isValid || cfg.deviceName.isEmpty || token.isEmpty) return;
      final marca = '${cfg.deviceName}|$token';
      if (prefs.getString(_keyDone) == marca) return;
      await HaService(cfg).registerFcmToken(cfg.deviceName, token);
      await prefs.setString(_keyDone, marca);
    } catch (e) {
      debugPrint('[FCM] Registro en HA fallido (se reintentará): $e');
    }
  }
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
        'timeout':   prefs.getInt('ha_timeout')      ?? kTimeoutSeconds,
        'showArmModes': prefs.getBool('show_arm_modes') ?? false,
        'deviceName':   prefs.getString('device_name') ?? '',
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
      if (config['timeout'] != null) await prefs.setInt('ha_timeout', (config['timeout'] as num).toInt());
      if (config['deviceName'] is String) await prefs.setString('device_name', config['deviceName']);
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
  static const _channel = MethodChannel('es.fernandezbadia.alarmacasa/widget');

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

  /// Acción pedida desde los botones del widget ('arm' / 'disarm') con la app
  /// cerrada; devuelve null si no hay ninguna.
  static Future<String?> launchAction() async {
    try {
      return await _channel.invokeMethod<String>('getLaunchAction');
    } catch (e) {
      debugPrint('[Widget] launchAction error: $e');
      return null;
    }
  }

  /// Escucha las acciones del widget con la app ya abierta.
  static void listenActions(void Function(String action) onAction) {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'widgetAction') onAction(call.arguments as String);
    });
  }

  static Future<void> update(AlarmState state, {String zones = ''}) async {
    try {
      final now  = DateTime.now();
      final hora = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('widget_state_label', _labels[state] ?? '—');
      await prefs.setString('widget_state_key',   state.name);
      await prefs.setString('widget_updated_at',  hora);
      await prefs.setString('widget_zones',       zones);

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
