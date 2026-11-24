// Versión 2026.11.17
// Pruebas del controlador: zonas, marcas de robot, resumen del widget, aviso e historial
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ha_alarm/controller.dart';
import 'package:ha_alarm/models.dart';

const _pb   = 'alarm_control_panel.planta_baja';
const _marca = 'input_boolean.robots_alarma_desarmada_auto_planta_baja';

Map<String, dynamic> _est(String estado) => {'state': estado, 'attributes': <String, dynamic>{}};

AlarmController _nuevo(AlarmState maestro) {
  final c = AlarmController();
  c.setConfigForTest(const Config(
      url: 'https://ha.example', token: 't', entityId: 'alarm_control_panel.alarmo', code: ''));
  c.setStateForTest(AlarmStateData(state: maestro, lastChanged: DateTime.now()));
  return c;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // El controlador avisa al widget nativo por este canal; en las pruebas no existe
  setUpAll(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
          const MethodChannel('es.fernandezbadia.alarmacasa/widget'), (_) async => null));
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('una zona desarmada por el robot se puede armar', () {
    final c = _nuevo(AlarmState.armedAway);
    c.onWsEntityForTest(_marca, _est('off'));
    c.onWsEntityForTest(_pb, _est('armed_away'));
    expect(c.robotZones, isEmpty);

    c.onWsEntityForTest(_pb, _est('disarmed'));
    c.onWsEntityForTest(_marca, _est('on'));
    expect(c.robotZones.map((z) => z.def.label), ['Planta baja']);
    expect(c.robotZones.single.canArm, isTrue);
    c.dispose();
  });

  test('el resumen del widget solo lista zonas distintas del maestro', () {
    final c = _nuevo(AlarmState.armedAway);
    c.onWsEntityForTest('alarm_control_panel.perimetro', _est('armed_away'));
    c.onWsEntityForTest(_marca, _est('off'));
    c.onWsEntityForTest(_pb, _est('disarmed'));
    c.onWsEntityForTest(_marca, _est('on'));
    expect(c.zonesSummaryForTest(), '🤖 PB desarmada');
    c.dispose();
  });

  test('avisa una sola vez si el robot desarma una zona al armar', () {
    final c = _nuevo(AlarmState.arming);
    c.onWsEntityForTest(_marca, _est('off'));
    c.onWsEntityForTest(_marca, _est('on'));
    expect(c.takeAviso(), contains('Planta baja'));
    expect(c.takeAviso(), isNull);
    c.dispose();
  });

  test('no avisa si el maestro está desarmado', () {
    final c = _nuevo(AlarmState.disarmed);
    c.onWsEntityForTest(_marca, _est('off'));
    c.onWsEntityForTest(_marca, _est('on'));
    expect(c.takeAviso(), isNull);
    c.dispose();
  });

  test('el historial marca como de robot el desarme de la zona', () async {
    final c = _nuevo(AlarmState.armedAway);
    c.onWsEntityForTest(_marca, _est('off'));
    c.onWsEntityForTest(_pb, _est('armed_away')); // primera lectura: no se anota
    c.onWsEntityForTest(_pb, _est('disarmed'));
    c.onWsEntityForTest(_marca, _est('on'));
    await Future.delayed(const Duration(milliseconds: 200)); // las escrituras son asíncronas
    final h = await HistoryService.load();
    final zona = h.where((e) => e.zone == 'Planta baja').toList();
    expect(zona.length, 1);
    expect(zona.single.state, AlarmState.disarmed);
    expect(zona.single.robot, isTrue);
    c.dispose();
  });
}
