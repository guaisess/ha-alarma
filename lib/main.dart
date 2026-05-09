import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

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
const kText    = Color(0xFFf1f5f9);
const kSubtext = Color(0xFF94a3b8);

// ─── Estado de la alarma ──────────────────────────────────────
enum AlarmState { disarmed, armedAway, armedHome, armedNight, pending, triggered, unknown }

AlarmState parseState(String s) {
  switch (s) {
    case 'disarmed':    return AlarmState.disarmed;
    case 'armed_away':  return AlarmState.armedAway;
    case 'armed_home':  return AlarmState.armedHome;
    case 'armed_night': return AlarmState.armedNight;
    case 'pending':     return AlarmState.pending;
    case 'triggered':   return AlarmState.triggered;
    default:            return AlarmState.unknown;
  }
}

const stateInfo = {
  AlarmState.disarmed:  {'label': 'Desarmada',       'color': kGreen,  'icon': Icons.lock_open},
  AlarmState.armedAway: {'label': 'Armada',           'color': kRed,    'icon': Icons.lock},
  AlarmState.armedHome: {'label': 'Armada (Casa)',    'color': Color(0xFFf97316), 'icon': Icons.home},
  AlarmState.armedNight:{'label': 'Armada (Noche)',   'color': Color(0xFFa855f7), 'icon': Icons.bedtime},
  AlarmState.pending:   {'label': 'Activando...',     'color': kYellow, 'icon': Icons.timer},
  AlarmState.triggered: {'label': '¡ALARMA!',         'color': kRed,    'icon': Icons.warning},
  AlarmState.unknown:   {'label': 'Sin conexión',     'color': kSubtext,'icon': Icons.help_outline},
};

// ─── App ──────────────────────────────────────────────────────
class AlarmApp extends StatelessWidget {
  const AlarmApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Alarma',
      debugShowCheckedModeBanner: false,
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
  final String url;
  final String token;
  final String entityId;
  final String code;

  const Config({
    required this.url,
    required this.token,
    required this.entityId,
    required this.code,
  });

  bool get isValid => url.isNotEmpty && token.isNotEmpty && entityId.isNotEmpty;

  static Future<Config> load() async {
    final p = await SharedPreferences.getInstance();
    return Config(
      url:      p.getString('ha_url')    ?? '',
      token:    p.getString('ha_token')  ?? '',
      entityId: p.getString('ha_entity') ?? '',
      code:     p.getString('ha_code')   ?? '',
    );
  }

  Future<void> save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('ha_url',    url);
    await p.setString('ha_token',  token);
    await p.setString('ha_entity', entityId);
    await p.setString('ha_code',   code);
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

  Future<AlarmState> getState() async {
    final uri = Uri.parse('${config.url}/api/states/${config.entityId}');
    final res = await http.get(uri, headers: _headers)
        .timeout(const Duration(seconds: 10));
    if (res.statusCode == 200) {
      return parseState(jsonDecode(res.body)['state'] as String);
    }
    throw Exception('Error ${res.statusCode}');
  }

  Future<void> disarm() => _call('alarm_disarm', {'code': config.code});
  Future<void> armAway() => _call('alarm_arm_away', {});

  Future<void> _call(String service, Map<String, dynamic> extra) async {
    final uri = Uri.parse('${config.url}/api/services/alarm_control_panel/$service');
    final body = jsonEncode({'entity_id': config.entityId, ...extra});
    final res = await http.post(uri, headers: _headers, body: body)
        .timeout(const Duration(seconds: 10));
    if (res.statusCode != 200 && res.statusCode != 201) {
      throw Exception('Error ${res.statusCode}');
    }
  }
}

