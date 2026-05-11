import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:dio/dio.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const AlarmApp());
}

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

// ─── Estado de la alarma ──────────────────────────────────────
enum AlarmState { disarmed, armedAway, armedHome, armedNight, arming, pending, triggered, unknown }

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

const stateInfo = {
  AlarmState.disarmed:   {'label': 'Desarmada',    'color': kGreen,            'icon': Icons.lock_open_rounded},
  AlarmState.armedAway:  {'label': 'Armada',        'color': kRed,              'icon': Icons.lock_rounded},
  AlarmState.armedHome:  {'label': 'Armada (Casa)', 'color': kOrange,           'icon': Icons.home_rounded},
  AlarmState.armedNight: {'label': 'Armada (Noche)','color': Color(0xFFa855f7), 'icon': Icons.bedtime_rounded},
  AlarmState.arming:     {'label': 'Armando...',    'color': kOrange,           'icon': Icons.lock_clock_outlined},
  AlarmState.pending:    {'label': 'Entrada...',    'color': kYellow,           'icon': Icons.timer_outlined},
  AlarmState.triggered:  {'label': '¡ALARMA!',      'color': kRed,              'icon': Icons.warning_rounded},
  AlarmState.unknown:    {'label': 'Sin conexión',  'color': kSubtext,          'icon': Icons.help_outline_rounded},
};

// ─── Datos extendidos del estado ──────────────────────────────
class AlarmStateData {
  final AlarmState state;
  final DateTime lastChanged;
  final int? delay;
  final List<String> openSensors;

  AlarmStateData({
    required this.state,
    required this.lastChanged,
    this.delay,
    this.openSensors = const [],
  });

  int get elapsed   => DateTime.now().difference(lastChanged).inSeconds;
  int get remaining => delay != null ? (delay! - elapsed).clamp(0, delay!) : 0;
  bool get hasCountdown => (state == AlarmState.arming || state == AlarmState.pending) && delay != null;
}

// ─── App ──────────────────────────────────────────────────────
class AlarmApp extends StatelessWidget {
  const AlarmApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Alarma',
      debugShowCheckedModeBanner: false,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('es', 'ES'),
      ],
      locale: const Locale('es', 'ES'),
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: kBg,
        colorScheme: const ColorScheme.dark(surface: kSurface, primary: kBlue),
      ),
      home: const HomeScreen(),
    );
  }
}

// ─── Config ───────────────────────────────────────────────────
class Config {
  final String url, token, entityId, code, updateUrl;
  const Config({required this.url, required this.token, required this.entityId,
      required this.code, required this.updateUrl});
  bool get isValid => url.isNotEmpty && token.isNotEmpty && entityId.isNotEmpty;

  static Future<Config> load() async {
    final p = await SharedPreferences.getInstance();
    return Config(
      url:       p.getString('ha_url')       ?? '',
      token:     p.getString('ha_token')     ?? '',
      entityId:  p.getString('ha_entity')    ?? '',
      code:      p.getString('ha_code')      ?? '',
      updateUrl: p.getString('ha_updateUrl') ?? '',
    );
  }

  Future<void> save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('ha_url',       url);
    await p.setString('ha_token',     token);
    await p.setString('ha_entity',    entityId);
    await p.setString('ha_code',      code);
    await p.setString('ha_updateUrl', updateUrl);
  }
}

// ─── Servicio HA ──────────────────────────────────────────────
class HaService {
  final Config config;
  HaService(this.config);

  Map<String, String> get _headers => {
    'Authorization': 'Bearer ${config.token}',
    'Content-Type': 'application/json',
  };

  Future<AlarmStateData> getState() async {
    final uri = Uri.parse('${config.url}/api/states/${config.entityId}');
    final res = await http.get(uri, headers: _headers).timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) throw Exception('Error ${res.statusCode}');

    final data       = jsonDecode(res.body);
    final state      = parseState(data['state'] as String);
    final attrs      = data['attributes'] as Map<String, dynamic>? ?? {};
    final lastChanged = DateTime.parse(data['last_changed'] as String).toLocal();

    // Delay: Alarmo lo provee en segundos
    int? delay;
    if (attrs.containsKey('delay')) {
      delay = (attrs['delay'] as num?)?.toInt();
    }

