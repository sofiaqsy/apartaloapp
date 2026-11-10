import 'dart:convert';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:apartalo_app/services/administracion_service.dart';
import 'package:apartalo_app/services/api_service.dart';

// Avisos por área (General Manager, 10 Nov 2026): the phone is saved with the person signed in, and removed on sign-out.
void main() {
  setUpAll(() => dotenv.testLoad(fileInput: 'API_BASE_URL=https://api.test\nBUSINESS_ID=b1'));

  test('the phone is saved for the push notifications of the person, and removed on sign-out', () async {
    ApiService.businessId = 'BIZ-002';
    final pedidos = <http.Request>[];
    await http.runWithClient(() async {
      expect(await AdministracionService.telefonoParaAvisos('fcm-token-123', plataforma: 'ios'), isTrue);
      expect(await AdministracionService.telefonoParaAvisos('fcm-token-123', quitar: true), isTrue);
    }, () => MockClient((req) async {
          pedidos.add(req);
          return http.Response(jsonEncode({'ok': true}), 200);
        }));
    expect(pedidos.map((r) => '${r.method} ${r.url.path}'), [
      'POST /api/administracion/BIZ-002/push-token',
      'DELETE /api/administracion/BIZ-002/push-token',
    ]);
    expect(jsonDecode(pedidos.first.body), {'token': 'fcm-token-123', 'platform': 'ios'});
    expect(jsonDecode(pedidos.last.body), {'token': 'fcm-token-123'});
  });

  test('without signal it says no, and nothing breaks', () async {
    await http.runWithClient(() async {
      expect(await AdministracionService.telefonoParaAvisos('fcm-token-123'), isFalse);
    }, () => MockClient((req) async => throw http.ClientException('sin señal')));
  });
}
