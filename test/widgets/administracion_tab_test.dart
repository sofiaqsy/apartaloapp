import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:apartalo_app/screens/tabs/administracion_tab.dart';
import 'package:apartalo_app/services/administracion_service.dart';

void main() {
  final pedidos = <http.Request>[];

  http.Response responder(http.Request req) {
    pedidos.add(req);
    final p = req.url.path;
    if (p.endsWith('/pendientes')) {
      return http.Response(jsonEncode({
        'sinPrecio': [{'id': 'DL-0001', 'kg': 100, 'farmer_id': 'P-J', 'delivery_date': '2026-11-03'}],
        'porPagar': [{'id': 'PU-0001', 'still_owed': 300, 'farmer_id': 'P-J', 'purchase_date': '2026-11-04'}],
        'adelantos': [{'id': 'ADV-002', 'party_id': 'P-MIS', 'open_balance': 1500, 'advance_date': '2026-11-02'}],
        'banco': [],
      }), 200);
    }
    if (p.endsWith('/personas')) return http.Response('[]', 200);
    if (p.endsWith('/resumen')) return http.Response(jsonEncode({'rol': 'owner', 'meses': []}), 200);
    if (p.contains('/registrar/')) return http.Response(jsonEncode({'ok': true, 'result': {'expense_id': 'EX-0001'}}), 200);
    return http.Response(jsonEncode({'pedidos': [], 'total': 0}), 200);
  }

  setUp(() {
    pedidos.clear();
    dotenv.testLoad(fileInput: 'API_BASE_URL=https://api.test\nBUSINESS_ID=BIZ-002');
  });

  Future<void> abrir(WidgetTester tester, {required String rol}) async {
    // An iPhone-sized screen (390 x 844 points).
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({'business_role': rol});
    await http.runWithClient(() async {
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: AdministracionTab())));
      await tester.pumpAndSettle();
    }, () => MockClient((req) async => responder(req)));
  }

  testWidgets('three parts and the registrar buttons; staff cannot open Adelanto', (tester) async {
    await abrir(tester, rol: 'staff');
    expect(find.text('Administración'), findsOneWidget);
    for (final t in ['Registrar', 'Pendientes', 'Resumen']) {
      expect(find.text(t), findsOneWidget);
    }
    expect(find.text('Gasto'), findsOneWidget);
    expect(find.text('Adelanto (sólo dueño)'), findsOneWidget);
    await tester.tap(find.text('Adelanto (sólo dueño)'));
    await tester.pumpAndSettle();
    expect(find.text('Guardar'), findsNothing); // the form did not open
  });

  testWidgets('the expense form asks for what is missing before sending anything', (tester) async {
    await abrir(tester, rol: 'owner');
    await http.runWithClient(() async {
      await tester.tap(find.text('Gasto'));
      await tester.pumpAndSettle();
      expect(find.text('Guardar'), findsOneWidget);
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
    }, () => MockClient((req) async => responder(req)));
    expect(find.textContaining('Falta: Monto (S/), Categoría, Número de operación'), findsOneWidget);
    expect(pedidos.where((r) => r.url.path.contains('/registrar/')), isEmpty);
  });

  testWidgets('the expense form is short: amount first with the keyboard open, rare fields under Más opciones', (tester) async {
    await abrir(tester, rol: 'owner');
    await tester.tap(find.text('Gasto'));
    await tester.pumpAndSettle();
    final monto = tester.widget<EditableText>(find.byType(EditableText).first);
    expect(monto.focusNode.hasFocus, isTrue); // amount field focused, number keyboard up
    expect(find.text('Más opciones'), findsOneWidget);
    expect(find.textContaining('Fecha: hoy'), findsOneWidget);
    expect(find.byType(ChoiceChip), findsWidgets); // categories and payment method are buttons to tap
    expect(find.text('Área'), findsNothing); // inside Más opciones until opened
  });

  testWidgets('tapping outside a field hides the keyboard', (tester) async {
    await abrir(tester, rol: 'owner');
    await tester.tap(find.text('Gasto'));
    await tester.pumpAndSettle();
    bool tecladoAbierto() => tester.widget<EditableText>(find.byType(EditableText).first).focusNode.hasFocus;
    expect(tecladoAbierto(), isTrue);
    await tester.tapAt(const Offset(195, 700)); // empty part of the screen
    await tester.pumpAndSettle();
    expect(tecladoAbierto(), isFalse);
  });

  testWidgets('the X closes the form without saving', (tester) async {
    await abrir(tester, rol: 'owner');
    await tester.tap(find.text('Gasto'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Cancelar'));
    await tester.pumpAndSettle();
    expect(find.text('Guardar'), findsNothing);
    expect(find.text('Registrar'), findsOneWidget);
    expect(pedidos.where((r) => r.url.path.contains('/registrar/')), isEmpty);
  });

  testWidgets('pendientes lists what waits for a price, a payment and open advances', (tester) async {
    await abrir(tester, rol: 'owner');
    await http.runWithClient(() async {
      await tester.tap(find.text('Pendientes'));
      await tester.pumpAndSettle();
    }, () => MockClient((req) async => responder(req)));
    expect(find.text('Sin precio (1)'), findsOneWidget);
    expect(find.text('Por pagar (1)'), findsOneWidget);
    expect(find.textContaining('ADV-002'), findsOneWidget);
    expect(find.text('Banco por cruzar (0)'), findsOneWidget);
  });

  test('each send has its own retry key, long enough for the database', () {
    final a = AdministracionService.nuevaClave('gasto');
    final b = AdministracionService.nuevaClave('gasto');
    expect(a, isNot(b));
    expect(a.length, inInclusiveRange(8, 80));
  });

  test('a form sends to the business route with the retry key', () async {
    await http.runWithClient(() async {
      final r = await AdministracionService.registrar('gasto', {'monto': 80}, clave: 'gasto-123-abcdefgh');
      expect(r.isSuccess, isTrue);
    }, () => MockClient((req) async => responder(req)));
    final req = pedidos.single;
    expect(req.url.toString(), 'https://api.test/api/administracion/BIZ-002/registrar/gasto');
    expect(jsonDecode(req.body), {'monto': 80, 'clientRef': 'gasto-123-abcdefgh'});
  });
}