    // Sensores abiertos que bloquearon el armado
    List<String> openSensors = [];
    if (attrs.containsKey('open_sensors')) {
      final raw = attrs['open_sensors'];
      if (raw is Map) openSensors = raw.keys.map((k) => k.toString()).toList();
      if (raw is List) openSensors = raw.map((e) => e.toString()).toList();
    }

    return AlarmStateData(
      state: state, lastChanged: lastChanged,
      delay: delay, openSensors: openSensors,
    );
  }

  Future<void> disarm()  => _call('alarm_disarm', {'code': config.code});
  Future<void> armAway() => _call('alarm_arm_away', {});

  Future<void> _call(String service, Map<String, dynamic> extra) async {
    final uri  = Uri.parse('${config.url}/api/services/alarm_control_panel/$service');
    final body = jsonEncode({'entity_id': config.entityId, ...extra});
    final res  = await http.post(uri, headers: _headers, body: body).timeout(const Duration(seconds: 10));
    if (res.statusCode != 200 && res.statusCode != 201) throw Exception('Error ${res.statusCode}');
  }
}

// ─── Servicio de actualización ────────────────────────────────
class UpdateInfo { final String version, apkUrl; UpdateInfo({required this.version, required this.apkUrl}); }

class UpdateService {
  static bool _checkedThisSession = false;

  static bool _isNewer(String remote, String current) {
    List<int> parse(String v) => v.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final r = parse(remote); final c = parse(current);
    for (int i = 0; i < 3; i++) {
      final rv = i < r.length ? r[i] : 0; final cv = i < c.length ? c[i] : 0;
      if (rv > cv) return true; if (rv < cv) return false;
    }
    return false;
  }

  static Future<UpdateInfo?> check(String url) async {
    if (_checkedThisSession) return null;
    _checkedThisSession = true;
    try {
      final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return null;
      final data          = jsonDecode(res.body);
      final remoteVersion = data['version'] as String;
      final apkUrl        = data['url'] as String;
      final info          = await PackageInfo.fromPlatform();
      final prefs         = await SharedPreferences.getInstance();
      if (prefs.getString('last_update_notified') == remoteVersion) return null;
      if (_isNewer(remoteVersion, info.version)) return UpdateInfo(version: remoteVersion, apkUrl: apkUrl);
    } catch (_) {}
    return null;
  }

