import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:apartalo_app/screens/detalle_cliente_screen.dart';

// Client detail (General Manager, 5 Nov 2026): Pedidos in place of Estadísticas, and a PDF report with the same form as
// Administración (Mensual or Anual).
void main() {
  const id = '11111111-2222-3333-4444-555555555555';
  final pedidos = <http.Request>[];
  Map<String, dynamic> pedido(int n, String estado, num total, num pagado) =>
      {'id': 'ORD-$n', 'supabaseId': 'o$n', 'fecha': '${n + 1}/11/2026', 'estado': estado, 'total': total, 'montoPagado': pagado,
       'pagos': [], 'evidencias': [], 'productosDetalle': [], 'cliente': 'Café Cirilo'};

  Future<http.Response> responder(http.Request req) async {
    pedidos.add(req);
    final p = req.url.path;
    if (p.endsWith('/$id/pedidos')) {
      final desde = int.parse(req.url.queryParameters['offset'] ?? '0');
      final todos = [
        pedido(1, 'COMPLETADO', 800, 800),
        pedido(2, 'CONFIRMADO', 500, 200),
        pedido(3, 'CANCELADO', 300, 0),
        for (var i = 4; i <= 22; i++) pedido(i, 'PENDIENTE', 100, 0),
      ];
      return http.Response(jsonEncode({'pedidos': todos.skip(desde).take(20).toList(), 'total': todos.length, 'hayMas': desde + 20 < todos.length}), 200);
    }
    if (p.endsWith('/$id/reporte')) return http.Response(jsonEncode({'error': 'Sin señal'}), 503);
    if (p.endsWith('/addresses')) return http.Response(jsonEncode({'addresses': []}), 200);
    if (p.endsWith('/$id')) return http.Response(jsonEncode({'cliente': {'nombreNegocio': 'Café Cirilo'}}), 200);
    return http.Response(jsonEncode({}), 200);
  }

  setUp(() {
    pedidos.clear();
    dotenv.testLoad(fileInput: 'API_BASE_URL=https://api.test\nBUSINESS_ID=BIZ-002');
    SharedPreferences.setMockInitialValues({});
  });

  Future<void> abrir(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await http.runWithClient(() async {
      await tester.pumpWidget(const MaterialApp(home: DetalleClienteScreen(cliente: {'id': id, 'nombreNegocio': 'Café Cirilo', 'whatsapp': '999888777'})));
      await tester.pumpAndSettle();
    }, () => MockClient(responder));
  }

  testWidgets('Pedidos replaces Estadísticas: each order with its total and whether it is paid, 20 at a time', (tester) async {
    await abrir(tester);
    final lista = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(find.text('Pedido ORD-1'), 300, scrollable: lista);
    expect(find.text('Estadísticas'), findsNothing);
    expect(find.text('Pedidos'), findsOneWidget);
    for (final t in ['S/ 800 · Pagado', 'S/ 500 · Parcial · debe S/ 300', 'Completado', 'Cancelado']) {
      await tester.scrollUntilVisible(find.text(t), 200, scrollable: lista);
      expect(find.text(t), findsOneWidget, reason: t);
    }
    expect(find.text('S/ 300 · Sin pagar'), findsNothing); // a cancelled order says nothing about paying
    // Near the end, the next 20 come by themselves.
    await http.runWithClient(() async {
      await tester.scrollUntilVisible(find.text('Pedido ORD-22'), 400, scrollable: lista);
      await tester.pumpAndSettle();
    }, () => MockClient(responder));
    expect(pedidos.where((r) => r.url.path.endsWith('/pedidos')).map((r) => r.url.queryParameters['offset']), ['0', '20']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Generar reporte opens the Administración form and asks the client report for the chosen months', (tester) async {
    await abrir(tester);
    await tester.scrollUntilVisible(find.byTooltip('Generar reporte'), 300, scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await http.runWithClient(() async {
      await tester.tap(find.byTooltip('Generar reporte'));
      await tester.pumpAndSettle();
    }, () => MockClient(responder));
    for (final t in ['Generar reporte', 'Mensual', 'Anual', 'Generar PDF']) {
      expect(find.text(t), findsWidgets, reason: t);
    }
    expect(pedidos.any((r) => r.url.path.endsWith('/reporte')), isFalse); // only asked when Generar PDF is tapped
    await http.runWithClient(() async {
      await tester.tap(find.text('Generar PDF'));
      await tester.pumpAndSettle();
    }, () => MockClient(responder));
    final r = pedidos.lastWhere((r) => r.url.path.endsWith('/$id/reporte'));
    final hoy = DateTime.now();
    final mes = '${hoy.year}-${hoy.month.toString().padLeft(2, '0')}';
    expect(r.url.queryParameters, {'desde': mes, 'hasta': mes});
    expect(find.byType(SnackBar), findsOneWidget); // the error is said, nothing is left half done
  });
}
