// Versión 2026.11.17
// Pruebas del historial: deduplicación por zona, marca de robot y límite
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ha_alarm/constants.dart';
import 'package:ha_alarm/models.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('no repite el mismo estado consecutivo de una misma zona', () async {
    await HistoryService.add(AlarmState.disarmed);
    await HistoryService.add(AlarmState.disarmed);
    expect((await HistoryService.load()).length, 1);
  });

  test('cada zona tiene su propia secuencia', () async {
    await HistoryService.add(AlarmState.disarmed);                          // maestro
    await HistoryService.add(AlarmState.disarmed, zone: 'Planta baja');     // zona
    await HistoryService.add(AlarmState.disarmed, zone: 'Planta baja');     // repetido
    final h = await HistoryService.load();
    expect(h.length, 2);
    expect(h.first.zone, 'Planta baja');
  });

  test('markRobot marca el último desarme de la zona', () async {
    await HistoryService.add(AlarmState.disarmed, zone: 'Planta alta');
    await HistoryService.markRobot('Planta alta');
    expect((await HistoryService.load()).first.robot, isTrue);
  });

  test('markRobot ignora zonas armadas', () async {
    await HistoryService.add(AlarmState.armedAway, zone: 'Planta alta');
    await HistoryService.markRobot('Planta alta');
    expect((await HistoryService.load()).first.robot, isFalse);
  });

  test('respeta el máximo de entradas', () async {
    for (var i = 0; i < kHistoryMaxSize + 10; i++) {
      // alterna estados para que no se deduplique
      await HistoryService.add(
          i.isEven ? AlarmState.armedAway : AlarmState.disarmed);
    }
    expect((await HistoryService.load()).length, kHistoryMaxSize);
  });
}