  static Future<void> downloadAndInstall(String url, void Function(double) onProgress) async {
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

// ─── Pantalla Principal ───────────────────────────────────────
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Config?         _config;
  AlarmStateData? _stateData;
  bool            _configLoaded = false;   // ← distingue cargando vs sin config
  bool            _loading    = true;
  bool            _actionBusy = false;
  String?         _error;
  Timer?          _pollTimer;
  Timer?          _countdownTimer;

  @override
  void initState() { super.initState(); _init(); }

  Future<void> _init() async {
    _config = await Config.load();
    setState(() => _configLoaded = true);
    if (_config!.isValid) {
      await _refresh();
      _pollTimer = Timer.periodic(const Duration(seconds: 15), (_) => _refresh());
    } else {
      setState(() => _loading = false);
    }
    if (_config!.updateUrl.isNotEmpty) _checkUpdate();
  }

  Future<void> _refresh() async {
    if (_config == null || !_config!.isValid) return;
    try {
      final data = await HaService(_config!).getState();
      if (mounted) {
        setState(() { _stateData = data; _loading = false; _error = null; });
        _updateCountdownTimer(data);
      }
    } catch (e) {
      if (mounted) setState(() { _error = 'Sin conexión'; _loading = false; });
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
    double progress = 0; bool downloading = false; String? dlError;
    showDialog(
      context: context, barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) => Dialog(
        backgroundColor: kSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(padding: const EdgeInsets.all(28), child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.system_update_rounded, color: kBlue, size: 44),
          const SizedBox(height: 14),
          const Text('Actualización disponible', style: TextStyle(color: kText, fontWeight: FontWeight.bold, fontSize: 17)),
          const SizedBox(height: 8),
          Text('Versión ${info.version}', style: const TextStyle(color: kSubtext, fontSize: 14)),
          const SizedBox(height: 20),
          if (downloading) ...[
            LinearProgressIndicator(value: progress, backgroundColor: kBg, color: kBlue, borderRadius: BorderRadius.circular(4)),
            const SizedBox(height: 8),
            Text('${(progress * 100).toInt()}%', style: const TextStyle(color: kSubtext, fontSize: 13)),
          ],
          if (dlError != null) Text(dlError!, style: const TextStyle(color: kRed, fontSize: 12)),
          const SizedBox(height: 20),
          Row(children: [
            Expanded(child: OutlinedButton(
              onPressed: downloading ? null : () async {
                final prefs = await SharedPreferences.getInstance();
                await prefs.setString('last_update_notified', info.version);
                if (ctx.mounted) Navigator.pop(ctx);
              },
              style: OutlinedButton.styleFrom(foregroundColor: kSubtext, side: const BorderSide(color: kSubtext),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              child: const Text('Ahora no'),
            )),
            const SizedBox(width: 14),
            Expanded(child: ElevatedButton(
              onPressed: downloading ? null : () async {
                setS(() { downloading = true; dlError = null; });
                try {
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setString('last_update_notified', info.version);
                  await UpdateService.downloadAndInstall(info.apkUrl, (p) => setS(() => progress = p));
                  if (ctx.mounted) Navigator.pop(ctx);
                } catch (e) {
                  setS(() { downloading = false; dlError = 'Error: $e'; });
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: kBlue, foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), elevation: 0),
              child: const Text('Actualizar', style: TextStyle(fontWeight: FontWeight.bold)),
            )),
          ]),
        ])),
      )),
    );
  }

  Future<void> _execute(String action) async {
    setState(() => _actionBusy = true);
    try {
      if (action == 'disarm') await HaService(_config!).disarm();
      if (action == 'arm')    await HaService(_config!).armAway();
      await Future.delayed(const Duration(milliseconds: 800));
      await _refresh();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('❌ Error al ejecutar la acción'), backgroundColor: kRed));
    } finally {
      if (mounted) setState(() => _actionBusy = false);
    }
  }

  void _confirm(String action, String label, Color color, IconData icon) {
    showDialog(
      context: context, barrierDismissible: false,
      builder: (ctx) => Dialog(
        backgroundColor: kSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(padding: const EdgeInsets.all(28), child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: color.withOpacity(0.15), shape: BoxShape.circle),
            child: Icon(icon, color: color, size: 40)),
          const SizedBox(height: 18),
          const Text('¿Confirmar acción?', style: TextStyle(color: kText, fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text('Se va a aplicar: $label', textAlign: TextAlign.center, style: const TextStyle(color: kSubtext, fontSize: 14)),
          const SizedBox(height: 28),
          Row(children: [
            Expanded(child: OutlinedButton(
              onPressed: () => Navigator.pop(ctx),
              style: OutlinedButton.styleFrom(foregroundColor: kSubtext, side: const BorderSide(color: kSubtext),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              child: const Text('Cancelar'),
            )),
            const SizedBox(width: 14),
            Expanded(child: ElevatedButton(
              onPressed: () { Navigator.pop(ctx); _execute(action); },
              style: ElevatedButton.styleFrom(backgroundColor: color.withOpacity(0.2), foregroundColor: color,
                  side: BorderSide(color: color), padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), elevation: 0),
              child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
            )),
          ]),
        ])),
      ),
    );
  }

  Future<void> _goConfig() async {
    _pollTimer?.cancel(); _countdownTimer?.cancel();
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const ConfigScreen()));
    _config = null;
    setState(() { _loading = true; _configLoaded = false; _stateData = null; _error = null; });
    _init();
  }

  @override
  void dispose() { _pollTimer?.cancel(); _countdownTimer?.cancel(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final data  = _stateData;
    final state = data?.state ?? AlarmState.unknown;
    final info  = stateInfo[state]!;
    final color = info['color'] as Color;
    final icon  = info['icon'] as IconData;
    final label = info['label'] as String;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: kBg, elevation: 0,
        title: const Text('🏡 Alarma Casa', style: TextStyle(color: kText, fontWeight: FontWeight.bold, fontSize: 18)),
        actions: [
          IconButton(icon: const Icon(Icons.info_outline_rounded, color: kSubtext),
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AboutScreen()))),
          IconButton(icon: const Icon(Icons.settings_outlined, color: kSubtext), onPressed: _goConfig),
        ],
      ),
      body: !_configLoaded
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2, color: kBlue))
          : !(_config?.isValid ?? false)
          ? _NoConfig(onConfig: _goConfig)
          : Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 30),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [

                // ── Estado ──
                AnimatedContainer(
                  duration: const Duration(milliseconds: 400),
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: color.withOpacity(0.35), width: 1.5),
                    boxShadow: [BoxShadow(color: color.withOpacity(0.12), blurRadius: 20)],
                  ),
                  child: Column(children: [
                    Icon(icon, color: color, size: 52),
                    const SizedBox(height: 12),
                    const Text('Estado actual', style: TextStyle(color: kSubtext, fontSize: 12, letterSpacing: 1.2)),
                    const SizedBox(height: 6),
                    if (_loading && data == null)
                      const CircularProgressIndicator(strokeWidth: 2)
                    else if (_error != null)
                      Text(_error!, style: const TextStyle(color: kRed, fontWeight: FontWeight.bold, fontSize: 18))
                    else
                      Text(label, style: TextStyle(color: color, fontSize: 22, fontWeight: FontWeight.bold)),

                    // ── Contador arming / pending ──
                    if (data != null && data.hasCountdown) ...[
                      const SizedBox(height: 14),
                      _CountdownBar(data: data, color: color),
                    ],

                    // ── Sensores abiertos (solo al armar o disparar) ──
                    if (data != null && data.openSensors.isNotEmpty &&
                        (state == AlarmState.arming || state == AlarmState.triggered)) ...[
                      const SizedBox(height: 14),
                      _OpenSensorsWarning(sensors: data.openSensors),
                    ],
                  ]),
                ),

                const SizedBox(height: 32),

                // ── Botones ──
                Row(children: [
                  Expanded(child: _ActionButton(
                    label: 'Desarmar', icon: Icons.lock_open_rounded, color: kGreen,
                    active: state == AlarmState.disarmed, busy: _actionBusy,
                    onTap: () => _confirm('disarm', 'Desarmar', kGreen, Icons.lock_open_rounded),
                  )),
                  const SizedBox(width: 16),
                  Expanded(child: _ActionButton(
                    label: 'Armar', icon: Icons.lock_rounded, color: kRed,
                    active: state == AlarmState.armedAway, busy: _actionBusy,
                    onTap: () => _confirm('arm', 'Armar', kRed, Icons.lock_rounded),
                  )),
                ]),

                const SizedBox(height: 24),
                TextButton.icon(
                  onPressed: (_loading || _actionBusy) ? null : _refresh,
                  icon: const Icon(Icons.refresh_rounded, size: 16, color: kSubtext),
                  label: const Text('Actualizar estado', style: TextStyle(color: kSubtext, fontSize: 12)),
                ),
              ]),
            ),
    );
  }
}

