import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:apartalo_app/services/auth_client.dart';

void main() {
  late List<http.BaseRequest> seen;
  AuthClient build({String? host = 'api.example.com', Future<String?> Function()? token}) {
    seen = [];
    final inner = MockClient((req) async {
      seen.add(req);
      return http.Response('ok', 200);
    });
    return AuthClient(inner, backendHost: () => host, getToken: token ?? () async => 'TOKEN');
  }

  test('adds token and X-Client for the backend host', () async {
    await build().get(Uri.parse('https://api.example.com/api/pedidos/BIZ-002'));
    expect(seen.single.headers['Authorization'], 'Bearer TOKEN');
    expect(seen.single.headers['X-Client'], 'apartalo-app');
  });

  test('never sends the token to third parties', () async {
    final c = build();
    await c.get(Uri.parse('https://world.openfoodfacts.org/api/v0/product/1.json'));
    await c.get(Uri.parse('https://api.example.com.evil.com/x'));
    await c.get(Uri.parse('https://evil.com/api.example.com'));
    for (final r in seen) {
      expect(r.headers.containsKey('Authorization'), isFalse);
      expect(r.headers.containsKey('X-Client'), isFalse);
    }
  });

  test('never sends the token over plain http', () async {
    await build().get(Uri.parse('http://api.example.com/x'));
    expect(seen.single.headers.containsKey('Authorization'), isFalse);
  });

  test('keeps an Authorization header set by the caller', () async {
    await build().get(Uri.parse('https://api.example.com/x'), headers: {'Authorization': 'Bearer OTHER'});
    expect(seen.single.headers['Authorization'], 'Bearer OTHER');
  });

  test('no token or a failing token provider does not block the request', () async {
    await build(token: () async => null).get(Uri.parse('https://api.example.com/x'));
    expect(seen.single.headers.containsKey('Authorization'), isFalse);
    await build(token: () async => throw Exception('x')).get(Uri.parse('https://api.example.com/x'));
    expect(seen.single.headers.containsKey('Authorization'), isFalse);
    expect(seen.single.headers['X-Client'], 'apartalo-app');
  });

  test('unknown backend host (env not loaded) attaches nothing', () async {
    await build(host: null).get(Uri.parse('https://api.example.com/x'));
    expect(seen.single.headers.containsKey('Authorization'), isFalse);
  });
}
