// Versión 2026.11.5
import 'dart:async';
import 'package:flutter/material.dart';
import 'constants.dart';
import 'models.dart';
import 'services.dart';

class AlarmController extends ChangeNotifier {
  Config?          _config;
  AlarmStateData?  _stateData;
  DateTime?        _lastFetch;
  bool             _loading        = true;
  bool             _refreshing     = false;
  bool             _actionBusy     = false;
  bool             _wsConnected    = false;
  String?          _error;
  Map<String, Map<String, dynamic>> _zoneRaw = {}; // estado+atributos de zonas y marcas de robot
  Map<String, String> _sensorNames = {};            // entidad -> nombre legible

  HaWebSocketService? _ws;
  Timer?  _pollTimer;
  Timer?  _countdownTimer;
  Timer?  _lastFetchTimer;

  // Getters
  Config?         get config      => _config;
  AlarmStateData? get stateData   => _stateData;
  DateTime?       get lastFetch   => _lastFetch;
  bool            get loading     => _loading;
  bool            get refreshing  => _refreshing;
  bool            get actionBusy  => _actionBusy;
  bool            get wsConnected => _wsConnected;
  bool            get showArmModes => _config?.showArmModes ?? false;
  String?         get error       => _error;

  /// Zonas conocidas (solo las que existen en HA)
  List<ZoneData> get zones => [
    for (final d in kZones)
      if (_zoneRaw.containsKey(d.entityId))
        ZoneData(
          def: d,
          state: parseState(_zoneRaw[d.entityId]!['state'] as String? ?? 'unknown'),
          autoDisarmed: d.autoFlagEntity != null &&
              _zoneRaw[d.autoFlagEntity]?['state'] == 'on',
          openSensors: sensorsFromAttr(_attrs(d.entityId)['open_sensors']),
          bypassedSensors: sensorsFromAttr(_attrs(d.entityId)['bypassed_sensors']),
        ),
  ];

  Map<String, dynamic> _attrs(String id) =>
      _zoneRaw[id]?['attributes'] as Map<String, dynamic>? ?? const {};

  /// Nombres legibles de sensores ya consultados
  Map<String, String> get sensorNames => _sensorNames;

  /// Anota en el historial los cambios de estado de una zona. Ignora la
  /// primera lectura (sin estado previo) para no llenarlo de ruido.
  void _registrarZona(String id, Map<String, dynamic>? antes, Map<String, dynamic> ahora) {
    final nuevo = ahora['state'] as String?;
    if (antes == null || nuevo == null || antes['state'] == nuevo) return;
    for (final d in kZones) {
      if (d.entityId == id) {
        HistoryService.add(parseState(nuevo), zone: d.label,
            robot: d.autoFlagEntity != null && _zoneRaw[d.autoFlagEntity]?['state'] == 'on');
      } else if (d.autoFlagEntity == id && nuevo == 'on') {
        HistoryService.markRobot(d.label);
      }
    }
  }

  /// Resumen para el widget: solo zonas que difieren de la maestra
  String _zonesSummary() {
    final master = _stateData?.state;
    return zones
        .where((z) => z.state != master && z.state != AlarmState.unknown)
        .map((z) => '${z.autoDisarmed ? '🤖 ' : ''}${z.def.short} '
            '${(stateInfo[z.state]!['label'] as String).toLowerCase()}')
        .join(' · ');
  }

  void _pushWidget() {
    final s = _stateData?.state;
    if (s != null) WidgetService.update(s, zones: _zonesSummary());
  }

  /// Consulta una sola vez el nombre de los sensores abiertos/anulados nuevos
  Future<void> _loadSensorNames() async {
    if (_config == null || !_config!.isValid) return;
    final ids = <String>{
      ...?_stateData?.openSensors,
      for (final z in zones) ...[...z.openSensors, ...z.bypassedSensors],
    }.where((i) => !_sensorNames.containsKey(i)).toList();
    if (ids.isEmpty) return;
    _sensorNames = {..._sensorNames, ...await HaService(_config!).getFriendlyNames(ids)};
    notifyListeners();
  }

