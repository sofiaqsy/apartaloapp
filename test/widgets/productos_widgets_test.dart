import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'dart:async';
import 'package:apartalo_app/screens/tabs/productos/widgets/nuevo_producto_fab.dart';
import 'package:apartalo_app/screens/tabs/productos/widgets/nuevo_producto_sheet.dart';
import 'package:apartalo_app/screens/tabs/productos/widgets/producto_list_card.dart';
import 'package:apartalo_app/theme/fincas_theme.dart';

Widget _app(Widget child, {double scale = 1.0}) => MaterialApp(
      theme: FincasTheme.light(),
      builder: (context, c) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)), child: c!),
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

Map<String, dynamic> _producto({String nombre = 'Café Rosal', bool tueste = false, List<Map<String, dynamic>>? pres}) => {
      'nombre': nombre,
      'pendingTueste': tueste,
      'presentaciones': pres ??
          [
            {'contenido': 250, 'unidad': 'g', 'precio': 32.5, 'stock': 12, 'predeterminada': true},
            {'contenido': 1000, 'unidad': 'g', 'precio': 110, 'stock': 3},
          ],
    };

void main() {
  group('NuevoProductoFab', () {
    Widget fab({required bool abriendo, required VoidCallback onPressed}) => MaterialApp(
          theme: FincasTheme.light(),
          home: Scaffold(floatingActionButton: NuevoProductoFab(abriendo: abriendo, onPressed: onPressed)),
        );

    testWidgets('idle: label only, no spinner, tap works', (t) async {
      var taps = 0;
      await t.pumpWidget(fab(abriendo: false, onPressed: () => taps++));
      expect(find.text('Nuevo producto'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await t.tap(find.text('Nuevo producto'));
      expect(taps, 1);
    });

    testWidgets('opening: a spinner and "Abriendo..." replace the label, and extra taps do nothing', (t) async {
      var taps = 0;
      await t.pumpWidget(fab(abriendo: true, onPressed: () => taps++));
      await t.pump(const Duration(milliseconds: 200)); // the spinner never settles
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Abriendo...'), findsOneWidget);
      expect(find.text('Nuevo producto'), findsNothing);
      await t.tap(find.text('Abriendo...'));
      expect(taps, 0);
      expect(find.bySemanticsLabel('Nuevo producto, abriendo'), findsOneWidget);
    });

    testWidgets('keeps the accent color while opening (it does not turn grey)', (t) async {
      await t.pumpWidget(fab(abriendo: true, onPressed: () {}));
      await t.pump(const Duration(milliseconds: 200)); // the spinner never settles
      final fabWidget = t.widget<FloatingActionButton>(find.byType(FloatingActionButton));
      expect(fabWidget.onPressed, isNotNull);
    });

    testWidgets('fits a 320pt screen at 2x text', (t) async {
      t.view.physicalSize = const Size(320 * 3, 640 * 3);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      await t.pumpWidget(MaterialApp(
        theme: FincasTheme.light(),
        builder: (context, c) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(2.0)), child: c!),
        home: Scaffold(floatingActionButton: NuevoProductoFab(abriendo: true, onPressed: () {})),
      ));
      await t.pump(const Duration(milliseconds: 200)); // the spinner never settles
      expect(t.takeException(), isNull);
    });
  });

  nuevoProductoSheetTests();
  test('presentation labels', () {
    expect(etiquetaPresentacion(250, 'g'), '250g');
    expect(etiquetaPresentacion(1000, 'g'), '1kg');
    expect(etiquetaPresentacion(1500, 'g'), '1.5kg');
    expect(etiquetaPresentacion(250, 'ml'), '250ml');
  });

  testWidgets('shows name, each presentation with price, and stock as text', (t) async {
    await t.pumpWidget(_app(ProductoListCard(producto: _producto(), onTap: () {})));
    expect(find.text('Café Rosal'), findsOneWidget);
    expect(find.text('250g'), findsOneWidget);
    expect(find.text('1kg'), findsOneWidget);
    expect(find.text('S/ 32.50'), findsOneWidget);
    expect(find.text('Stock 12'), findsOneWidget);
    expect(find.text('Stock bajo · 3'), findsOneWidget); // below 5: said in words, not only in color
  });

  testWidgets('pending roast is a text badge, absent otherwise', (t) async {
    await t.pumpWidget(_app(Column(children: [
      ProductoListCard(producto: _producto(tueste: true), onTap: () {}),
      ProductoListCard(producto: _producto(nombre: 'Otro'), onTap: () {}),
    ])));
    expect(find.text('Tueste pendiente'), findsOneWidget);
  });

  testWidgets('a product without presentations explains what to do', (t) async {
    await t.pumpWidget(_app(ProductoListCard(producto: _producto(pres: []), onTap: () {})));
    expect(find.text('Sin presentaciones. Toca para agregar.'), findsOneWidget);
  });

  testWidgets('tap works and the card has one accessible label', (t) async {
    var taps = 0;
    await t.pumpWidget(_app(ProductoListCard(producto: _producto(tueste: true), onTap: () => taps++)));
    await t.tap(find.byType(ProductoListCard));
    expect(taps, 1);
    expect(find.bySemanticsLabel('Café Rosal, tueste pendiente, 2 presentaciones'), findsOneWidget);
  });

  testWidgets('without an image the initial of the name is shown', (t) async {
    await t.pumpWidget(_app(ProductoListCard(producto: _producto(nombre: 'mnemonic'), onTap: () {})));
    expect(find.text('M'), findsOneWidget);
  });

  testWidgets('a very long name with many presentations fits 320pt at 2x text', (t) async {
    t.view.physicalSize = const Size(320 * 3, 640 * 3);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    final pres = [
      for (var i = 1; i <= 4; i++) {'contenido': 250 * i, 'unidad': 'g', 'precio': 1234.5 * i, 'stock': i, 'predeterminada': i == 1},
    ];
    await t.pumpWidget(_app(
      ProductoListCard(producto: _producto(nombre: 'Café de especialidad lavado de altura, lote microselección Villa Rica Oxapampa', tueste: true, pres: pres), onTap: () {}),
      scale: 2.0,
    ));
    expect(t.takeException(), isNull);
  });
}