// ─── Barra de cuenta atrás ────────────────────────────────────
class _CountdownBar extends StatelessWidget {
  final AlarmStateData data;
  final Color color;
  const _CountdownBar({required this.data, required this.color});

  @override
  Widget build(BuildContext context) {
    final remaining = data.remaining;
    final total     = data.delay ?? 1;
    final progress  = remaining / total;
    final mins      = remaining ~/ 60;
    final secs      = remaining % 60;
    final timeStr   = mins > 0 ? '${mins}m ${secs.toString().padLeft(2,'0')}s' : '${secs}s';

    return Column(children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(data.state == AlarmState.arming ? 'Tiempo para armarse' : 'Tiempo para disparar',
            style: TextStyle(color: color.withOpacity(0.8), fontSize: 12)),
        Text(timeStr, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 18,
            fontFeatures: const [FontFeature.tabularFigures()])),
      ]),
      const SizedBox(height: 8),
      ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: LinearProgressIndicator(
          value: progress,
          backgroundColor: color.withOpacity(0.15),
          valueColor: AlwaysStoppedAnimation<Color>(color),
          minHeight: 8,
        ),
      ),
    ]);
  }
}

// ─── Advertencia sensores abiertos ───────────────────────────
class _OpenSensorsWarning extends StatelessWidget {
  final List<String> sensors;
  const _OpenSensorsWarning({required this.sensors});

  String _friendlyName(String entityId) {
    // Convierte entity_id a nombre legible
    return entityId.split('.').last.replaceAll('_', ' ').split(' ')
        .map((w) => w.isNotEmpty ? '${w[0].toUpperCase()}${w.substring(1)}' : '')
        .join(' ');
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: kRed.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kRed.withOpacity(0.4)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [
          Icon(Icons.sensor_door_rounded, color: kRed, size: 16),
          SizedBox(width: 6),
          Text('Sensores abiertos', style: TextStyle(color: kRed, fontWeight: FontWeight.bold, fontSize: 13)),
        ]),
        const SizedBox(height: 6),
        ...sensors.map((s) => Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Row(children: [
            const Icon(Icons.circle, color: kRed, size: 6),
            const SizedBox(width: 8),
            Text(_friendlyName(s), style: const TextStyle(color: kText, fontSize: 13)),
          ]),
        )),
      ]),
    );
  }
}

