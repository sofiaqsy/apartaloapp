import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'dart:async';
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

// New product sheet: opens straight into manual entry; scan and photo stay one tap away.
void nuevoProductoSheetTests() {
  late List<String> creados;
  late int escanear;
  late int foto;

  Future<void> open(WidgetTester t, {Future<String?> Function(String)? onCrear}) async {
    creados = [];
    escanear = 0;
    foto = 0;
    await t.pumpWidget(MaterialApp(
      theme: FincasTheme.light(),
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async {
              lastResult = await showNuevoProductoSheet(
                context,
                onCrear: onCrear ?? (n) async { creados.add(n); return null; },
                onEscanear: () => escanear++,
                onFoto: () => foto++,
              );
            },
            child: const Text('abrir'),
          ),
        ),
      ),
    ));
    await t.tap(find.text('abrir'));
    await t.pumpAndSettle();
  }

  testWidgets('opens directly on the manual form, with scan and photo as secondary actions', (t) async {
    await open(t);
    expect(find.text('Nuevo producto'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Crear y configurar'), findsOneWidget);
    expect(find.text('Escanear código'), findsOneWidget);
    expect(find.text('Tomar foto'), findsOneWidget);
    expect(find.text('Cancelar'), findsOneWidget);
    expect(find.text('Elige cómo quieres agregar el producto'), findsNothing); // no extra step first
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

  testWidgets('while creating there is a loader and nothing else can be tapped', (t) async {
    final done = Completer<String?>();
    await open(t, onCrear: (n) => done.future);
    await t.enterText(find.byType(TextField), 'Café');
    await t.tap(find.text('Crear y configurar'));
    await t.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await t.tap(find.text('Escanear código'), warnIfMissed: false);
    await t.tap(find.text('Cancelar'), warnIfMissed: false);
    await t.pump();
    expect(escanear, 0);
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

  testWidgets('Escanear código: spinner at once, then the sheet closes and the scanner opens once', (t) async {
    await open(t);
    await t.tap(find.text('Escanear código'));
    await t.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(escanear, 0);
    await t.pumpAndSettle();
    expect((escanear, foto), (1, 0));
    expect(lastResult, false);
  });

  testWidgets('Tomar foto: spinner at once, then the camera flow opens once', (t) async {
    await open(t);
    await t.tap(find.text('Tomar foto'));
    await t.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await t.pumpAndSettle();
    expect((escanear, foto), (0, 1));
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
            onPressed: () => showNuevoProductoSheet(context, onCrear: (n) async => null, onEscanear: () {}, onFoto: () {}),
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
