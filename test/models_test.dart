// Versión 2026.11.8
// Pruebas de modelos: estados, zonas, configuración e historial (serialización)
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ha_alarm/models.dart';

void main() {
  group('parseState', () {
    test('reconoce todos los estados de Alarmo', () {
      expect(parseState('disarmed'), AlarmState.disarmed);
      expect(parseState('armed_away'), AlarmState.armedAway);
      expect(parseState('armed_home'), AlarmState.armedHome);
      expect(parseState('armed_night'), AlarmState.armedNight);
      expect(parseState('armed_custom_bypass'), AlarmState.armedCustomBypass);
      expect(parseState('arming'), AlarmState.arming);
      expect(parseState('pending'), AlarmState.pending);
      expect(parseState('triggered'), AlarmState.triggered);
    });

    test('un estado desconocido o unavailable es unknown', () {
      expect(parseState('unavailable'), AlarmState.unknown);
      expect(parseState(''), AlarmState.unknown);
    });
  });

  group('AlarmStateData', () {
    test('cuenta atrás solo en arming/pending con delay', () {
      final ahora = DateTime.now();
      expect(AlarmStateData(state: AlarmState.arming, lastChanged: ahora, delay: 45).hasCountdown, isTrue);
      expect(AlarmStateData(state: AlarmState.arming, lastChanged: ahora).hasCountdown, isFalse);
      expect(AlarmStateData(state: AlarmState.disarmed, lastChanged: ahora, delay: 45).hasCountdown, isFalse);
    });

    test('remaining nunca es negativo ni supera el delay', () {
      final viejo = DateTime.now().subtract(const Duration(seconds: 100));
      final d = AlarmStateData(state: AlarmState.arming, lastChanged: viejo, delay: 45);
      expect(d.remaining, 0);
    });

    test('toJson/fromJson conserva los datos', () {
      final original = AlarmStateData(
        state: AlarmState.pending,
        lastChanged: DateTime.utc(2026, 11, 23, 12, 0),
        delay: 30,
        openSensors: ['binary_sensor.puerta'],
      );
      final copia = AlarmStateData.fromJson(original.toJson());
      expect(copia.state, AlarmState.pending);
      expect(copia.delay, 30);
      expect(copia.openSensors, ['binary_sensor.puerta']);
    });
  });

  group('ZoneData.canArm', () {
    const def = ZoneDef(
        entityId: 'alarm_control_panel.planta_baja', label: 'Planta baja',
        short: 'PB', icon: Icons.home);

    test('solo si el robot la desarmó y sigue desarmada', () {
      expect(const ZoneData(def: def, state: AlarmState.disarmed, autoDisarmed: true).canArm, isTrue);
      expect(const ZoneData(def: def, state: AlarmState.disarmed, autoDisarmed: false).canArm, isFalse);
      expect(const ZoneData(def: def, state: AlarmState.armedAway, autoDisarmed: true).canArm, isFalse);
    });
  });

  group('Config', () {
    test('cleanDeviceName deja solo caracteres válidos para HA', () {
      expect(Config.cleanDeviceName('  Alfredo Móvil! '), 'alfredomvil');
      expect(Config.cleanDeviceName('mc-2_ok'), 'mc-2_ok');
      expect(Config.cleanDeviceName('a' * 40).length, 30);
    });

    test('isValid exige url, token y entidad', () {
      const base = Config(url: 'http://x', token: 't', entityId: 'e', code: '', updateUrl: '');
      expect(base.isValid, isTrue);
      expect(const Config(url: '', token: 't', entityId: 'e', code: '', updateUrl: '').isValid, isFalse);
    });
  });

  group('HistoryEntry', () {
    test('lee entradas antiguas sin zona ni robot', () {
      final e = HistoryEntry.fromJson({
        'state': 'disarmed',
        'timestamp': '2026-11-01T10:00:00.000',
      });
      expect(e.zone, isNull);
      expect(e.robot, isFalse);
    });

    test('toJson/fromJson conserva zona y robot', () {
      final e = HistoryEntry(
          state: AlarmState.disarmed, timestamp: DateTime(2026, 11, 23),
          zone: 'Planta alta', robot: true);
      final c = HistoryEntry.fromJson(e.toJson());
      expect(c.zone, 'Planta alta');
      expect(c.robot, isTrue);
      expect(c.state, AlarmState.disarmed);
    });
  });
}
