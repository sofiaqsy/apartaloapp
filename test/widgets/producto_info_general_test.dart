import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:apartalo_app/models/producto_info.dart';
import 'package:apartalo_app/services/api_service.dart';
import 'package:apartalo_app/theme/fincas_theme.dart';
import 'package:apartalo_app/widgets/producto_info_general.dart';

const _catalogos = CatalogosProducto(
  categorias: [OpcionCatalogo(id: 'cat-cafe', nombre: 'Café'), OpcionCatalogo(id: 'cat-cacao', nombre: 'Cacao')],
  variedades: [OpcionCatalogo(id: 'var-obata', nombre: 'Obata'), OpcionCatalogo(id: 'var-caturra', nombre: 'Caturra')],
  tuestes: [OpcionCatalogo(id: 'tue-claro', nombre: 'Claro')],
  procesos: [OpcionCatalogo(id: 'pro-lavado', nombre: 'Lavado')],
  secados: [OpcionCatalogo(id: 'sec-sol', nombre: 'Secado al sol')],
  notasSugeridas: ['Chocolate', 'Cítricos', 'Floral'],
);

ProductoInfo _info({String categoria = 'cat-cafe', List<String> notas = const ['Chocolate']}) => ProductoInfo(
      id: 'p1',
      nombre: 'Obata',
      descripcionBreve: 'Resumen',
      detalle: '',
      categoriaId: categoria,
      variedadId: 'var-obata',
      tuesteId: 'tue-claro',
      procesoId: 'pro-lavado',
      secadoId: 'sec-sol',
      notasSensoriales: notas,
    );

class _Harness {
  Map<String, dynamic>? enviado;
  ProductoInfo? guardado;
  final dirty = <bool>[];
  Future<ApiResponse<ProductoInfo>> Function(Map<String, dynamic>)? respuesta;
}

Future<_Harness> _pump(WidgetTester t, {ProductoInfo? info, ApiResponse<ProductoInfoData>? carga, double scale = 1.0, Size? size}) async {
  final h = _Harness();
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
        child: ProductoInfoGeneral(
          productId: 'p1',
          onDirtyChanged: h.dirty.add,
          onGuardado: (p) => h.guardado = p,
          cargar: (_) async => carga ?? ApiResponse.success(ProductoInfoData(producto: info ?? _info(), catalogos: _catalogos)),
          guardar: (_, cambios) async {
            h.enviado = cambios;
            if (h.respuesta != null) return h.respuesta!(cambios);
            // Echo the saved state back, like the server does.
            final i = info ?? _info();
            return ApiResponse.success(ProductoInfo(
              id: i.id,
              nombre: (cambios['nombre'] ?? i.nombre) as String,
              descripcionBreve: (cambios['descripcionBreve'] ?? i.descripcionBreve) as String,
              detalle: (cambios['detalle'] ?? i.detalle) as String,
              categoriaId: cambios.containsKey('categoriaId') ? cambios['categoriaId'] as String? : i.categoriaId,
              variedadId: cambios.containsKey('variedadId') ? cambios['variedadId'] as String? : i.variedadId,
              tuesteId: i.tuesteId,
              procesoId: i.procesoId,
              secadoId: i.secadoId,
              notasSensoriales: cambios.containsKey('notasSensoriales') ? List<String>.from(cambios['notasSensoriales'] as List) : i.notasSensoriales,
            ));
          },
        ),
      ),
    ),
  ));
  await t.pumpAndSettle();
  return h;
}

Finder campo(String etiqueta) => find.byWidgetPredicate((w) => w is TextField && w.decoration?.labelText == etiqueta);