// ─── Botón de acción ──────────────────────────────────────────
class _ActionButton extends StatelessWidget {
  final String label; final IconData icon; final Color color;
  final bool active, busy; final VoidCallback onTap;
  const _ActionButton({required this.label, required this.icon, required this.color,
      required this.active, required this.busy, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: (busy || active) ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.symmetric(vertical: 28),
        decoration: BoxDecoration(
          color: active ? color.withOpacity(0.18) : kSurface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: active ? color : color.withOpacity(0.4), width: active ? 2 : 1.5),
          boxShadow: active ? [BoxShadow(color: color.withOpacity(0.25), blurRadius: 18, spreadRadius: 1)] : [],
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: active ? color : color.withOpacity(0.65), size: 38),
          const SizedBox(height: 10),
          Text(label, style: TextStyle(color: active ? color : kSubtext, fontWeight: FontWeight.bold, fontSize: 15)),
        ]),
      ),
    );
  }
}

// ─── Sin configuración ────────────────────────────────────────
class _NoConfig extends StatelessWidget {
  final VoidCallback onConfig;
  const _NoConfig({required this.onConfig});
  @override
  Widget build(BuildContext context) {
    return Center(child: Padding(padding: const EdgeInsets.all(32), child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.settings_suggest_outlined, color: kSubtext, size: 72),
      const SizedBox(height: 20),
      const Text('Configura la conexión primero', textAlign: TextAlign.center, style: TextStyle(color: kSubtext, fontSize: 16)),
      const SizedBox(height: 24),
      ElevatedButton.icon(icon: const Icon(Icons.settings), label: const Text('Ir a configuración'), onPressed: onConfig,
        style: ElevatedButton.styleFrom(backgroundColor: kBlue, foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)))),
    ])));
  }
}

// ─── Pantalla Acerca de ───────────────────────────────────────
class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});
  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  String _version = '...';

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((i) => setState(() => _version = '${i.version} (build ${i.buildNumber})'));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: kBg, elevation: 0,
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new, color: kSubtext, size: 20),
            onPressed: () => Navigator.pop(context)),
        title: const Text('Acerca de', style: TextStyle(color: kText, fontWeight: FontWeight.bold)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(children: [

          const SizedBox(height: 12),

          // Icono
          Container(
            width: 110, height: 110,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(26),
              boxShadow: [BoxShadow(color: kBlue.withOpacity(0.2), blurRadius: 24, spreadRadius: 2)],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(26),
              child: Image.asset('assets/icon.png', fit: BoxFit.cover),
            ),
          ),

          const SizedBox(height: 20),
          const Text('Alarma Casa HA', style: TextStyle(color: kText, fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Text('Versión $_version', style: const TextStyle(color: kSubtext, fontSize: 14)),

          const SizedBox(height: 32),

          // Tarjeta info
          _AboutCard(items: const [
            _AboutItem(icon: Icons.person_rounded,      label: 'Desarrollador', value: 'Alfredo Fernández Badía'),
            _AboutItem(icon: Icons.home_work_rounded,   label: 'Proyecto',      value: 'Control de alarma para Home Assistant'),
            _AboutItem(icon: Icons.location_city_rounded, label: 'Ubicación',   value: 'Bargas, Toledo'),
            _AboutItem(icon: Icons.calendar_today_rounded, label: 'Año',        value: '2025'),
          ]),

          const SizedBox(height: 16),

          _AboutCard(items: const [
            _AboutItem(icon: Icons.code_rounded,       label: 'Tecnología',   value: 'Flutter'),
            _AboutItem(icon: Icons.hub_rounded,        label: 'Plataforma',   value: 'Home Assistant + Alarmo'),
            _AboutItem(icon: Icons.build_circle_rounded, label: 'CI/CD',      value: 'GitHub Actions'),
          ]),

          const SizedBox(height: 32),

          const Text('Uso personal — Todos los derechos reservados',
              textAlign: TextAlign.center,
              style: TextStyle(color: kSubtext, fontSize: 11)),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }
}

class _AboutCard extends StatelessWidget {
  final List<_AboutItem> items;
  const _AboutCard({required this.items});
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(color: kSurface, borderRadius: BorderRadius.circular(18)),
      child: Column(children: items.asMap().entries.map((e) {
        final isLast = e.key == items.length - 1;
        return Column(children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            child: Row(children: [
              Icon(e.value.icon, color: kBlue, size: 20),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(e.value.label, style: const TextStyle(color: kSubtext, fontSize: 11)),
                const SizedBox(height: 2),
                Text(e.value.value, style: const TextStyle(color: kText, fontSize: 14, fontWeight: FontWeight.w500)),
              ])),
            ]),
          ),
          if (!isLast) Divider(height: 1, color: kBg, indent: 52),
        ]);
      }).toList()),
    );
  }
}