// New product sheet: opens straight into manual entry, with nothing else to choose.
void nuevoProductoSheetTests() {
  late List<String> creados;

  Future<void> open(WidgetTester t, {Future<String?> Function(String)? onCrear}) async {
    creados = [];
    await t.pumpWidget(MaterialApp(
      theme: FincasTheme.light(),
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async {
              lastResult = await showNuevoProductoSheet(context, onCrear: onCrear ?? (n) async { creados.add(n); return null; });
            },
            child: const Text('abrir'),
          ),
        ),
      ),
    ));
    await t.tap(find.text('abrir'));
    await t.pumpAndSettle();
  }

  testWidgets('opens directly on the manual form: name, create and cancel only', (t) async {
    await open(t);
    expect(find.text('Nuevo producto'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Crear y configurar'), findsOneWidget);
    expect(find.text('Cancelar'), findsOneWidget);
    expect(find.text('Escanear código'), findsNothing);
    expect(find.text('Tomar foto'), findsNothing);
    expect(find.text('O agrégalo con'), findsNothing);
  });

  testWidgets('the sheet appears first; the keyboard is requested only after it has finished rising', (t) async {
    creados = [];
    await t.pumpWidget(MaterialApp(
      theme: FincasTheme.light(),
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(onPressed: () => showNuevoProductoSheet(context, onCrear: (n) async => null), child: const Text('abrir')),
        ),
      ),
    ));
    await t.tap(find.text('abrir'));
    await t.pump(); // first frame of the sheet
    expect(find.text('Nuevo producto'), findsOneWidget); // visible at once
    final campoNombre = t.widget<TextField>(find.byType(TextField));
    expect(campoNombre.autofocus, isFalse); // no keyboard request while building
    expect(campoNombre.focusNode!.hasFocus, isFalse);
    await t.pump(const Duration(milliseconds: 100));
    expect(campoNombre.focusNode!.hasFocus, isFalse); // still not asked while the sheet is rising
    await t.pump(const Duration(milliseconds: 400));
    expect(campoNombre.focusNode!.hasFocus, isTrue); // asked after it arrived
  });

  testWidgets('an empty name shows an inline message and does not call the server', (t) async {
    await open(t);
    await t.tap(find.text('Crear y configurar'));
    await t.pump();
    expect(find.text('Ingresa el nombre del producto'), findsOneWidget);
    expect(creados, isEmpty);
  });

  testWidgets('creating sends the trimmed name and closes the sheet with true', (t) async {
    await open(t);
    await t.enterText(find.byType(TextField), '  Café Blend  ');
    await t.tap(find.text('Crear y configurar'));
    await t.pumpAndSettle();
    expect(creados, ['Café Blend']);
    expect(lastResult, true);
    expect(find.text('Nuevo producto'), findsNothing);
  });

  testWidgets('while creating there is a loader and cancel cannot be tapped', (t) async {
    final done = Completer<String?>();
    await open(t, onCrear: (n) => done.future);
    await t.enterText(find.byType(TextField), 'Café');
    await t.tap(find.text('Crear y configurar'));
    await t.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await t.tap(find.text('Cancelar'), warnIfMissed: false);
    await t.pump();
    expect(find.text('Nuevo producto'), findsOneWidget); // still open
    done.complete(null);
    await t.pumpAndSettle();
    expect(lastResult, true);
  });

  testWidgets('a server error is shown under the field and the form is usable again', (t) async {
    await open(t, onCrear: (n) async => 'Ya existe un producto con ese nombre');
    await t.enterText(find.byType(TextField), 'Café');
    await t.tap(find.text('Crear y configurar'));
    await t.pumpAndSettle();
    expect(find.text('Ya existe un producto con ese nombre'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Nuevo producto'), findsOneWidget);
  });

  testWidgets('Cancelar closes without creating anything', (t) async {
    await open(t);
    await t.tap(find.text('Cancelar'));
    await t.pumpAndSettle();
    expect(creados, isEmpty);
    expect(lastResult, false);
  });

  testWidgets('fits a 320x568 phone at 2x text with the keyboard open', (t) async {
    t.view.physicalSize = const Size(320 * 3, 568 * 3);
    t.view.devicePixelRatio = 3;
    t.view.viewInsets = const FakeViewPadding(bottom: 260 * 3);
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
      theme: FincasTheme.light(),
      builder: (context, c) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(2.0)), child: c!),
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => showNuevoProductoSheet(context, onCrear: (n) async => null),
            child: const Text('abrir'),
          ),
        ),
      ),
    ));
    await t.tap(find.text('abrir'));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    expect(find.text('Nuevo producto'), findsOneWidget);
  });
}

bool? lastResult;
