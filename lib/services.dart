import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:dio/dio.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:vibration/vibration.dart';
import 'package:home_widget/home_widget.dart';
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
    if (res.statusCode != 200) throw Exception('Error ${res.statusCode}');

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
      throw Exception('Error ${res.statusCode}');
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
    } catch (_) {}
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

// ─── Servicio de Widget Android ───────────────────────────────
class WidgetService {
  static const _appGroupId  = 'com.homeassistant.ha_alarm';
  static const _widgetName  = 'AlarmWidget';

  // Actualiza los datos que el widget lee
  static Future<void> update(AlarmState state) async {
    try {
      final labels = {
        AlarmState.disarmed:   'Desarmada',
        AlarmState.armedAway:  'Armada',
        AlarmState.armedHome:  'Armada (Casa)',
        AlarmState.armedNight: 'Armada (Noche)',
        AlarmState.arming:     'Armando...',
        AlarmState.pending:    'Entrada...',
        AlarmState.triggered:  '¡ALARMA!',
        AlarmState.unknown:    'Sin conexión',
      };
      final now = DateTime.now();
      final hora = '${now.hour.toString().padLeft(2,'0')}:${now.minute.toString().padLeft(2,'0')}';

      await HomeWidget.saveWidgetData<String>('state_label', labels[state] ?? '—');
      await HomeWidget.saveWidgetData<String>('state_key',   state.name);
      await HomeWidget.saveWidgetData<String>('updated_at',  hora);
      await HomeWidget.updateWidget(
        androidName: _widgetName,
        qualifiedAndroidName: '$_appGroupId.$_widgetName',
      );
    } catch (_) {}
  }

  static Future<void> init() async {
    try {
      await HomeWidget.setAppGroupId(_appGroupId);
    } catch (_) {}
  }
}