class _AboutItem {
  final IconData icon; final String label, value;
  const _AboutItem({required this.icon, required this.label, required this.value});
}

// ─── Pantalla de Configuración ────────────────────────────────
class ConfigScreen extends StatefulWidget {
  const ConfigScreen({super.key});
  @override
  State<ConfigScreen> createState() => _ConfigScreenState();
}

class _ConfigScreenState extends State<ConfigScreen> {
  final _urlCtrl       = TextEditingController();
  final _tokenCtrl     = TextEditingController();
  final _entityCtrl    = TextEditingController();
  final _codeCtrl      = TextEditingController();
  final _updateUrlCtrl = TextEditingController();
  bool _obscureToken = true, _obscureCode = true, _saving = false, _testing = false;
  String? _testResult;

  @override
  void initState() {
    super.initState();
    Config.load().then((c) {
      _urlCtrl.text = c.url; _tokenCtrl.text = c.token;
      _entityCtrl.text = c.entityId; _codeCtrl.text = c.code;
      _updateUrlCtrl.text = c.updateUrl;
    });
  }

  Config _buildConfig() => Config(
    url:       _urlCtrl.text.trim().replaceAll(RegExp(r'/$'), ''),
    token:     _tokenCtrl.text.trim(),
    entityId:  _entityCtrl.text.trim(),
    code:      _codeCtrl.text.trim(),
    updateUrl: _updateUrlCtrl.text.trim(),
  );