// ─── Pantalla Principal ───────────────────────────────────────
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Config? _config;
  AlarmState _state = AlarmState.unknown;
  bool _loading = true;
  bool _actionBusy = false;
  String? _error;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _config = await Config.load();
    if (_config!.isValid) {
      await _refresh();
      _timer = Timer.periodic(const Duration(seconds: 15), (_) => _refresh());
    } else {
      setState(() => _loading = false);
    }
  }

  Future<void> _refresh() async {
    if (_config == null || !_config!.isValid) return;
    try {
      final state = await HaService(_config!).getState();
      if (mounted) setState(() { _state = state; _loading = false; _error = null; });
    } catch (e) {
      if (mounted) setState(() { _error = 'Sin conexión'; _loading = false; });
    }
  }

  Future<void> _execute(String action) async {
    setState(() => _actionBusy = true);
    try {
      final svc = HaService(_config!);
      if (action == 'disarm') await svc.disarm();
      if (action == 'arm')    await svc.armAway();
      await Future.delayed(const Duration(milliseconds: 800));
      await _refresh();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('❌ Error al ejecutar la acción'), backgroundColor: kRed),
        );
      }
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
                color: color.withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 40),
            ),
            const SizedBox(height: 18),
            const Text('¿Confirmar acción?',
                style: TextStyle(color: kText, fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('Se va a aplicar: $label',
                textAlign: TextAlign.center,
                style: const TextStyle(color: kSubtext, fontSize: 14)),
            const SizedBox(height: 28),
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: kSubtext,
                    side: const BorderSide(color: kSubtext),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Cancelar'),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: ElevatedButton(
                  onPressed: () { Navigator.pop(ctx); _execute(action); },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: color.withOpacity(0.2),
                    foregroundColor: color,
                    side: BorderSide(color: color),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                  child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ]),
          ]),
        ),
      ),
    );
  }

  Future<void> _goConfig() async {
    _timer?.cancel();
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const ConfigScreen()));
    _config = null;
    setState(() { _loading = true; _state = AlarmState.unknown; _error = null; });
    _init();
  }

  @override
  void dispose() { _timer?.cancel(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final info   = stateInfo[_state]!;
    final color  = info['color'] as Color;
    final icon   = info['icon'] as IconData;
    final label  = info['label'] as String;
    final noConf = !(_config?.isValid ?? false);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: kBg,
        elevation: 0,
        title: const Text('🏡 Alarma Casa',
            style: TextStyle(color: kText, fontWeight: FontWeight.bold, fontSize: 18)),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined, color: kSubtext),
            onPressed: _goConfig,
          ),
        ],
      ),
      body: noConf
          ? _NoConfig(onConfig: _goConfig)
          : Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 30),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // ── Estado ──
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 400),
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 20),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: color.withOpacity(0.35), width: 1.5),
                      boxShadow: [BoxShadow(color: color.withOpacity(0.12), blurRadius: 20)],
                    ),
                    child: Column(children: [
                      Icon(icon, color: color, size: 56),
                      const SizedBox(height: 14),
                      const Text('Estado actual',
                          style: TextStyle(color: kSubtext, fontSize: 12, letterSpacing: 1.2)),
                      const SizedBox(height: 6),
                      if (_loading && _state == AlarmState.unknown)
                        const CircularProgressIndicator(strokeWidth: 2)
                      else if (_error != null)
                        Text(_error!, style: const TextStyle(color: kRed, fontWeight: FontWeight.bold, fontSize: 18))
                      else
                        Text(label, style: TextStyle(color: color, fontSize: 22, fontWeight: FontWeight.bold)),
                    ]),
                  ),

                  const SizedBox(height: 36),

                  // ── Botones ──
                  Row(children: [
                    Expanded(child: _ActionButton(
                      label: 'Desarmar',
                      icon: Icons.lock_open_rounded,
                      color: kGreen,
                      active: _state == AlarmState.disarmed,
                      busy: _actionBusy,
                      onTap: () => _confirm('disarm', 'Desarmar', kGreen, Icons.lock_open_rounded),
                    )),
                    const SizedBox(width: 16),
                    Expanded(child: _ActionButton(
                      label: 'Armar',
                      icon: Icons.lock_rounded,
                      color: kRed,
                      active: _state == AlarmState.armedAway,
                      busy: _actionBusy,
                      onTap: () => _confirm('arm', 'Armar', kRed, Icons.lock_rounded),
                    )),
                  ]),

                  const SizedBox(height: 24),

                  // ── Refresh manual ──
                  TextButton.icon(
                    onPressed: (_loading || _actionBusy) ? null : _refresh,
                    icon: const Icon(Icons.refresh_rounded, size: 16, color: kSubtext),
                    label: const Text('Actualizar estado',
                        style: TextStyle(color: kSubtext, fontSize: 12)),
                  ),
                ],
              ),
            ),
    );
  }
}

