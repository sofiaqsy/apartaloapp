import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:apartalo_app/screens/tabs/clientes_tab.dart';
import 'package:apartalo_app/screens/tabs/pedidos_tab.dart';
import 'package:apartalo_app/screens/tabs/productos_tab.dart';

void main() {
  setUp(() {
    dotenv.testLoad(fileInput: 'API_BASE_URL=https://api.test\nBUSINESS_ID=BIZ-002');
    SharedPreferences.setMockInitialValues({});
  });

  // General Manager, 5 Nov 2026: the floating buttons covered the list over the keyboard while searching; first in
  // Pedidos, then "the same with Productos and Clientes".
  for (final (nombre, pantalla, botones) in [
    ('Pedidos', const PedidosTab(businessName: 'Finca Rosal') as Widget, ['Pre-venta', 'Nuevo Pedido']),
    ('Productos', const ProductosTab(), ['Nuevo']),
    ('Clientes', const ClientesTab(), ['Cotizar', 'Nuevo Cliente']),
  ]) {
    testWidgets('$nombre: ${botones.join(' and ')} hide while typing in Buscar and come back when the keyboard closes', (tester) async {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final cliente = MockClient((req) async =>
          http.Response(jsonEncode({'pedidos': [], 'productos': [], 'clientes': [], 'data': [], 'total': 0, 'success': true}), 200));
      await http.runWithClient(() async {
        await tester.pumpWidget(MaterialApp(home: pantalla));
        await tester.pump(const Duration(seconds: 1));
      }, () => cliente);
      for (final b in botones) {
        expect(find.text(b), findsOneWidget, reason: b);
      }

      await tester.tap(find.byType(TextField).first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500)); // the buttons leave with the Scaffold's own short animation
      for (final b in botones) {
        expect(find.text(b), findsNothing, reason: b);
      }

      FocusManager.instance.primaryFocus?.unfocus(); // the keyboard closes
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      for (final b in botones) {
        expect(find.text(b), findsOneWidget, reason: b);
      }
      await tester.pumpWidget(const SizedBox()); // stop the loading animation
    });
  }
}
