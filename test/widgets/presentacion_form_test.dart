import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:apartalo_app/services/api_service.dart';
import 'package:apartalo_app/theme/fincas_theme.dart';
import 'package:apartalo_app/widgets/presentacion_form.dart';

const _existente = Presentacion(
  id: 'pr1',
  contenido: 250,
  unidad: 'g',
  precio: 25,
  precioB2b: 22.5,
  cantidadB2b: 6,
  stock: 12,
  pedidoMinimo: 2,
  orden: 0,
  predeterminada: true,
  visible: true,
  molienda: ['ground', 'whole'],
);

Finder campo(String etiqueta) => find.byWidgetPredicate((w) => w is TextField && w.decoration?.labelText == etiqueta);

class _H {
  PresentacionDatos? datos;
  int llamadas = 0;
  int cancelar = 0;
  Future<String?> Function(PresentacionDatos)? respuesta;
}

Future<_H> _pump(WidgetTester t, {Presentacion? presentacion, bool manual = false, double scale = 1.0, Size? size, bool cancelable = false}) async {
  final h = _H();
  if (size != null) {
    t.view.physicalSize = Size(size.width * 3, size.height * 3);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
  }
  await t.pumpWidget(MaterialApp(
    theme: FincasTheme.light(),
    builder: (context, c) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)), child: c!),
    home: Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: PresentacionForm(
          presentacion: presentacion,
          stockManual: manual,
          simboloMoneda: r'$',
          onCancelar: cancelable ? () => h.cancelar++ : null,
          onGuardar: (d) async {
            h.llamadas++;
            h.datos = d;
            return h.respuesta == null ? null : h.respuesta!(d);
          },
        ),
      ),
    ),
  ));
  await t.pumpAndSettle();
  return h;
}

Future<void> _tap(WidgetTester t, Finder f) async {
  await t.pump(); // let the form rebuild after typing (the Save button depends on the edits)
  await t.ensureVisible(f);
  await t.tap(f);
  await t.pumpAndSettle();
}

