import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../constants.dart';
import '../models.dart';
import '../services.dart';
import '../controller.dart';
import '../widgets.dart';
import 'config_screen.dart';
import 'history_screen.dart';
import 'about_screen.dart';

final flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final _controller = AlarmController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller.addListener(_onChanged);
    _controller.init();
    _initNotifications();
  }

  void _onChanged() {
    if (mounted) setState(() {});
    if (_controller.pendingUpdate != null && mounted) {
      _showUpdateDialog(_controller.pendingUpdate!);
      _controller.clearPendingUpdate();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      Future.delayed(const Duration(milliseconds: 800), _controller.refresh);
    }
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
    } catch (e) {
      debugPrint('[Home] Notification init error: $e');
    }
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

  Future<void> _goConfig() async {
    final changed = await Navigator.push<bool>(
        context, MaterialPageRoute(builder: (_) => const ConfigScreen()));
    if (changed == true) await _controller.reloadConfig();
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
                onPressed: () {
                  Navigator.pop(ctx);
                  _controller.execute(action).catchError((e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('❌ Error al ejecutar la acción'),
                            backgroundColor: kRed));
                    }
                  });
                },
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

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.removeListener(_onChanged);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark       = Theme.of(context).brightness == Brightness.dark;
    final textColor    = isDark ? kText    : const Color(0xFF0f172a);
    final subtextColor = isDark ? kSubtext : const Color(0xFF64748b);

    final c     = _controller;
    final data  = c.stateData;
    final state = data?.state ?? AlarmState.unknown;
    final info  = stateInfo[state]!;
    final color = info['color'] as Color;
    final icon  = info['icon'] as IconData;
    final label = info['label'] as String;
    final isLoading = c.loading && data == null;
    final hasError  = c.error != null && data == null;

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
      body: c.config == null
          ? const Center(
              child: CircularProgressIndicator(strokeWidth: 2, color: kBlue))
          : !(c.config?.isValid ?? false)
              ? NoConfigWidget(onConfig: _goConfig)
              : RefreshIndicator(
                  onRefresh: c.refresh,
                  color: kBlue,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(20, 10, 20, 30),
                    children: [
                      const SizedBox(height: 60),
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
                          if (isLoading)
                            const CircularProgressIndicator(strokeWidth: 2)
                          else if (hasError)
                            Text(c.error!,
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
                          if (c.lastFetch != null) ...[
                            const SizedBox(height: 6),
                            Text(c.lastFetchLabel(),
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
                      Row(children: [
                        Expanded(child: ActionButton(
                          label: 'Desarmar',
                          icon: Icons.lock_open_rounded,
                          color: kGreen,
                          active: state == AlarmState.disarmed,
                          busy: c.actionBusy,
                          onTap: () => _confirm('disarm', 'Desarmar',
                              kGreen, Icons.lock_open_rounded),
                        )),
                        const SizedBox(width: 16),
                        Expanded(child: ActionButton(
                          label: 'Armar',
                          icon: Icons.lock_rounded,
                          color: kRed,
                          active: state == AlarmState.armedAway,
                          busy: c.actionBusy,
                          onTap: () => _confirm('arm', 'Armar',
                              kRed, Icons.lock_rounded),
                        )),
                      ]),
                      if (c.showArmModes && state == AlarmState.disarmed) ...[
                        const SizedBox(height: 12),
                        _ArmModesRow(controller: c, onConfirm: _confirm),
                      ],
                      const SizedBox(height: 24),
                      Center(
                        child: TextButton.icon(
                          onPressed: (c.loading || c.actionBusy) ? null : c.refresh,
                          icon: Icon(Icons.refresh_rounded,
                              size: 16, color: subtextColor),
                          label: Text('Actualizar estado',
                              style: TextStyle(color: subtextColor, fontSize: 12)),
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }
}

class _ArmModesRow extends StatelessWidget {
  final AlarmController controller;
  final void Function(String action, String label, Color color, IconData icon) onConfirm;

  const _ArmModesRow({required this.controller, required this.onConfirm});

  @override
  Widget build(BuildContext context) {
    final modes = [
      ('arm_home',     'Armar (Casa)',     kOrange, Icons.home_rounded),
      ('arm_night',    'Armar (Noche)',    kPurple, Icons.bedtime_rounded),
      ('arm_vacation', 'Armar (Vac.)',     kBlue,   Icons.flight_rounded),
    ];

    return Row(children: [
      for (final m in modes) ...[
        if (m != modes.first) const SizedBox(width: 10),
        Expanded(child: _ArmModeChip(
          label: m.$2,
          icon: m.$4,
          color: m.$3,
          busy: controller.actionBusy,
          onTap: () => onConfirm(m.$1, m.$2, m.$3, m.$4),
        )),
      ],
    ]);
  }
}

class _ArmModeChip extends StatelessWidget {
  final String  label;
  final IconData icon;
  final Color   color;
  final bool    busy;
  final VoidCallback onTap;

  const _ArmModeChip({
    required this.label,
    required this.icon,
    required this.color,
    required this.busy,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: busy ? null : onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withOpacity(0.3), width: 1),
        ),
        child: Column(children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 4),
          Text(label,
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: isDark ? kText : const Color(0xFF0f172a),
                  fontSize: 10,
                  fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }
}
