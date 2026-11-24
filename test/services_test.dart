// Versión 2026.11.17
// Pruebas de servicios: parseo de estados de HA, sensores y comparación de versiones
import 'package:flutter_test/flutter_test.dart';
import 'package:ha_alarm/models.dart';
import 'package:ha_alarm/services.dart';

void main() {
  group('sensorsFromAttr', () {
    test('acepta mapa (entidad: estado), lista y nulo', () {
      expect(sensorsFromAttr({'binary_sensor.a': 'open', 'binary_sensor.b': 'open'}),
          ['binary_sensor.a', 'binary_sensor.b']);
      expect(sensorsFromAttr(['binary_sensor.a']), ['binary_sensor.a']);
      expect(sensorsFromAttr(null), isEmpty);
    });
  });

  group('parseStateData', () {
    test('lee estado, delay y sensores abiertos', () {
      final d = parseStateData({
        'state': 'arming',
        'last_changed': '2026-11-23T12:00:00+00:00',
        'attributes': {
          'delay': 45,
          'open_sensors': {'binary_sensor.salon': 'open'},
        },
      });
      expect(d.state, AlarmState.arming);
      expect(d.delay, 45);
      expect(d.openSensors, ['binary_sensor.salon']);
    });

    test('tolera datos incompletos', () {
      final d = parseStateData({'state': 'disarmed'});
      expect(d.state, AlarmState.disarmed);
      expect(d.delay, isNull);
      expect(d.openSensors, isEmpty);
    });
  });

}
