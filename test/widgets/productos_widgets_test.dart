import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
