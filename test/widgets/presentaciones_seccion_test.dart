import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:apartalo_app/models/producto_info.dart';
import 'package:apartalo_app/services/api_service.dart';
import 'package:apartalo_app/theme/fincas_theme.dart';
import 'package:apartalo_app/widgets/presentacion_tile.dart';
import 'package:apartalo_app/widgets/producto_presentaciones_ajustes.dart';

const _catalogos = CatalogosProducto(
  monedas: [
    OpcionMoneda(codigo: 'PEN', nombre: 'Sol peruano', simbolo: 'S/.'),
    OpcionMoneda(codigo: 'USD', nombre: 'Dólar estadounidense', simbolo: r'$'),
  ],
  lotesVerdes: [
    LoteVerdeOpcion(id: 'lote-2', etiqueta: 'L-2 · Obata · Finca Rosal · 2026 (195 kg disponibles)', kgDisponibles: 195),
    LoteVerdeOpcion(id: 'lote-3', etiqueta: 'L-3 · Caturra · 2025 (10 kg disponibles)', kgDisponibles: 10),
  ],
);

ProductoInfo _info({bool manual = false, String moneda = 'PEN', String? lote}) =>
    ProductoInfo(id: 'p1', nombre: 'Obata', stockManual: manual, moneda: moneda, loteVerdeId: lote);

class _H {
  Map<String, dynamic>? enviado;
  AjustesPresentaciones? ajustes;
  final dirty = <bool>[];
  Future<ApiResponse<ProductoInfo>> Function(Map<String, dynamic>)? respuesta;
}

Future<_H> _pump(WidgetTester t, {ProductoInfo? info, ApiResponse<ProductoInfoData>? carga, double scale = 1.0, Size? size}) async {
  final h = _H();
  if (size != null) {
    t.view.physicalSize = Size(size.width * 3, size.height * 3);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
  }
  final base = info ?? _info();
  await t.pumpWidget(MaterialApp(
    theme: FincasTheme.light(),
    builder: (context, c) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)), child: c!),
    home: Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: ProductoPresentacionesAjustes(
          productId: 'p1',
          onAjustes: (a) => h.ajustes = a,
          onDirtyChanged: h.dirty.add,
          cargar: (_) async => carga ?? ApiResponse.success(ProductoInfoData(producto: base, catalogos: _catalogos)),
          guardar: (_, cambios) async {
            h.enviado = cambios;
            if (h.respuesta != null) return h.respuesta!(cambios);
            return ApiResponse.success(ProductoInfo(
              id: 'p1',
              nombre: 'Obata',
              stockManual: cambios.containsKey('stockManual') ? cambios['stockManual'] as bool : base.stockManual,
              moneda: cambios.containsKey('moneda') ? cambios['moneda'] as String : base.moneda,
              loteVerdeId: cambios.containsKey('loteVerdeId') ? cambios['loteVerdeId'] as String? : base.loteVerdeId,
            ));
          },
        ),
      ),
    ),
  ));
  await t.pumpAndSettle();
  return h;
}

Finder _guardar() => find.widgetWithText(ElevatedButton, 'Guardar ajustes');

Presentacion _pres({double? b2b, int minimo = 1, bool pred = false, bool visible = true, List<String> molienda = const [], int stock = 12, String? imagen}) => Presentacion(
      id: 'pr1',
      contenido: 250,
      unidad: 'g',
      precio: 25,
      precioB2b: b2b,
      stock: stock,
      pedidoMinimo: minimo,
      orden: 0,
      predeterminada: pred,
      visible: visible,
      molienda: molienda,
      imageUrl: imagen,
    );

Widget _tile(Presentacion p, {VoidCallback? editar, VoidCallback? eliminar, String simbolo = 'S/', bool manual = false, double scale = 1.0}) => MaterialApp(
      theme: FincasTheme.light(),
      builder: (context, c) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)), child: c!),
      home: Scaffold(body: SingleChildScrollView(child: PresentacionTile(presentacion: p, onEditar: editar ?? () {}, onEliminar: eliminar ?? () {}, simboloMoneda: simbolo, stockManual: manual))),
    );