  /// Zonas desarmadas por la automatización de robots
  List<ZoneData> get robotZones => zones.where((z) => z.autoDisarmed).toList();

  /// Crea el servicio WebSocket (una sola vez) con sus callbacks.
  void _ensureWs() {
    _ws ??= HaWebSocketService(
      onEntityChanged: _onWsEntity,
      onConnectionChanged: (c) {
        if (c == _wsConnected) return; // evita notificar y reprogramar sin cambio
        _wsConnected = c;
        notifyListeners();
        // Con WS conectado basta un sondeo lento; sin él, el rápido
        _startPolling(c ? kPollWsSeconds : kPollSeconds);
        if (c) _refresh(); // resincroniza lo perdido durante la desconexión
      },
      onAuthError: () {
        _error = 'Token no válido';
        notifyListeners();
      },
    );
  }

  Future<void> init() async {
    _config = await Config.load();
    if (_config!.isValid) {
      _stateData = await StateCache.load();
      _loading = false;
      notifyListeners();

      _ensureWs();
      await _refresh();
      _initWs();
      _startPolling();
      // Solo refresca la etiqueta "Hace Xs", no cada segundo
      _lastFetchTimer = Timer.periodic(
          const Duration(seconds: kLabelRefreshSeconds), (_) {
        if (_stateData != null && !(_stateData!.hasCountdown)) notifyListeners();
      });
    } else {
      _loading = false;
      notifyListeners();
    }
    if (_config!.updateUrl.isNotEmpty) _checkUpdate();
  }

  Future<void> _initWs() async {
    if (_config == null || !_config!.isValid) return;
    try {
      await _ws?.connect(_config!.url, _config!.token, _watchedEntities());
    } catch (e) {
      debugPrint('[Controller] WS init error: $e');
    }
  }

  /// Enruta un evento del WebSocket: alarma maestra o zona/marca de robot
  void _onWsEntity(String id, Map<String, dynamic> s) {
    if (id == _config?.entityId) {
      _onWsState(parseStateData(s));
      return;
    }
    final antes = _zoneRaw[id];
    _zoneRaw = {..._zoneRaw, id: s};
    _registrarZona(id, antes, s);
    notifyListeners();
    _pushWidget();
    _loadSensorNames();
  }

  /// Entidades que escucha el WebSocket (filtradas en el servidor)
  List<String> _watchedEntities() => [
    _config!.entityId,
    for (final z in kZones) ...[z.entityId, if (z.autoFlagEntity != null) z.autoFlagEntity!],
  ];

  Future<void> _refreshZones() async {
    if (_config == null || !_config!.isValid) return;
    final antes = _zoneRaw;
    _zoneRaw = await HaService(_config!).getZoneStates();
    for (final e in _zoneRaw.entries) {
      _registrarZona(e.key, antes[e.key], e.value);
    }
    notifyListeners();
    _pushWidget();
    _loadSensorNames();
  }

  /// Arma una zona que no se rearmó sola tras la limpieza del robot
  Future<void> armZone(ZoneDef zone) async {
    _actionBusy = true;
    notifyListeners();
    try {
      await HaService(_config!).armZone(zone.entityId);
      await FeedbackService.confirm();
      await Future.delayed(const Duration(milliseconds: 800));
      await _refreshZones();
    } catch (e) {
      await FeedbackService.error();
      rethrow;
    } finally {
      _actionBusy = false;
      notifyListeners();
    }
  }

  void _onWsState(AlarmStateData data) {
    if (_stateData?.state != data.state) {
      HistoryService.add(data.state);
    }
    _stateData = data;
    _lastFetch = DateTime.now();
    _error = null;
    _updateCountdownTimer(data);
    _pushWidget();
    StateCache.save(data);
    notifyListeners();
    _loadSensorNames();
  }

