import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:apartalo_app/screens/tabs/pedidos_tab.dart';

void main() {
  setUp(() {
    dotenv.testLoad(fileInput: 'API_BASE_URL=https://api.test\nBUSINESS_ID=BIZ-002');
    SharedPreferences.setMockInitialValues({});
  });

  // General Manager, 5 Nov 2026: the two floating buttons covered the list over the keyboard while searching.
  testWidgets('Pre-venta and Nuevo Pedido hide while typing in Buscar and come back when the keyboard closes', (tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final cliente = MockClient((req) async => http.Response(jsonEncode({'pedidos': [], 'total': 0, 'success': true}), 200));
    await http.runWithClient(() async {
      await tester.pumpWidget(const MaterialApp(home: PedidosTab(businessName: 'Finca Rosal')));
      await tester.pump(const Duration(seconds: 1));
    }, () => cliente);
    expect(find.text('Pre-venta'), findsOneWidget);
    expect(find.text('Nuevo Pedido'), findsOneWidget);

    await tester.tap(find.byType(TextField).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500)); // the buttons leave with the Scaffold's own short animation
    expect(find.text('Pre-venta'), findsNothing);
    expect(find.text('Nuevo Pedido'), findsNothing);

    FocusManager.instance.primaryFocus?.unfocus(); // the keyboard closes
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Pre-venta'), findsOneWidget);
    expect(find.text('Nuevo Pedido'), findsOneWidget);
    await tester.pumpWidget(const SizedBox()); // stop the loading animation
  });
}