void main() {
  group('settings: stock manual, green lot, currency', () {
    testWidgets('shows the three settings with the explanations', (t) async {
      await _pump(t);
      expect(find.text('Stock manual'), findsOneWidget);
      expect(find.textContaining('ingresa el stock de cada presentación a mano'), findsOneWidget);
      expect(find.text('Lote verde a vender (presentación verde)'), findsOneWidget);
      expect(find.textContaining('descontarán 1:1 de este lote'), findsOneWidget);
      expect(find.text('Moneda'), findsOneWidget);
      expect(find.text('S/. — Sol peruano (PEN)'), findsOneWidget);
    });

    testWidgets('automatic stock explains where the stock comes from', (t) async {
      await _pump(t);
      expect(find.text('Stock automático'), findsOneWidget);
      expect(find.textContaining('se calcula desde los kg asignados en los tuestes'), findsOneWidget);
    });

    testWidgets('manual stock hides the automatic-stock box', (t) async {
      await _pump(t, info: _info(manual: true));
      expect(find.text('Stock automático'), findsNothing);
    });

    testWidgets('tells the screen the currency symbol and whether stock is manual', (t) async {
      final h = await _pump(t, info: _info(manual: true, moneda: 'USD'));
      expect(h.ajustes?.stockManual, true);
      expect(h.ajustes?.simboloMoneda, r'$');
    });

    testWidgets('the Save button appears only after a change and sends only the changed settings', (t) async {
      final h = await _pump(t);
      expect(_guardar(), findsNothing);
      await t.tap(find.byType(Switch));
      await t.pump();
      expect(h.dirty.last, true);
      expect(h.ajustes?.stockManual, true.not);
      await t.ensureVisible(_guardar());
      await t.tap(_guardar());
      await t.pumpAndSettle();
      expect(h.enviado, {'stockManual': true});
      expect(find.text('Ajustes guardados'), findsOneWidget);
      expect(h.ajustes?.stockManual, true);
      expect(h.dirty.last, false);
      expect(_guardar(), findsNothing);
    });

    testWidgets('choosing a lot and a currency are sent together', (t) async {
      final h = await _pump(t);
      await t.tap(find.text('Sin lote'));
      await t.pumpAndSettle();
      await t.tap(find.textContaining('L-2 · Obata').last);
      await t.pumpAndSettle();
      await t.tap(find.text('S/. — Sol peruano (PEN)'));
      await t.pumpAndSettle();
      await t.tap(find.textContaining('Dólar estadounidense').last);
      await t.pumpAndSettle();
      await t.ensureVisible(_guardar());
      await t.tap(_guardar());
      await t.pumpAndSettle();
      expect(h.enviado, {'loteVerdeId': 'lote-2', 'moneda': 'USD'});
    });

    testWidgets('a selected lot is shown, and "Sin lote" clears it', (t) async {
      final h = await _pump(t, info: _info(lote: 'lote-3'));
      expect(find.textContaining('L-3 · Caturra'), findsOneWidget);
      await t.tap(find.textContaining('L-3 · Caturra').first);
      await t.pumpAndSettle();
      await t.tap(find.text('Sin lote').last);
      await t.pumpAndSettle();
      await t.ensureVisible(_guardar());
      await t.tap(_guardar());
      await t.pumpAndSettle();
      expect(h.enviado, {'loteVerdeId': null});
    });

    testWidgets('a server error is shown and the edits are kept', (t) async {
      final h = await _pump(t);
      h.respuesta = (_) async => ApiResponse.error('La moneda no existe');
      await t.tap(find.byType(Switch));
      await t.pump();
      await t.ensureVisible(_guardar());
      await t.tap(_guardar());
      await t.pumpAndSettle();
      expect(find.text('La moneda no existe'), findsOneWidget);
      expect(_guardar(), findsOneWidget);
    });

    testWidgets('while saving the button shows a loader', (t) async {
      final done = Completer<ApiResponse<ProductoInfo>>();
      final h = await _pump(t);
      h.respuesta = (_) => done.future;
      await t.tap(find.byType(Switch));
      await t.pump();
      await t.ensureVisible(_guardar());
      await t.tap(_guardar());
      await t.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      done.complete(ApiResponse.success(_info(manual: true)));
      await t.pumpAndSettle();
    });

    testWidgets('a load error offers to retry and hides the controls', (t) async {
      await _pump(t, carga: ApiResponse.error('Error de conexión. Revisa tu internet.'));
      expect(find.text('No se pudieron cargar los ajustes'), findsOneWidget);
      expect(find.text('Reintentar'), findsOneWidget);
      expect(find.byType(Switch), findsNothing);
    });

    testWidgets('fits a 320x568 phone at 2x text with a very long lot description', (t) async {
      const largo = CatalogosProducto(
        monedas: [OpcionMoneda(codigo: 'PEN', nombre: 'Sol peruano', simbolo: 'S/.')],
        lotesVerdes: [LoteVerdeOpcion(id: 'lote-9', etiqueta: 'L-9 · Caturra + Obata + Typica + Geisha · Cooperativa Agraria Cafetalera Valle Alto Urubamba · 2026 (1200 kg disponibles)', kgDisponibles: 1200)],
      );
      await _pump(t, scale: 2.0, size: const Size(320, 568), carga: ApiResponse.success(ProductoInfoData(producto: _info(lote: 'lote-9'), catalogos: largo)));
      expect(t.takeException(), isNull);
    });
  });

  group('PresentacionTile', () {
    testWidgets('shows label, price, details and stock', (t) async {
      await t.pumpWidget(_tile(_pres(b2b: 22.5, minimo: 3, molienda: ['ground', 'whole'])));
      expect(find.text('250g'), findsOneWidget);
      expect(find.text('S/ 25.00'), findsOneWidget);
      expect(find.text('B2B S/ 22.50 · Pedido mínimo 3 · Molido, Grano'), findsOneWidget);
      expect(find.text('Stock: 12'), findsOneWidget);
    });

    testWidgets('uses the product currency symbol', (t) async {
      await t.pumpWidget(_tile(_pres(b2b: 20), simbolo: r'$'));
      expect(find.text(r'$ 25.00'), findsOneWidget);
      expect(find.textContaining(r'B2B $ 20.00'), findsOneWidget);
    });

    testWidgets('default and hidden-in-store are text badges', (t) async {
      await t.pumpWidget(_tile(_pres(pred: true, visible: false)));
      expect(find.text('Predeterminada'), findsOneWidget);
      expect(find.text('Oculta en tienda'), findsOneWidget);
    });

    testWidgets('a normal visible presentation has no badges', (t) async {
      await t.pumpWidget(_tile(_pres()));
      expect(find.text('Predeterminada'), findsNothing);
      expect(find.text('Oculta en tienda'), findsNothing);
    });

    testWidgets('minimum order of 1 is not repeated, and manual stock is labelled', (t) async {
      await t.pumpWidget(_tile(_pres(minimo: 1), manual: true));
      expect(find.textContaining('Pedido mínimo'), findsNothing);
      expect(find.text('Stock manual: 12'), findsOneWidget);
    });

    testWidgets('Editar and Eliminar call their actions', (t) async {
      var editar = 0, eliminar = 0;
      await t.pumpWidget(_tile(_pres(), editar: () => editar++, eliminar: () => eliminar++));
      await t.tap(find.text('Editar'));
      await t.tap(find.text('Eliminar'));
      expect((editar, eliminar), (1, 1));
    });

    testWidgets('fits 320pt at 2x text with every badge and detail', (t) async {
      t.view.physicalSize = const Size(320 * 3, 640 * 3);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      await t.pumpWidget(_tile(_pres(b2b: 22.5, minimo: 12, pred: true, visible: false, molienda: ['ground', 'whole', 'green']), scale: 2.0));
      expect(t.takeException(), isNull);
    });
  });
}

extension on bool {
  bool get not => !this;
}