// ─── Botón de acción ──────────────────────────────────────────
class _ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool active;
  final bool busy;
  final VoidCallback onTap;

  const _ActionButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.active,
    required this.busy,
    required this.onTap,
  });

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
          border: Border.all(
            color: active ? color : color.withOpacity(0.4),
            width: active ? 2 : 1.5,
          ),
          boxShadow: active
              ? [BoxShadow(color: color.withOpacity(0.25), blurRadius: 18, spreadRadius: 1)]
              : [],
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: active ? color : color.withOpacity(0.65), size: 38),
          const SizedBox(height: 10),
          Text(label,
              style: TextStyle(
                color: active ? color : kSubtext,
                fontWeight: FontWeight.bold,
                fontSize: 15,
              )),
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
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.settings_suggest_outlined, color: kSubtext, size: 72),
          const SizedBox(height: 20),
          const Text('Configura la conexión primero',
              textAlign: TextAlign.center,
              style: TextStyle(color: kSubtext, fontSize: 16)),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            icon: const Icon(Icons.settings),
            label: const Text('Ir a configuración'),
            onPressed: onConfig,
            style: ElevatedButton.styleFrom(
              backgroundColor: kBlue,
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ]),
      ),
    );
  }
}

// ─── Pantalla de Configuración ────────────────────────────────
class ConfigScreen extends StatefulWidget {
  const ConfigScreen({super.key});
  @override
  State<ConfigScreen> createState() => _ConfigScreenState();
}

class _ConfigScreenState extends State<ConfigScreen> {
  final _urlCtrl    = TextEditingController();
  final _tokenCtrl  = TextEditingController();
  final _entityCtrl = TextEditingController();
  final _codeCtrl   = TextEditingController();
  bool _obscureToken = true;
  bool _obscureCode  = true;
  bool _saving       = false;
  bool _testing      = false;
  String? _testResult;

  @override
  void initState() {
    super.initState();
    Config.load().then((c) {
      _urlCtrl.text    = c.url;
      _tokenCtrl.text  = c.token;
      _entityCtrl.text = c.entityId;
      _codeCtrl.text   = c.code;
    });
  }

  Future<void> _test() async {
    setState(() { _testing = true; _testResult = null; });
    try {
      final cfg = _buildConfig();
      final state = await HaService(cfg).getState();
      setState(() => _testResult = '✅ Conexión OK — Estado: ${stateInfo[state]!['label']}');
    } catch (e) {
      setState(() => _testResult = '❌ Error: $e');
    } finally {
      setState(() => _testing = false);
    }
  }

  Config _buildConfig() => Config(
    url:      _urlCtrl.text.trim().replaceAll(RegExp(r'/$'), ''),
    token:    _tokenCtrl.text.trim(),
    entityId: _entityCtrl.text.trim(),
    code:     _codeCtrl.text.trim(),
  );

