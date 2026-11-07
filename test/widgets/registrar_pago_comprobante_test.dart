import 'dart:convert';
import 'dart:io';

import 'package:apartalo_app/screens/registrar_pago_comprobante_screen.dart';
import 'package:apartalo_app/services/api_service.dart';
import 'package:apartalo_app/services/comprobante_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

void main() {
  late Directory carpeta;
  final pedido = {'id': 'PED-001', 'cliente': 'Café Lima', 'total': 150.0};

  setUp(() {
    carpeta = Directory.systemTemp.createTempSync('comprobante');
    dotenv.testLoad(fileInput: 'API_BASE_URL=https://api.test\nBUSINESS_ID=b1');
    ApiService.businessId = 'b1';
    ComprobanteService.leerTextoParaPruebas = (_) async => '¡Yapeaste!\nS/ 150\nNro. de operación\n12345678';
  });

  tearDown(() {
    ComprobanteService.leerTextoParaPruebas = null;
    if (carpeta.existsSync()) carpeta.deleteSync(recursive: true);
  });

  File imagen() => File('${carpeta.path}/compartido_1.jpg')..writeAsBytesSync([0xFF, 0xD8, 0xFF, 0xD9]);

  Future<void> abrir(WidgetTester tester, Widget pantalla) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => pantalla)),
            child: const Text('abrir'),
          ),
        ),
      ),
    )));
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
  }

  testWidgets('a shared comprobante fills the amount and shows the operation number; Guardar sends both with the photo', (tester) async {
    final f = imagen();
    (double, File?, String?)? enviado;
    await abrir(
        tester,
        RegistrarPagoComprobanteScreen(
          pedido: pedido,
          montoPagado: 0,
          imagen: f.path,
          guardar: (m, i, o) async {
            enviado = (m, i, o);
            return null;
          },
        ));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    expect(find.text('Registrar Pago'), findsOneWidget);
    expect(find.text('Monto S/ 150.00 · Nº de operación 12345678'), findsOneWidget);
    expect(find.widgetWithText(TextField, '150.00'), findsOneWidget);
    expect(find.text('Leído del comprobante: revísalo'), findsOneWidget);
    expect(find.text('Completa el pedido'), findsOneWidget);
    // The operation number is read, never asked: there is no field for it.
    expect(find.widgetWithText(TextField, '12345678'), findsNothing);

    await tester.tap(find.text('Confirmar'));
    await tester.pumpAndSettle();
    expect(enviado!.$1, 150);
    expect(enviado!.$2!.path, f.path);
    expect(enviado!.$3, '12345678');
    expect(find.text('Registrar Pago'), findsNothing); // closed after saving
    expect(f.existsSync(), isFalse); // the temporary copy is gone
  });

  testWidgets('closing without saving saves nothing and deletes the temporary copy', (tester) async {
    final f = imagen();
    var llamadas = 0;
    await abrir(
        tester,
        RegistrarPagoComprobanteScreen(
          pedido: pedido,
          montoPagado: 0,
          imagen: f.path,
          guardar: (m, i, o) async {
            llamadas++;
            return null;
          },
        ));
    await tester.tap(find.byTooltip('Cerrar'));
    await tester.pumpAndSettle();
    expect(llamadas, 0);
    expect(f.existsSync(), isFalse);
  });

  testWidgets('without a photo it works as before: the amount left, and the error right above Guardar', (tester) async {
    await abrir(
        tester,
        RegistrarPagoComprobanteScreen(
          pedido: pedido,
          montoPagado: 100,
          guardar: (m, i, o) async => 'No se guardó el pago: revisa la señal e inténtalo de nuevo.',
        ));
    expect(find.text('Registrar Abono'), findsOneWidget);
    expect(find.text('Tomar foto'), findsOneWidget);
    expect(find.text('Elegir foto'), findsOneWidget);
    expect(find.widgetWithText(TextField, '50.00'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '20');
    await tester.pump();
    expect(find.text('Falta S/ 30.00 después de este pago'), findsOneWidget);
    await tester.tap(find.text('Confirmar'));
    await tester.pumpAndSettle();
    final error = tester.getBottomLeft(find.text('No se guardó el pago: revisa la señal e inténtalo de nuevo.')).dy;
    final guardar = tester.getTopLeft(find.text('Confirmar')).dy;
    expect(guardar - error, lessThan(30));
  });

  test('saving uploads the photo first, then the payment with the operation number, then joins the photo to it', () async {
    final f = imagen();
    final orden = <String>[];
    Map<String, dynamic>? pagoEnviado;
    Map<String, dynamic>? evidenciaEnviada;
    final (error, datos) = await http.runWithClient(
      () => registrarPagoPedido(
          pedido: pedido, montoPagado: 0, pagosAntes: const [], monto: 150, imagen: f, operacion: '12345678'),
      () => MockClient((req) async {
        final ruta = req.url.path;
        if (ruta.endsWith('/sign')) {
          orden.add('sign');
          return http.Response(jsonEncode({'signedUrl': 'https://almacen.test/subir', 'publicUrl': 'https://almacen.test/c.jpg'}), 200);
        }
        if (req.url.host == 'almacen.test') {
          orden.add('subir');
          return http.Response('', 200);
        }
        if (req.method == 'PUT' && ruta.endsWith('/PED-001')) {
          orden.add('pago');
          pagoEnviado = jsonDecode(req.body) as Map<String, dynamic>;
          return http.Response(jsonEncode({'estadoPago': 'PAGADO', 'montoPagado': 150, 'pagos': [{'id': 'pay-9', 'monto': 150}]}), 200);
        }
        if (ruta.endsWith('/PED-001/evidencias')) {
          orden.add('comprobante');
          evidenciaEnviada = jsonDecode(req.body) as Map<String, dynamic>;
          return http.Response(jsonEncode({'success': true, 'evidencia': {'id': 'e1', 'url': 'https://almacen.test/c.jpg'}}), 200);
        }
        return http.Response('{}', 404);
      }),
    );
    expect(error, isNull);
    expect(orden, ['sign', 'subir', 'pago', 'comprobante']);
    expect(pagoEnviado!['nuevoPago'], 150);
    expect(pagoEnviado!['estadoPago'], 'PAGADO');
    expect('${pagoEnviado!['notaPago']}', contains('12345678'));
    expect(evidenciaEnviada!['paymentId'], 'pay-9');
    expect(evidenciaEnviada!['url'], 'https://almacen.test/c.jpg');
    expect(datos!['sinComprobante'], isNull);
  });

  test('if the photo does not upload, nothing is saved', () async {
    final f = imagen();
    var pagos = 0;
    final (error, _) = await http.runWithClient(
      () => registrarPagoPedido(pedido: pedido, montoPagado: 0, pagosAntes: const [], monto: 150, imagen: f),
      () => MockClient((req) async {
        if (req.url.path.endsWith('/sign')) return http.Response(jsonEncode({'error': 'sin señal'}), 500);
        pagos++;
        return http.Response('{}', 200);
      }),
    );
    expect(error, contains('No se guardó nada'));
    expect(pagos, 0);
  });
}