void main() {
  testWidgets('shows the section with the product data and none of the excluded fields', (t) async {
    await _pump(t);
    expect(find.text('Información general'), findsOneWidget);
    expect(campo('Nombre del producto'), findsOneWidget);
    expect(campo('Descripción breve'), findsOneWidget);
    expect(campo('Detalle completo'), findsOneWidget);
    expect(find.text('Categoría'), findsOneWidget);
    expect(find.textContaining('nutricional'), findsNothing);
    expect(find.textContaining('URL'), findsNothing);
    expect(find.textContaining('/tienda'), findsNothing);
  });

  testWidgets('coffee attributes are shown for Café', (t) async {
    await _pump(t);
    expect(find.text('Atributos del café'), findsOneWidget);
    expect(find.text('Variedad'), findsOneWidget);
    expect(find.text('Tueste'), findsOneWidget);
    expect(find.text('Según el proceso'), findsOneWidget);
    expect(find.text('Técnica de secado'), findsOneWidget);
    expect(find.text('Análisis sensorial'), findsOneWidget);

  });

  testWidgets('coffee attributes are hidden for another category that has none', (t) async {
    const sinAtributos = ProductoInfo(id: 'p2', nombre: 'Cacao nibs', categoriaId: 'cat-cacao');
    await _pump(t, info: sinAtributos);
    expect(find.text('Atributos del café'), findsNothing);
    expect(find.text('Variedad'), findsNothing);
  });

  testWidgets('selected values are shown in the pickers', (t) async {
    await _pump(t);
    expect(find.text('Café'), findsOneWidget);
    expect(find.text('Obata'), findsWidgets);
    expect(find.text('Claro'), findsOneWidget);
    expect(find.text('Lavado'), findsOneWidget);
    expect(find.text('Secado al sol'), findsOneWidget);
    expect(find.widgetWithText(InputChip, 'Chocolate'), findsOneWidget);
  });

  testWidgets('Save is disabled until something changes, sends only the changed fields, then disables again', (t) async {
    final h = await _pump(t);
    final guardar = find.widgetWithText(ElevatedButton, 'Guardar información');
    expect(t.widget<ElevatedButton>(guardar).onPressed, isNull);

    await t.enterText(campo('Descripción breve'), 'Un resumen nuevo');
    await t.pump();
    expect(t.widget<ElevatedButton>(guardar).onPressed, isNotNull);
    expect(h.dirty.last, true);

    await t.ensureVisible(guardar);
    await t.tap(guardar);
    await t.pumpAndSettle();
    expect(h.enviado, {'descripcionBreve': 'Un resumen nuevo'});
    expect(find.text('Información guardada'), findsOneWidget);
    expect(h.guardado?.descripcionBreve, 'Un resumen nuevo');
    expect(t.widget<ElevatedButton>(guardar).onPressed, isNull);
    expect(h.dirty.last, false);
  });

  testWidgets('changing a value back to the original is not a change', (t) async {
    final h = await _pump(t);
    final desc = campo('Descripción breve');
    await t.enterText(desc, 'Otro');
    await t.pump();
    expect(h.dirty.last, true);
    await t.enterText(desc, 'Resumen');
    await t.pump();
    expect(h.dirty.last, false);
  });

  testWidgets('an empty name is refused before calling the server', (t) async {
    final h = await _pump(t);
    await t.enterText(campo('Nombre del producto'), '   ');
    await t.pump();
    final guardar = find.widgetWithText(ElevatedButton, 'Guardar información');
    await t.ensureVisible(guardar);
    await t.tap(guardar);
    await t.pump();
    expect(find.text('El nombre es obligatorio'), findsOneWidget);
    expect(h.enviado, isNull);
  });

  testWidgets('a server error is shown and the edits are kept', (t) async {
    final h = await _pump(t);
    h.respuesta = (_) async => ApiResponse.error('La descripción breve es muy larga');
    await t.enterText(campo('Descripción breve'), 'x');
    await t.pump();
    final guardar = find.widgetWithText(ElevatedButton, 'Guardar información');
    await t.ensureVisible(guardar);
    await t.tap(guardar);
    await t.pumpAndSettle();
    expect(find.text('La descripción breve es muy larga'), findsOneWidget);
    expect(t.widget<ElevatedButton>(guardar).onPressed, isNotNull);
    expect(find.text('x'), findsOneWidget);
  });

  testWidgets('while saving there is a loader on the button', (t) async {
    final done = Completer<ApiResponse<ProductoInfo>>();
    final h = await _pump(t);
    h.respuesta = (_) => done.future;
    await t.enterText(campo('Descripción breve'), 'x');
    await t.pump();
    final guardar = find.widgetWithText(ElevatedButton, 'Guardar información');
    await t.ensureVisible(guardar);
    await t.tap(guardar);
    await t.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    done.complete(ApiResponse.success(_info()));
    await t.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  group('sensory notes', () {
    testWidgets('a suggestion adds a chip and disappears from the suggestions', (t) async {
      final h = await _pump(t);
      final sugerencia = find.widgetWithText(ActionChip, 'Cítricos');
      await t.ensureVisible(sugerencia);
      await t.tap(sugerencia);
      await t.pump();
      expect(find.widgetWithText(InputChip, 'Cítricos'), findsOneWidget);
      expect(find.widgetWithText(ActionChip, 'Cítricos'), findsNothing);
      expect(h.dirty.last, true);
    });

    testWidgets('typing a note and pressing Enter adds it; duplicates (any case) are ignored', (t) async {
      await _pump(t);
      final entrada = find.byWidgetPredicate((w) => w is TextField && w.decoration?.hintText == 'Escribe una nota y presiona Enter o coma');
      await t.ensureVisible(entrada);
      await t.enterText(entrada, 'Mi nota propia');
      await t.testTextInput.receiveAction(TextInputAction.done);
      await t.pump();
      expect(find.widgetWithText(InputChip, 'Mi nota propia'), findsOneWidget);
      await t.enterText(entrada, 'chocolate');
      await t.testTextInput.receiveAction(TextInputAction.done);
      await t.pump();
      expect(find.widgetWithText(InputChip, 'Chocolate'), findsOneWidget);
      expect(find.widgetWithText(InputChip, 'chocolate'), findsNothing);
    });

    testWidgets('a comma confirms the note', (t) async {
      await _pump(t);
      final entrada = find.byWidgetPredicate((w) => w is TextField && w.decoration?.hintText == 'Escribe una nota y presiona Enter o coma');
      await t.ensureVisible(entrada);
      await t.enterText(entrada, 'Panela,');
      await t.pump();
      expect(find.widgetWithText(InputChip, 'Panela'), findsOneWidget);
    });

    testWidgets('removing a chip is saved as the new list', (t) async {
      final h = await _pump(t, info: _info(notas: ['Chocolate', 'Floral']));
      await t.ensureVisible(find.widgetWithText(InputChip, 'Floral'));
      await t.tap(find.byTooltip('Quitar Floral'));
      await t.pump();
      final guardar = find.widgetWithText(ElevatedButton, 'Guardar información');
      await t.ensureVisible(guardar);
      await t.tap(guardar);
      await t.pumpAndSettle();
      expect(h.enviado, {'notasSensoriales': ['Chocolate']});
    });

    testWidgets('no more than 12 notes can be added', (t) async {
      await _pump(t, info: _info(notas: [for (var i = 1; i <= 12; i++) 'Nota $i']));
      final entrada = find.byWidgetPredicate((w) => w is TextField && w.decoration?.hintText == 'Escribe una nota y presiona Enter o coma');
      await t.ensureVisible(entrada);
      await t.enterText(entrada, 'Una más');
      await t.testTextInput.receiveAction(TextInputAction.done);
      await t.pump();
      expect(find.text('Máximo 12 notas sensoriales'), findsOneWidget);
      expect(find.widgetWithText(InputChip, 'Una más'), findsNothing);
    });
  });

  testWidgets('a load error offers to retry', (t) async {
    await _pump(t, carga: ApiResponse.error('Error de conexión. Revisa tu internet.'));
    expect(find.text('No se pudo cargar'), findsOneWidget);
    expect(find.text('Reintentar'), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, 'Guardar información'), findsNothing);
  });

  testWidgets('fits a 320x568 phone at 2x text', (t) async {
    await _pump(t, scale: 2.0, size: const Size(320, 568), info: _info(notas: ['Chocolate', 'Cítricos', 'Floral', 'Una nota bastante larga de cata']));
    expect(t.takeException(), isNull);
  });
}