  void _startPolling([int? interval]) {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(
      Duration(seconds: interval ?? kPollSeconds),
      (_) => _refresh(),
    );
  }

  Future<void> refresh() => _refresh();

  Future<void> _refresh() async {
    if (_config == null || !_config!.isValid || _refreshing) return;
    _refreshing = true;
    try {
      const maxRetries = kMaxRetries;
      int delay = 1;
      for (int attempt = 1; attempt <= maxRetries; attempt++) {
        try {
          final data = await HaService(_config!).getState();
          if (_stateData?.state != data.state) {
            HistoryService.add(data.state);
          }
          _stateData = data;
          _lastFetch = DateTime.now();
          _loading   = false;
          _error     = null;
          _updateCountdownTimer(data);
          _pushWidget();
          StateCache.save(data);
          notifyListeners();
          _refreshZones();
          return;
        } catch (e) {
          if (attempt == maxRetries) {
            _error = 'Sin conexión';
            _loading = false;
            notifyListeners();
          } else {
            await Future.delayed(Duration(seconds: delay));
            delay *= 2;
          }
        }
      }
    } finally {
      _refreshing = false;
    }
  }

  void _updateCountdownTimer(AlarmStateData data) {
    _countdownTimer?.cancel();
    if (data.hasCountdown) {
      _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        notifyListeners();
        if (_stateData?.remaining == 0) _countdownTimer?.cancel();
      });
    }
  }

  Future<void> execute(String action) async {
    _actionBusy = true;
    notifyListeners();
    try {
      final svc = HaService(_config!);
      switch (action) {
        case 'disarm':        await svc.disarm();        break;
        case 'arm':           await svc.armAway();       break;
        case 'arm_home':      await svc.armHome();       break;
        case 'arm_night':     await svc.armNight();      break;
        case 'arm_vacation':  await svc.armCustomBypass(); break;
      }
      await FeedbackService.confirm();
      await Future.delayed(const Duration(milliseconds: 800));
      await _refresh();
    } catch (e) {
      await FeedbackService.error();
      rethrow;
    } finally {
      _actionBusy = false;
      notifyListeners();
    }
  }

  Future<void> reloadConfig() async {
    _config = await Config.load();
    await _ws?.disconnect();
    _wsConnected = false;
    if (_config!.isValid) {
      _ensureWs();
      _lastFetchTimer ??= Timer.periodic(
          const Duration(seconds: kLabelRefreshSeconds), (_) {
        if (_stateData != null && !(_stateData!.hasCountdown)) notifyListeners();
      });
      await _refresh();
      _initWs();
      _startPolling();
    } else {
      _pollTimer?.cancel();
    }
  }

  /// Comprueba si hay versión nueva (arranque y al volver a la app)
  Future<void> checkUpdate() async {
    if (_config == null || _config!.updateUrl.isEmpty) return;
    await _checkUpdate();
  }

  Future<void> _checkUpdate() async {
    try {
      final info = await UpdateService.check(_config!.updateUrl);
      if (info != null) {
        _pendingUpdate = info;
        notifyListeners(); // para que la pantalla muestre el aviso ya
      }
    } catch (e) {
      debugPrint('[Controller] Update check error: $e');
    }
  }

  UpdateInfo? _pendingUpdate;
  UpdateInfo? get pendingUpdate => _pendingUpdate;
  void clearPendingUpdate() => _pendingUpdate = null;

  String lastFetchLabel() {
    if (_lastFetch == null) return '';
    final secs = DateTime.now().difference(_lastFetch!).inSeconds;
    if (secs < 5)  return 'Ahora mismo';
    if (secs < 60) return 'Hace ${secs}s';
    final mins = secs ~/ 60;
    return 'Hace ${mins}min';
  }

  @override
  void dispose() {
    _ws?.disconnect();
    _pollTimer?.cancel();
    _countdownTimer?.cancel();
    _lastFetchTimer?.cancel();
    super.dispose();
  }
}
