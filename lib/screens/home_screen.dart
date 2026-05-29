import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../constants.dart';
import '../models.dart';
import '../services.dart';
import '../widgets.dart';
import 'config_screen.dart';
import 'history_screen.dart';
import 'about_screen.dart';

// Referencia global a las notificaciones locales (inicializado en main.dart)
final flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  Config?         _config;
  AlarmStateData? _stateData;
  DateTime?       _lastFetch;
  bool            _configLoaded = false;
  bool            _loading      = true;
  bool            _actionBusy   = false;
  bool            _refreshing   = false;
  String?         _error;
  Timer?          _pollTimer;
  Timer?          _countdownTimer;
  Timer?          _lastFetchTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      Future.delayed(const Duration(milliseconds: 800), _refresh);
    }
  }

  Future<void> _init() async {
    _config = await Config.load();
    setState(() => _configLoaded = true);
    if (_config!.isValid) {
      _refresh();
      _pollTimer = Timer.periodic(
          const Duration(seconds: kPollSeconds), (_) => _refresh());
      _lastFetchTimer = Timer.periodic(
          const Duration(seconds: 1), (_) { if (mounted) setState(() {}); });
    } else {
      setState(() => _loading = false);
    }
    if (_config!.updateUrl.isNotEmpty) _checkUpdate();
    _initNotifications();
  }

  Future<void> _initNotifications() async {
    try {
      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission(alert: true, badge: true, sound: true);

      final token = await messaging.getToken();
      if (token != null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('fcm_token', token);
      }

      messaging.onTokenRefresh.listen((newToken) async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('fcm_token', newToken);
      });

      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        final n = message.notification;
        if (n == null) return;
        flutterLocalNotificationsPlugin.show(
          message.hashCode,
          n.title ?? 'Alarma Casa HA',
          n.body,
          const NotificationDetails(
            android: AndroidNotificationDetails(
              'ha_alarm_channel', 'Alarma Casa HA',
              channelDescription: 'Notificaciones de estado de la alarma',
              importance: Importance.max,
              priority: Priority.high,
              icon: '@mipmap/ic_launcher',
            ),
          ),
        );
      });
    } catch (_) {}
  }

  Future<void> _refresh() async {
    if (_config == null || !_config!.isValid || _refreshing) return;
    _refreshing = true;
    try {
      int delaySeconds = 1;
      for (int attempt = 1; attempt <= kMaxRetries; attempt++) {
        try {
          final data = await HaService(_config!).getState();
          if (mounted) {
            if (_stateData?.state != data.state) {
              HistoryService.add(data.state);
            }
            setState(() {
              _stateData = data;
              _lastFetch = DateTime.now();
              _loading   = false;
              _error     = null;
            });
            _updateCountdownTimer(data);
          }
          return;
        } catch (_) {
          if (attempt == kMaxRetries) {
            if (mounted) setState(() { _error = 'Sin conexión'; _loading = false; });
          } else {
            await Future.delayed(Duration(seconds: delaySeconds));
            delaySeconds *= 2;
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
        if (mounted) setState(() {});
        if (_stateData?.remaining == 0) _countdownTimer?.cancel();
      });
    }
  }

  Future<void> _checkUpdate() async {
    final info = await UpdateService.check(_config!.updateUrl);
    if (info != null && mounted) _showUpdateDialog(info);
  }

  void _showUpdateDialog(UpdateInfo info) {
    double  progress   = 0;
    bool    downloading = false;
    String? dlError;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Dialog(
          backgroundColor: kSurface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.system_update_rounded, color: kBlue, size: 44),
              const SizedBox(height: 14),
              const Text('Actualización disponible',
                  style: TextStyle(color: kText, fontWeight: FontWeight.bold, fontSize: 17)),
              const SizedBox(height: 8),
              Text('Versión ${info.version}',
                  style: const TextStyle(color: kSubtext, fontSize: 14)),
              const SizedBox(height: 20),
              if (downloading) ...[
                LinearProgressIndicator(
                    value: progress,
                    backgroundColor: kBg,
                    color: kBlue,
                    borderRadius: BorderRadius.circular(4)),
                const SizedBox(height: 8),
                Text('${(progress * 100).toInt()}%',
                    style: const TextStyle(color: kSubtext, fontSize: 13)),
              ],
              if (dlError != null)
                Text(dlError!, style: const TextStyle(color: kRed, fontSize: 12)),
              const SizedBox(height: 20),
              Row(children: [
                Expanded(child: OutlinedButton(
                  onPressed: downloading ? null : () async {
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setString('last_update_notified', info.version);
                    if (ctx.mounted) Navigator.pop(ctx);
                  },
                  style: OutlinedButton.styleFrom(
                      foregroundColor: kSubtext,
                      side: const BorderSide(color: kSubtext),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12))),
                  child: const Text('Ahora no'),
                )),
                const SizedBox(width: 14),
                Expanded(child: ElevatedButton(
                  onPressed: downloading ? null : () async {
                    setS(() { downloading = true; dlError = null; });
                    try {
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setString('last_update_notified', info.version);
                      await UpdateService.downloadAndInstall(
                          info.apkUrl, (p) => setS(() => progress = p));
                      if (ctx.mounted) Navigator.pop(ctx);
                    } catch (e) {
                      setS(() { downloading = false; dlError = 'Error: $e'; });
                    }
                  },
                  style: ElevatedButton.styleFrom(
                      backgroundColor: kBlue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      elevation: 0),
                  child: const Text('Actualizar',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                )),
              ]),
            ]),
          ),
        ),
      ),
    );
  }

  Future<void> _execute(String action) async {
    setState(() => _actionBusy = true);
    try {
      if (action == 'disarm') await HaService(_config!).disarm();
      if (action == 'arm')    await HaService(_config!).armAway();
      await FeedbackService.confirm();
      await Future.delayed(const Duration(milliseconds: 800));
      await _refresh();
    } catch (e) {
      await FeedbackService.error();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('❌ Error al ejecutar la acción'),
            backgroundColor: kRed));
    } finally {
      if (mounted) setState(() => _actionBusy = false);
    }
  }

  void _confirm(String action, String label, Color color, IconData icon) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        backgroundColor: kSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                  color: color.withOpacity(0.15), shape: BoxShape.circle),
              child: Icon(icon, color: color, size: 40)),
            const SizedBox(height: 18),
            const Text('¿Confirmar acción?',
                style: TextStyle(color: kText, fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('Se va a aplicar: $label',
                textAlign: TextAlign.center,
                style: const TextStyle(color: kSubtext, fontSize: 14)),
            const SizedBox(height: 28),
            Row(children: [
              Expanded(child: OutlinedButton(
                onPressed: () => Navigator.pop(ctx),
                style: OutlinedButton.styleFrom(
                    foregroundColor: kSubtext,
                    side: const BorderSide(color: kSubtext),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12))),
                child: const Text('Cancelar'),
              )),
              const SizedBox(width: 14),
              Expanded(child: ElevatedButton(
                onPressed: () { Navigator.pop(ctx); _execute(action); },
                style: ElevatedButton.styleFrom(
                    backgroundColor: color.withOpacity(0.2),
                    foregroundColor: color,
                    side: BorderSide(color: color),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    elevation: 0),
                child: Text(label,
                    style: const TextStyle(fontWeight: FontWeight.bold)),
              )),
            ]),
          ]),
        ),
      ),
    );
  }

  Future<void> _goConfig() async {
    _pollTimer?.cancel();
    _countdownTimer?.cancel();
    _lastFetchTimer?.cancel();
    await Navigator.push(
        context, MaterialPageRoute(builder: (_) => const ConfigScreen()));
    _config = null;
    setState(() {
      _loading = true; _configLoaded = false;
      _stateData = null; _error = null; _lastFetch = null;
    });
    _init();
  }

  String _lastFetchLabel() {
    if (_lastFetch == null) return '';
    final secs = DateTime.now().difference(_lastFetch!).inSeconds;
    if (secs < 5)  return 'Ahora mismo';
    if (secs < 60) return 'Hace ${secs}s';
    final mins = secs ~/ 60;
    return 'Hace ${mins}min';
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pollTimer?.cancel();
    _countdownTimer?.cancel();
    _lastFetchTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark       = Theme.of(context).brightness == Brightness.dark;
    final textColor    = isDark ? kText    : const Color(0xFF0f172a);
    final subtextColor = isDark ? kSubtext : const Color(0xFF64748b);

    final data  = _stateData;
    final state = data?.state ?? AlarmState.unknown;
    final info  = stateInfo[state]!;
    final color = info['color'] as Color;
    final icon  = info['icon'] as IconData;
    final label = info['label'] as String;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: isDark ? kBg : const Color(0xFFf1f5f9),
        elevation: 0,
        title: Text('🏡 Alarma Casa',
            style: TextStyle(
                color: textColor, fontWeight: FontWeight.bold, fontSize: 18)),
        actions: [
          IconButton(
              icon: Icon(Icons.history_rounded, color: subtextColor),
              onPressed: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const HistoryScreen()))),
          IconButton(
              icon: Icon(Icons.info_outline_rounded, color: subtextColor),
              onPressed: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const AboutScreen()))),
          IconButton(
              icon: Icon(Icons.settings_outlined, color: subtextColor),
              onPressed: _goConfig),
        ],
      ),
      body: !_configLoaded
          ? const Center(
              child: CircularProgressIndicator(strokeWidth: 2, color: kBlue))
          : !(_config?.isValid ?? false)
              ? NoConfigWidget(onConfig: _goConfig)
              : Padding(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 30),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [

                      // ── Tarjeta de estado ──
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 400),
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                            vertical: 28, horizontal: 20),
                        decoration: BoxDecoration(
                          color: color.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                              color: color.withOpacity(0.35), width: 1.5),
                          boxShadow: [BoxShadow(
                              color: color.withOpacity(0.12), blurRadius: 20)],
                        ),
                        child: Column(children: [
                          Icon(icon, color: color, size: 52),
                          const SizedBox(height: 12),
                          Text('Estado actual',
                              style: TextStyle(
                                  color: subtextColor,
                                  fontSize: 12,
                                  letterSpacing: 1.2)),
                          const SizedBox(height: 6),
                          if (_loading && data == null)
                            const CircularProgressIndicator(strokeWidth: 2)
                          else if (_error != null && data == null)
                            Text(_error!,
                                style: const TextStyle(
                                    color: kRed,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 18))
                          else
                            Text(label,
                                style: TextStyle(
                                    color: color,
                                    fontSize: 22,
                                    fontWeight: FontWeight.bold)),

                          if (_lastFetch != null) ...[
                            const SizedBox(height: 6),
                            Text(_lastFetchLabel(),
                                style: TextStyle(
                                    color: subtextColor, fontSize: 11)),
                          ],

                          if (data != null && data.hasCountdown) ...[
                            const SizedBox(height: 14),
                            CountdownBar(data: data, color: color),
                          ],

                          if (data != null &&
                              data.openSensors.isNotEmpty &&
                              (state == AlarmState.arming ||
                                  state == AlarmState.triggered ||
                                  state == AlarmState.disarmed)) ...[
                            const SizedBox(height: 14),
                            OpenSensorsWarning(sensors: data.openSensors),
                          ],
                        ]),
                      ),

                      const SizedBox(height: 32),

                      // ── Botones ──
                      Row(children: [
                        Expanded(child: ActionButton(
                          label: 'Desarmar',
                          icon: Icons.lock_open_rounded,
                          color: kGreen,
                          active: state == AlarmState.disarmed,
                          busy: _actionBusy,
                          onTap: () => _confirm('disarm', 'Desarmar',
                              kGreen, Icons.lock_open_rounded),
                        )),
                        const SizedBox(width: 16),
                        Expanded(child: ActionButton(
                          label: 'Armar',
                          icon: Icons.lock_rounded,
                          color: kRed,
                          active: state == AlarmState.armedAway,
                          busy: _actionBusy,
                          onTap: () => _confirm('arm', 'Armar',
                              kRed, Icons.lock_rounded),
                        )),
                      ]),

                      const SizedBox(height: 24),
                      TextButton.icon(
                        onPressed: (_loading || _actionBusy) ? null : _refresh,
                        icon: Icon(Icons.refresh_rounded,
                            size: 16, color: subtextColor),
                        label: Text('Actualizar estado',
                            style: TextStyle(color: subtextColor, fontSize: 12)),
                      ),
                    ],
                  ),
                ),
    );
  }
}
