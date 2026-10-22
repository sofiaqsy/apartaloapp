import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:apartalo_app/screens/tabs/productos/widgets/agregar_producto_sheet.dart';
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
  agregarSheetTests();
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

// Sheet: tap feedback while the camera or the form is opening.
void agregarSheetTests() {
  Future<List<int>> open(WidgetTester t, {Duration pausa = const Duration(milliseconds: 150)}) async {
    final calls = [0, 0, 0];
    await t.pumpWidget(MaterialApp(
      theme: FincasTheme.light(),
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => showAgregarProductoSheet(
              context,
              pausa: pausa,
              onEscanear: () => calls[0]++,
              onFoto: () => calls[1]++,
              onManual: () => calls[2]++,
            ),
            child: const Text('abrir'),
          ),
        ),
      ),
    ));
    await t.tap(find.text('abrir'));
    await t.pumpAndSettle();
    return calls;
  }

  testWidgets('tapping an option shows a loader at once, then closes the sheet and runs the action once', (t) async {
    final calls = await open(t);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await t.tap(find.text('Tomar foto del producto'));
    await t.pump(); // first frame after the tap
    expect(find.byType(CircularProgressIndicator), findsOneWidget); // feedback before anything else opens
    expect(find.text('Abriendo...'), findsOneWidget);
    expect(calls, [0, 0, 0]); // the action waits until the indicator has been painted
    await t.pumpAndSettle();
    expect(calls, [0, 1, 0]);
    expect(find.text('Agregar producto'), findsNothing); // sheet closed
  });

  testWidgets('while one option is loading the others are disabled and a second tap is ignored', (t) async {
    final calls = await open(t);
    await t.tap(find.text('Escanear código de barras'));
    await t.pump();
    await t.tap(find.text('Ingresar manualmente'), warnIfMissed: false);
    await t.tap(find.text('Escanear código de barras'), warnIfMissed: false);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await t.pumpAndSettle();
    expect(calls, [1, 0, 0]);
  });

  testWidgets('Cancelar closes the sheet without running anything', (t) async {
    final calls = await open(t);
    await t.tap(find.text('Cancelar'));
    await t.pumpAndSettle();
    expect(calls, [0, 0, 0]);
    expect(find.text('Agregar producto'), findsNothing);
  });

  testWidgets('the sheet fits a short phone at 2x text (it scrolls instead of overflowing)', (t) async {
    t.view.physicalSize = const Size(320 * 3, 568 * 3);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
      theme: FincasTheme.light(),
      builder: (context, c) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(2.0)), child: c!),
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => showAgregarProductoSheet(context, onEscanear: () {}, onFoto: () {}, onManual: () {}),
            child: const Text('abrir'),
          ),
        ),
      ),
    ));
    await t.tap(find.text('abrir'));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    expect(find.text('Agregar producto'), findsOneWidget);
  });

  testWidgets('manual entry also gets the loader', (t) async {
    final calls = await open(t);
    await t.tap(find.text('Ingresar manualmente'));
    await t.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await t.pumpAndSettle();
    expect(calls, [0, 0, 1]);
  });
}