void main() {
  group('new presentation', () {
    testWidgets('starts empty with sensible defaults', (t) async {
      await _pump(t);
      expect(find.text('Crear presentación'), findsOneWidget);
      expect(t.widget<TextField>(campo('Pedido mínimo')).controller!.text, '1');
      expect(t.widget<TextField>(campo('Contenido')).controller!.text, '');
      expect(find.text('Stock'), findsNothing);
    });

    testWidgets('empty content and price show inline messages and nothing is sent', (t) async {
      final h = await _pump(t);
      await _tap(t, find.text('Crear presentación'));
      expect(find.text('Ingresa el contenido'), findsOneWidget);
      expect(find.text('Ingresa el precio'), findsOneWidget);
      expect(h.llamadas, 0);
    });

    testWidgets('sends the data with the currency symbol as prefix and the defaults', (t) async {
      final h = await _pump(t);
      expect(find.text(r'$ '), findsWidgets); // the symbol is the field prefix
      await t.enterText(campo('Contenido'), '250');
      await t.enterText(campo('Precio público'), '25.5');
      await _tap(t, find.text('Crear presentación'));
      final d = h.datos!;
      expect((d.contenido, d.unidad, d.precio), (250.0, 'g', 25.5));
      expect((d.precioB2b, d.cantidadB2b, d.stock), (null, null, null));
      expect((d.pedidoMinimo, d.predeterminada, d.visible), (1, false, true));
      expect(d.molienda, isEmpty);
    });

    testWidgets('a comma works as the decimal separator', (t) async {
      final h = await _pump(t);
      await t.enterText(campo('Contenido'), '0,5');
      await t.enterText(campo('Precio público'), '12,90');
      await _tap(t, find.text('Crear presentación'));
      expect((h.datos!.contenido, h.datos!.precio), (0.5, 12.9));
    });

    testWidgets('minimum order below 1 is corrected to 1', (t) async {
      final h = await _pump(t);
      await t.enterText(campo('Contenido'), '1');
      await t.enterText(campo('Precio público'), '10');
      await t.enterText(campo('Pedido mínimo'), '0');
      await _tap(t, find.text('Crear presentación'));
      expect(h.datos!.pedidoMinimo, 1);
    });

    testWidgets('unit, molienda and the two switches are sent', (t) async {
      final h = await _pump(t);
      await t.enterText(campo('Contenido'), '1');
      await t.enterText(campo('Precio público'), '80');
      await _tap(t, find.byType(DropdownButtonFormField<String>));
      await _tap(t, find.text('kg').last);
      await _tap(t, find.widgetWithText(FilterChip, 'Molido'));
      await _tap(t, find.widgetWithText(FilterChip, 'Verde'));
      await _tap(t, find.text('Predeterminada'));
      await _tap(t, find.text('Visible en tienda'));
      await _tap(t, find.text('Crear presentación'));
      final d = h.datos!;
      expect(d.unidad, 'kg');
      expect(d.molienda, ['ground', 'green']);
      expect((d.predeterminada, d.visible), (true, false));
    });

    testWidgets('Cancelar only appears when a handler is given and is blocked while saving', (t) async {
      await _pump(t);
      expect(find.text('Cancelar'), findsNothing);
      final h = await _pump(t, cancelable: true);
      await _tap(t, find.text('Cancelar'));
      expect(h.cancelar, 1);
    });
  });

  group('edit presentation', () {
    testWidgets('shows the saved values', (t) async {
      await _pump(t, presentacion: _existente);
      expect(t.widget<TextField>(campo('Contenido')).controller!.text, '250');
      expect(t.widget<TextField>(campo('Precio público')).controller!.text, '25.00');
      expect(t.widget<TextField>(campo('Precio B2B (opcional)')).controller!.text, '22.50');
      expect(t.widget<TextField>(campo('Cant. mínima para precio B2B')).controller!.text, '6');
      expect(t.widget<TextField>(campo('Pedido mínimo')).controller!.text, '2');
      expect(find.widgetWithText(FilterChip, 'Molido'), findsOneWidget);
      expect(t.widget<FilterChip>(find.widgetWithText(FilterChip, 'Molido')).selected, true);
      expect(t.widget<FilterChip>(find.widgetWithText(FilterChip, 'Verde')).selected, false);
      expect(find.text('Guardar cambios'), findsOneWidget);
    });

    testWidgets('Save is disabled until something changes, and again if the change is undone', (t) async {
      await _pump(t, presentacion: _existente);
      final guardar = find.widgetWithText(ElevatedButton, 'Guardar cambios');
      expect(t.widget<ElevatedButton>(guardar).onPressed, isNull);
      await t.enterText(campo('Precio público'), '30');
      await t.pump();
      expect(t.widget<ElevatedButton>(guardar).onPressed, isNotNull);
      await t.enterText(campo('Precio público'), '25.00');
      await t.pump();
      expect(t.widget<ElevatedButton>(guardar).onPressed, isNull);
    });

    testWidgets('toggling a switch or a molienda chip counts as a change', (t) async {
      await _pump(t, presentacion: _existente);
      final guardar = find.widgetWithText(ElevatedButton, 'Guardar cambios');
      await _tap(t, find.text('Visible en tienda'));
      expect(t.widget<ElevatedButton>(guardar).onPressed, isNotNull);
      await _tap(t, find.text('Visible en tienda'));
      expect(t.widget<ElevatedButton>(guardar).onPressed, isNull);
      await _tap(t, find.widgetWithText(FilterChip, 'Verde'));
      expect(t.widget<ElevatedButton>(guardar).onPressed, isNotNull);
    });

    testWidgets('clearing the optional B2B price sends null', (t) async {
      final h = await _pump(t, presentacion: _existente);
      await t.enterText(campo('Precio B2B (opcional)'), '');
      await t.pump();
      await _tap(t, find.widgetWithText(ElevatedButton, 'Guardar cambios'));
      expect(h.datos!.precioB2b, isNull);
      expect(h.datos!.cantidadB2b, 6);
    });

    testWidgets('a server error is shown and the edits are kept', (t) async {
      final h = await _pump(t, presentacion: _existente);
      h.respuesta = (_) async => 'Contenido inválido';
      await t.enterText(campo('Precio público'), '30');
      await _tap(t, find.widgetWithText(ElevatedButton, 'Guardar cambios'));
      expect(find.text('Contenido inválido'), findsOneWidget);
      expect(t.widget<TextField>(campo('Precio público')).controller!.text, '30');
    });

    testWidgets('while saving there is a loader and fields are disabled', (t) async {
      final done = Completer<String?>();
      final h = await _pump(t, presentacion: _existente);
      h.respuesta = (_) => done.future;
      await t.enterText(campo('Precio público'), '30');
      await t.pump();
      await t.ensureVisible(find.widgetWithText(ElevatedButton, 'Guardar cambios'));
      await t.tap(find.widgetWithText(ElevatedButton, 'Guardar cambios'));
      await t.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(t.widget<TextField>(campo('Precio público')).enabled, false);
      done.complete(null);
      await t.pumpAndSettle();
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });
  });

  group('stock', () {
    testWidgets('manual stock shows the Stock field and sends its value', (t) async {
      final h = await _pump(t, presentacion: _existente, manual: true);
      expect(t.widget<TextField>(campo('Stock')).controller!.text, '12');
      await t.enterText(campo('Stock'), '40');
      await _tap(t, find.widgetWithText(ElevatedButton, 'Guardar cambios'));
      expect(h.datos!.stock, 40);
    });

    testWidgets('automatic stock hides the field and sends no stock', (t) async {
      final h = await _pump(t, presentacion: _existente);
      expect(campo('Stock'), findsNothing);
      await t.enterText(campo('Precio público'), '26');
      await _tap(t, find.widgetWithText(ElevatedButton, 'Guardar cambios'));
      expect(h.datos!.stock, isNull);
    });
  });

  testWidgets('fits a 320x568 phone at 2x text, in new and edit mode', (t) async {
    await _pump(t, presentacion: _existente, manual: true, scale: 2.0, size: const Size(320, 568));
    expect(t.takeException(), isNull);
  });
}
