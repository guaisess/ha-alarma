import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
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
  String?         get error       => _error;

  Future<void> init() async {
    _config = await Config.load();
    if (_config!.isValid) {
      _stateData = await StateCache.load();
      _loading = false;
      notifyListeners();

      _ws = HaWebSocketService(
        onStateChanged: _onWsState,
        onConnectionChanged: (c) {
          _wsConnected = c;
          notifyListeners();
          if (c) {
            _pollTimer?.cancel();
            _startPolling(30);
          }
        },
      );

      await _refresh();
      _initWs();
      _startPolling();
      _lastFetchTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (_stateData != null) notifyListeners();
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
      await _ws?.connect(_config!.url, _config!.token, _config!.entityId);
    } catch (e) {
      debugPrint('[Controller] WS init error: $e');
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
    WidgetService.update(data.state);
    StateCache.save(data);
    _pollTimer?.cancel();
    _startPolling(30);
    notifyListeners();
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
          WidgetService.update(data.state);
          StateCache.save(data);
          notifyListeners();
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
      if (action == 'disarm') await HaService(_config!).disarm();
      if (action == 'arm')    await HaService(_config!).armAway();
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
    _initWs();
    if (_config!.isValid) {
      await _refresh();
      _pollTimer?.cancel();
      _startPolling();
    }
  }

  Future<void> _checkUpdate() async {
    try {
      final info = await UpdateService.check(_config!.updateUrl);
      if (info != null) _pendingUpdate = info;
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
