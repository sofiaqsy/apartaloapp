import 'dart:convert';
import 'dart:io';

import 'package:apartalo_app/screens/elegir_pedido_comprobante_screen.dart';
import 'package:apartalo_app/services/api_service.dart';
import 'package:apartalo_app/services/comprobante_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  late Directory carpeta;
  final pedidos = <http.Request>[];

  setUp(() {
    pedidos.clear();
    carpeta = Directory.systemTemp.createTempSync('comprobante');
    dotenv.testLoad(fileInput: 'API_BASE_URL=https://api.test\nBUSINESS_ID=b1');
    ApiService.businessId = 'b1';
    ComprobanteService.leerTextoParaPruebas = (_) async => '¡Yapeaste!\nS/ 150\nNro. de operación\n12345678';
  });

  tearDown(() {
    ComprobanteService.leerTextoParaPruebas = null;
    if (carpeta.existsSync()) carpeta.deleteSync(recursive: true);
  });

  testWidgets('a shared comprobante lists the orders waiting for payment, the one with the same amount first', (tester) async {
    tester.view.physicalSize = const Size(1290, 2796); // the widest iPhone: the order card's row fits the test font
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final f = File('${carpeta.path}/compartido_1.jpg')..writeAsBytesSync([0xFF, 0xD8, 0xFF, 0xD9]);
    await http.runWithClient(() async {
      await tester.pumpWidget(MaterialApp(home: ElegirPedidoComprobanteScreen(imagen: f.path)));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pumpAndSettle();
    }, () => MockClient((req) async {
          pedidos.add(req);
          return http.Response(
              jsonEncode({
                'pedidos': [
                  {'id': 'PED-001', 'cliente': 'Café Lima', 'total': 300, 'montoPagado': 0},
                  {'id': 'PED-002', 'cliente': 'Café Cusco', 'total': 200, 'montoPagado': 50},
                ],
                'total': 2,
                'pagina': 1,
                'totalPaginas': 1,
              }),
              200);
        }));
    expect(pedidos.first.url.queryParameters['vista'], 'POR_COBRAR');
    expect(pedidos.first.url.queryParameters['limite'], '20');
    expect(find.text('¿De qué pedido es?'), findsOneWidget);
    expect(find.textContaining('Comprobante de S/ 150.00'), findsOneWidget);
    expect(find.text('Coincide el monto'), findsOneWidget);
    // Café Cusco (falta S/ 150) comes before Café Lima (falta S/ 300).
    expect(tester.getTopLeft(find.text('Café Cusco')).dy, lessThan(tester.getTopLeft(find.text('Café Lima')).dy));
    await tester.tap(find.byTooltip('Cerrar'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    expect(f.existsSync(), isFalse); // closing deletes the temporary copy
  });
}
