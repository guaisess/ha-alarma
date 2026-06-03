import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';
import '../constants.dart';
import '../models.dart';
import '../services.dart';
import '../widgets.dart';
import '../main.dart';

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
  final _timeoutCtrl   = TextEditingController();

  bool         _obscureToken = true, _obscureCode = true;
  bool         _saving = false, _testing = false;
  bool         _showArmModes = false;
  String?      _testResult;
  AppThemeMode _selectedTheme = AppThemeMode.system;

  @override
  void initState() {
    super.initState();
    Config.load().then((c) {
      setState(() {
        _urlCtrl.text       = c.url;
        _tokenCtrl.text     = c.token;
        _entityCtrl.text    = c.entityId;
        _codeCtrl.text      = c.code;
        _updateUrlCtrl.text = c.updateUrl;
        _timeoutCtrl.text   = c.timeoutSeconds.toString();
      });
    });
    SharedPreferences.getInstance().then((prefs) {
      setState(() {
        _selectedTheme = themeFromString(prefs.getString('app_theme'));
        _showArmModes  = prefs.getBool('show_arm_modes') ?? false;
      });
    });
  }

  Config _buildConfig() => Config(
    url:            _urlCtrl.text.trim().replaceAll(RegExp(r'/$'), ''),
    token:          _tokenCtrl.text.trim(),
    entityId:       _entityCtrl.text.trim(),
    code:           _codeCtrl.text.trim(),
    updateUrl:      _updateUrlCtrl.text.trim(),
    timeoutSeconds: int.tryParse(_timeoutCtrl.text.trim()) ?? kTimeoutSeconds,
    showArmModes:   _showArmModes,
  );

  Future<void> _test() async {
    setState(() { _testing = true; _testResult = null; });
    try {
      final d = await HaService(_buildConfig()).getState();
      setState(() =>
          _testResult = '✅ Conexión OK — Estado: ${stateInfo[d.state]!['label']}');
    } catch (e) {
      setState(() => _testResult = '❌ Error: $e');
    } finally {
      setState(() => _testing = false);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    await _buildConfig().save();
    AlarmApp.of(context)?.setTheme(_selectedTheme);
    setState(() => _saving = false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('✅ Configuración guardada'),
          backgroundColor: kGreen));
      Navigator.pop(context, true);
    }
  }

  Future<void> _exportBackup() async {
    try {
      final path = await BackupService.saveBackupFile(includeHistory: true);
      if (path != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('✅ Backup guardado en Descargas/Alarma Casa Backups'),
            backgroundColor: kGreen,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Error al exportar: $e'),
            backgroundColor: kRed,
          ),
        );
      }
    }
  }

  Future<void> _importBackup() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        dialogTitle: 'Seleccionar backup',
        initialDirectory: '/storage/emulated/0/Download/Alarma Casa Backups',
      );

      if (result == null || result.files.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Importación cancelada'),
              backgroundColor: kSubtext,
            ),
          );
        }
        return;
      }

      final filePath = result.files.single.path;
      if (filePath == null) return;

      // Mostrar diálogo de confirmación
      if (!mounted) return;
      final confirm = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => Dialog(
          backgroundColor: Theme.of(context).brightness == Brightness.dark ? kSurface : Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.warning_rounded, color: kOrange, size: 44),
              const SizedBox(height: 14),
              const Text('¿Restaurar configuración?',
                  style: TextStyle(color: kText, fontWeight: FontWeight.bold, fontSize: 17)),
              const SizedBox(height: 8),
              const Text('Se sobrescribirá la configuración actual',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: kSubtext, fontSize: 13)),
              const SizedBox(height: 20),
              Row(children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    style: OutlinedButton.styleFrom(
                        foregroundColor: kSubtext,
                        side: const BorderSide(color: kSubtext),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                    child: const Text('Cancelar'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kBlue,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                    child: const Text('Restaurar', style: TextStyle(color: Colors.white)),
                  ),
                ),
              ]),
            ]),
          ),
        ),
      );

      if (confirm != true) return;

      // Restaurar backup
      final success = await BackupService.loadBackupFile(filePath);

      if (mounted) {
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ Configuración restaurada correctamente'),
              backgroundColor: kGreen,
              duration: Duration(seconds: 3),
            ),
          );
          // Recargar configuración
          await Future.delayed(const Duration(seconds: 1));
          Navigator.pop(context);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('❌ Error al restaurar el backup'),
              backgroundColor: kRed,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Error: $e'),
            backgroundColor: kRed,
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _urlCtrl.dispose(); _tokenCtrl.dispose();
    _entityCtrl.dispose(); _codeCtrl.dispose();
    _updateUrlCtrl.dispose(); _timeoutCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark       = Theme.of(context).brightness == Brightness.dark;
    final bgColor      = isDark ? kBg      : const Color(0xFFf1f5f9);
    final textColor    = isDark ? kText    : const Color(0xFF0f172a);
    final subtextColor = isDark ? kSubtext : const Color(0xFF64748b);
    final surfaceColor = isDark ? kSurface : Colors.white;
    final fieldBg      = isDark ? kBg      : const Color(0xFFf8fafc);

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        elevation: 0,
        leading: IconButton(
            icon: Icon(Icons.arrow_back_ios_new, color: subtextColor, size: 20),
            onPressed: () => Navigator.pop(context)),
        title: Text('Configuración',
            style: TextStyle(color: textColor, fontWeight: FontWeight.bold)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

          // ── Apariencia ──
          SectionCard(
            title: '🎨 Apariencia',
            surfaceColor: surfaceColor,
            textColor: textColor,
            children: [
              Row(children: [
                ThemeOption(
                  icon: Icons.brightness_auto_rounded,
                  label: 'Sistema',
                  selected: _selectedTheme == AppThemeMode.system,
                  onTap: () => setState(() => _selectedTheme = AppThemeMode.system),
                ),
                const SizedBox(width: 10),
                ThemeOption(
                  icon: Icons.light_mode_rounded,
                  label: 'Claro',
                  selected: _selectedTheme == AppThemeMode.light,
                  onTap: () => setState(() => _selectedTheme = AppThemeMode.light),
                ),
                const SizedBox(width: 10),
                ThemeOption(
                  icon: Icons.dark_mode_rounded,
                  label: 'Oscuro',
                  selected: _selectedTheme == AppThemeMode.dark,
                  onTap: () => setState(() => _selectedTheme = AppThemeMode.dark),
                ),
              ]),
            ],
          ),

          const SizedBox(height: 20),

          // ── Conexión ──
          SectionCard(
            title: '🌐 Conexión',
            surfaceColor: surfaceColor,
            textColor: textColor,
            children: [
              InputField(ctrl: _urlCtrl,   label: 'URL de Home Assistant',        hint: 'https://tu-servidor.es',     icon: Icons.link_rounded,    fieldBg: fieldBg, subtextColor: subtextColor, textColor: textColor),
              const SizedBox(height: 14),
              InputField(ctrl: _tokenCtrl, label: 'Token de acceso (Long-Lived)', hint: 'eyJhbGciOiJIUzI1NiIs...',   icon: Icons.vpn_key_rounded, fieldBg: fieldBg, subtextColor: subtextColor, textColor: textColor, obscure: _obscureToken, onToggle: () => setState(() => _obscureToken = !_obscureToken)),
              const SizedBox(height: 14),
              InputField(ctrl: _entityCtrl, label: 'Entity ID de la alarma', hint: 'alarm_control_panel.alarmo', icon: Icons.security_rounded, fieldBg: fieldBg, subtextColor: subtextColor, textColor: textColor),
            ],
          ),

          const SizedBox(height: 20),

          // ── Seguridad ──
          SectionCard(
            title: '🔑 Seguridad',
            surfaceColor: surfaceColor,
            textColor: textColor,
            children: [
              InputField(
                ctrl: _codeCtrl, label: 'Código de desarmado', hint: '1234',
                icon: Icons.dialpad_rounded,
                obscure: _obscureCode,
                onToggle: () => setState(() => _obscureCode = !_obscureCode),
                keyboardType: TextInputType.number,
                fieldBg: fieldBg, subtextColor: subtextColor, textColor: textColor,
              ),
            ],
          ),

          const SizedBox(height: 20),

          // ── Avanzado ──
          SectionCard(
            title: '⚙️ Avanzado',
            surfaceColor: surfaceColor,
            textColor: textColor,
            children: [
              InputField(
                ctrl: _timeoutCtrl,
                label: 'Timeout de conexión (segundos)',
                hint: '5',
                icon: Icons.timer_outlined,
                keyboardType: TextInputType.number,
                fieldBg: fieldBg, subtextColor: subtextColor, textColor: textColor,
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(children: [
                  const Icon(Icons.layers_rounded, color: kSubtext, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Mostrar modos de armado',
                          style: TextStyle(color: textColor, fontSize: 14, fontWeight: FontWeight.w500)),
                      Text('Añade Armar (Casa), Armar (Noche), Armar (Vac.)',
                          style: TextStyle(color: subtextColor, fontSize: 11)),
                    ]),
                  ),
                  Switch(
                    value: _showArmModes,
                    onChanged: (v) => setState(() => _showArmModes = v),
                    activeColor: kBlue,
                  ),
                ]),
              ),
            ],
          ),

          const SizedBox(height: 20),

          // ── Actualizaciones ──
          SectionCard(
            title: '🔄 Actualizaciones',
            surfaceColor: surfaceColor,
            textColor: textColor,
            children: [
              InputField(
                ctrl: _updateUrlCtrl,
                label: 'URL del fichero version.json',
                hint: 'https://tu-servidor.es/ha_alarm/version.json',
                icon: Icons.cloud_download_rounded,
                fieldBg: fieldBg, subtextColor: subtextColor, textColor: textColor,
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: const Color(0xFF1e3a5f),
                    borderRadius: BorderRadius.circular(12)),
                child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Formato del version.json:',
                      style: TextStyle(
                          color: Color(0xFF60a5fa),
                          fontSize: 12,
                          fontWeight: FontWeight.bold)),
                  SizedBox(height: 6),
                  Text('{\n  "version": "1.0.2",\n  "url": "https://.../app.apk"\n}',
                      style: TextStyle(
                          color: Color(0xFF93c5fd),
                          fontSize: 11,
                          fontFamily: 'monospace')),
                ]),
              ),
            ],
          ),

          const SizedBox(height: 16),

          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
                color: const Color(0xFF1e3a5f),
                borderRadius: BorderRadius.circular(14)),
            child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.info_outline_rounded, color: Color(0xFF60a5fa), size: 18),
              SizedBox(width: 10),
              Expanded(child: Text(
                  'Token: HA → Perfil de usuario → Tokens de larga duración (al final de la página)',
                  style: TextStyle(
                      color: Color(0xFF93c5fd), fontSize: 12, height: 1.5))),
            ]),
          ),

          const SizedBox(height: 28),

          // ── Probar conexión ──
          SizedBox(
            width: double.infinity, height: 50,
            child: OutlinedButton.icon(
              onPressed: _testing ? null : _test,
              icon: _testing
                  ? const SizedBox(width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: kBlue))
                  : const Icon(Icons.wifi_find_rounded, color: kBlue),
              label: Text(_testing ? 'Probando...' : 'Probar conexión',
                  style: const TextStyle(
                      color: kBlue, fontWeight: FontWeight.w600, fontSize: 15)),
              style: OutlinedButton.styleFrom(
                  foregroundColor: kBlue,
                  side: const BorderSide(color: kBlue),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14))),
            ),
          ),

          if (_testResult != null) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _testResult!.startsWith('✅')
                    ? kGreen.withOpacity(0.1)
                    : kRed.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: _testResult!.startsWith('✅')
                        ? kGreen.withOpacity(0.4)
                        : kRed.withOpacity(0.4)),
              ),
              child: Text(_testResult!,
                  style: TextStyle(
                      color: _testResult!.startsWith('✅') ? kGreen : kRed,
                      fontSize: 13,
                      fontWeight: FontWeight.w600)),
            ),
          ],

          const SizedBox(height: 20),

          // ── Copia de seguridad ──
          SectionCard(
            title: '💾 Copia de seguridad',
            surfaceColor: surfaceColor,
            textColor: textColor,
            children: [
              Row(children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _exportBackup,
                    icon: const Icon(Icons.download_rounded),
                    label: const Text('Exportar'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kBlue.withOpacity(0.2),
                      foregroundColor: kBlue,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _importBackup,
                    icon: const Icon(Icons.upload_rounded),
                    label: const Text('Importar'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kGreen.withOpacity(0.2),
                      foregroundColor: kGreen,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                  ),
                ),
              ]),
            ],
          ),

          const SizedBox(height: 16),

          // ── Guardar ──
          SizedBox(
            width: double.infinity, height: 54,
            child: ElevatedButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.save_rounded, color: Colors.white),
              label: Text(_saving ? 'Guardando...' : 'Guardar configuración',
                  style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white)),
              style: ElevatedButton.styleFrom(
                  backgroundColor: kBlue,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                  elevation: 0),
            ),
          ),
        ]),
      ),
    );
  }
}