  Future<void> _save() async {
    setState(() => _saving = true);
    await _buildConfig().save();
    setState(() => _saving = false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ Configuración guardada'), backgroundColor: kGreen),
      );
      Navigator.pop(context);
    }
  }

  @override
  void dispose() {
    _urlCtrl.dispose(); _tokenCtrl.dispose();
    _entityCtrl.dispose(); _codeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: kBg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: kSubtext, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Configuración',
            style: TextStyle(color: kText, fontWeight: FontWeight.bold)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

          // ── Sección Conexión ──
          _SectionCard(title: '🌐 Conexión', children: [
            _InputField(
              ctrl: _urlCtrl,
              label: 'URL de Home Assistant',
              hint: 'http://192.168.1.100:8123',
              icon: Icons.link_rounded,
            ),
            const SizedBox(height: 14),
            _InputField(
              ctrl: _tokenCtrl,
              label: 'Token de acceso (Long-Lived)',
              hint: 'eyJhbGciOiJIUzI1NiIs...',
              icon: Icons.vpn_key_rounded,
              obscure: _obscureToken,
              onToggle: () => setState(() => _obscureToken = !_obscureToken),
            ),
            const SizedBox(height: 14),
            _InputField(
              ctrl: _entityCtrl,
              label: 'Entity ID de la alarma',
              hint: 'alarm_control_panel.home',
              icon: Icons.security_rounded,
            ),
          ]),

          const SizedBox(height: 20),

          // ── Sección Seguridad ──
          _SectionCard(title: '🔑 Seguridad', children: [
            _InputField(
              ctrl: _codeCtrl,
              label: 'Código de desarmado',
              hint: '1234',
              icon: Icons.dialpad_rounded,
              obscure: _obscureCode,
              onToggle: () => setState(() => _obscureCode = !_obscureCode),
              keyboardType: TextInputType.number,
            ),
          ]),

          const SizedBox(height: 16),

          // ── Info token ──
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF1e3a5f),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.info_outline_rounded, color: Color(0xFF60a5fa), size: 18),
              SizedBox(width: 10),
              Expanded(child: Text(
                'El token se genera en HA → Perfil de usuario → Tokens de larga duración (abajo del todo)',
                style: TextStyle(color: Color(0xFF93c5fd), fontSize: 12, height: 1.5),
              )),
            ]),
          ),

          const SizedBox(height: 28),

          // ── Botón probar conexión ──
          SizedBox(
            width: double.infinity,
            height: 50,
            child: OutlinedButton.icon(
              onPressed: _testing ? null : _test,
              icon: _testing
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: kBlue))
                  : const Icon(Icons.wifi_find_rounded, color: kBlue),
              label: Text(_testing ? 'Probando...' : 'Probar conexión',
                  style: const TextStyle(color: kBlue, fontWeight: FontWeight.w600)),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: kBlue),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),

          if (_testResult != null) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _testResult!.startsWith('✅') ? kGreen.withOpacity(0.1) : kRed.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _testResult!.startsWith('✅') ? kGreen.withOpacity(0.4) : kRed.withOpacity(0.4)),
              ),
              child: Text(_testResult!,
                  style: TextStyle(
                    color: _testResult!.startsWith('✅') ? kGreen : kRed,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  )),
            ),
          ],

          const SizedBox(height: 16),

          // ── Botón guardar ──
          SizedBox(
            width: double.infinity,
            height: 54,
            child: ElevatedButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.save_rounded),
              label: Text(_saving ? 'Guardando...' : 'Guardar configuración',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: kBlue,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: 0,
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

// ─── Widgets auxiliares ───────────────────────────────────────
class _SectionCard extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _SectionCard({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 12),
        child: Text(title,
            style: const TextStyle(color: kText, fontWeight: FontWeight.bold, fontSize: 15)),
      ),
      Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(color: kSurface, borderRadius: BorderRadius.circular(18)),
        child: Column(children: children),
      ),
    ]);
  }
}

class _InputField extends StatelessWidget {
  final TextEditingController ctrl;
  final String label, hint;
  final IconData icon;
  final bool obscure;
  final VoidCallback? onToggle;
  final TextInputType? keyboardType;

  const _InputField({
    required this.ctrl,
    required this.label,
    required this.hint,
    required this.icon,
    this.obscure = false,
    this.onToggle,
    this.keyboardType,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: ctrl,
      obscureText: obscure,
      keyboardType: keyboardType,
      style: const TextStyle(color: kText, fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: kSubtext, fontSize: 13),
        hintText: hint,
        hintStyle: TextStyle(color: kSubtext.withOpacity(0.45), fontSize: 12),
        prefixIcon: Icon(icon, color: kSubtext, size: 20),
        suffixIcon: onToggle != null
            ? IconButton(
                icon: Icon(
                  obscure ? Icons.visibility_rounded : Icons.visibility_off_rounded,
                  color: kSubtext, size: 20,
                ),
                onPressed: onToggle,
              )
            : null,
        filled: true,
        fillColor: kBg,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: kBlue, width: 1.5)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      ),
    );
  }
}