  Future<void> _test() async {
    setState(() { _testing = true; _testResult = null; });
    try {
      final d = await HaService(_buildConfig()).getState();
      setState(() => _testResult = '✅ Conexión OK — Estado: ${stateInfo[d.state]!['label']}');
    } catch (e) {
      setState(() => _testResult = '❌ Error: $e');
    } finally {
      setState(() => _testing = false);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    await _buildConfig().save();
    setState(() => _saving = false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ Configuración guardada'), backgroundColor: kGreen));
      Navigator.pop(context);
    }
  }

  @override
  void dispose() {
    _urlCtrl.dispose(); _tokenCtrl.dispose();
    _entityCtrl.dispose(); _codeCtrl.dispose();
    _updateUrlCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: kBg, elevation: 0,
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new, color: kSubtext, size: 20),
            onPressed: () => Navigator.pop(context)),
        title: const Text('Configuración', style: TextStyle(color: kText, fontWeight: FontWeight.bold)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

          _SectionCard(title: '🌐 Conexión', children: [
            _InputField(ctrl: _urlCtrl,    label: 'URL de Home Assistant',       hint: 'https://tu-servidor.es',          icon: Icons.link_rounded),
            const SizedBox(height: 14),
            _InputField(ctrl: _tokenCtrl,  label: 'Token de acceso (Long-Lived)', hint: 'eyJhbGciOiJIUzI1NiIs...',        icon: Icons.vpn_key_rounded,    obscure: _obscureToken, onToggle: () => setState(() => _obscureToken = !_obscureToken)),
            const SizedBox(height: 14),
            _InputField(ctrl: _entityCtrl, label: 'Entity ID de la alarma',       hint: 'alarm_control_panel.alarmo',     icon: Icons.security_rounded),
          ]),

          const SizedBox(height: 20),

          _SectionCard(title: '🔑 Seguridad', children: [
            _InputField(ctrl: _codeCtrl, label: 'Código de desarmado', hint: '1234',
                icon: Icons.dialpad_rounded, obscure: _obscureCode,
                onToggle: () => setState(() => _obscureCode = !_obscureCode),
                keyboardType: TextInputType.number),
          ]),

          const SizedBox(height: 20),

          _SectionCard(title: '🔄 Actualizaciones', children: [
            _InputField(ctrl: _updateUrlCtrl, label: 'URL del fichero version.json',
                hint: 'https://tu-servidor.es/ha_alarm/version.json', icon: Icons.cloud_download_rounded),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: const Color(0xFF1e3a5f), borderRadius: BorderRadius.circular(12)),
              child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Formato del version.json:', style: TextStyle(color: Color(0xFF60a5fa), fontSize: 12, fontWeight: FontWeight.bold)),
                SizedBox(height: 6),
                Text('{\n  "version": "1.0.2",\n  "url": "https://.../app.apk"\n}',
                    style: TextStyle(color: Color(0xFF93c5fd), fontSize: 11, fontFamily: 'monospace')),
              ]),
            ),
          ]),

          const SizedBox(height: 16),

          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: const Color(0xFF1e3a5f), borderRadius: BorderRadius.circular(14)),
            child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.info_outline_rounded, color: Color(0xFF60a5fa), size: 18),
              SizedBox(width: 10),
              Expanded(child: Text('Token: HA → Perfil de usuario → Tokens de larga duración (al final de la página)',
                  style: TextStyle(color: Color(0xFF93c5fd), fontSize: 12, height: 1.5))),
            ]),
          ),

          const SizedBox(height: 28),

          SizedBox(width: double.infinity, height: 50,
            child: OutlinedButton.icon(
              onPressed: _testing ? null : _test,
              icon: _testing
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: kBlue))
                  : const Icon(Icons.wifi_find_rounded, color: kBlue),
              label: Text(_testing ? 'Probando...' : 'Probar conexión',
                  style: const TextStyle(color: kBlue, fontWeight: FontWeight.w600, fontSize: 15)),
              style: OutlinedButton.styleFrom(foregroundColor: kBlue, side: const BorderSide(color: kBlue),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
            ),
          ),

          if (_testResult != null) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity, padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _testResult!.startsWith('✅') ? kGreen.withOpacity(0.1) : kRed.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _testResult!.startsWith('✅') ? kGreen.withOpacity(0.4) : kRed.withOpacity(0.4)),
              ),
              child: Text(_testResult!, style: TextStyle(
                  color: _testResult!.startsWith('✅') ? kGreen : kRed, fontSize: 13, fontWeight: FontWeight.w600)),
            ),
          ],

          const SizedBox(height: 16),

          SizedBox(width: double.infinity, height: 54,
            child: ElevatedButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.save_rounded, color: Colors.white),
              label: Text(_saving ? 'Guardando...' : 'Guardar configuración',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
              style: ElevatedButton.styleFrom(backgroundColor: kBlue, foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), elevation: 0),
            ),
          ),
        ]),
      ),
    );
  }
}

// ─── Widgets auxiliares ───────────────────────────────────────
class _SectionCard extends StatelessWidget {
  final String title; final List<Widget> children;
  const _SectionCard({required this.title, required this.children});
  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(padding: const EdgeInsets.only(left: 4, bottom: 12),
        child: Text(title, style: const TextStyle(color: kText, fontWeight: FontWeight.bold, fontSize: 15))),
      Container(padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(color: kSurface, borderRadius: BorderRadius.circular(18)),
        child: Column(children: children)),
    ]);
  }
}

class _InputField extends StatelessWidget {
  final TextEditingController ctrl;
  final String label, hint; final IconData icon;
  final bool obscure; final VoidCallback? onToggle; final TextInputType? keyboardType;
  const _InputField({required this.ctrl, required this.label, required this.hint, required this.icon,
      this.obscure = false, this.onToggle, this.keyboardType});
  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: ctrl, obscureText: obscure, keyboardType: keyboardType,
      style: const TextStyle(color: kText, fontSize: 14),
      decoration: InputDecoration(
        labelText: label, labelStyle: const TextStyle(color: kSubtext, fontSize: 13),
        hintText: hint, hintStyle: TextStyle(color: kSubtext.withOpacity(0.45), fontSize: 12),
        prefixIcon: Icon(icon, color: kSubtext, size: 20),
        suffixIcon: onToggle != null
            ? IconButton(icon: Icon(obscure ? Icons.visibility_rounded : Icons.visibility_off_rounded,
                color: kSubtext, size: 20), onPressed: onToggle)
            : null,
        filled: true, fillColor: kBg,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: kBlue, width: 1.5)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      ),
    );
  }
}
