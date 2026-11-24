// Versión 2026.11.17
// Pruebas de la copia de seguridad: una copia ajena no debe enviar tus credenciales a otro servidor
import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ha_alarm/services.dart';

const _almacen = FlutterSecureStorage();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({'ha_url': 'https://casa.example'});
    FlutterSecureStorage.setMockInitialValues({'ha_token': 'token-actual', 'ha_code': '1234'});
  });

  String copia(Map<String, dynamic> config) => jsonEncode({'config': config});

  test('si la copia cambia la URL sin credenciales, se borran las actuales', () async {
    final ok = await BackupService.import(copia({'url': 'https://otro.example'}));
    expect(ok, isTrue);
    expect(await _almacen.read(key: 'ha_token'), isNull);
    expect(await _almacen.read(key: 'ha_code'), isNull);
  });

  test('con la misma URL se conservan las credenciales', () async {
    await BackupService.import(copia({'url': 'https://casa.example', 'entity': 'alarm_control_panel.alarmo'}));
    expect(await _almacen.read(key: 'ha_token'), 'token-actual');
  });

  test('si la copia trae sus credenciales, se usan las suyas', () async {
    await BackupService.import(copia({'url': 'https://otro.example', 'token': 'nuevo', 'code': '9999'}));
    expect(await _almacen.read(key: 'ha_token'), 'nuevo');
    expect(await _almacen.read(key: 'ha_code'), '9999');
  });

  test('un fichero que no es JSON devuelve false y no toca nada', () async {
    expect(await BackupService.import('esto no es json'), isFalse);
    expect(await _almacen.read(key: 'ha_token'), 'token-actual');
  });
}
