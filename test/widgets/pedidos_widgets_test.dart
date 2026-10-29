import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:apartalo_app/screens/tabs/pedidos/widgets/pedidos_filtros.dart';
import 'package:apartalo_app/theme/fincas_theme.dart';
import 'package:apartalo_app/theme/fincas_tokens.dart';
import 'package:apartalo_app/widgets/fincas_widgets.dart';

Widget _app(Widget child, {double scale = 1.0}) => MaterialApp(
      theme: FincasTheme.light(),
      builder: (context, c) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)), child: c!),
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

Future<void> _small(WidgetTester t) async {
  t.view.physicalSize = const Size(320 * 3, 640 * 3);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
}

Map<String, dynamic> _pedido({String estado = 'PENDIENTE', String tipo = '', String origen = '', num total = 120, Map<String, dynamic>? extra}) => {
      'cliente': 'Keyla Cusi',
      'total': total,
      'estado': estado,
      'fecha': '21/10/2026',
      'tipo': tipo,
      'origen': origen,
      'productos': [
        {'nombre': 'Café', 'cantidad': 2},
        {'nombre': 'Molido', 'cantidad': 3},
      ],
      ...?extra,
    };

void main() {

  group('filters and summary', () {
    testWidgets('filter chips: selected state, count, touch target and tap', (t) async {
      var taps = 0;
      await t.pumpWidget(_app(Row(children: [
        Expanded(child: PedidosFiltroChip(label: 'Pendientes', count: 3, selected: true, onTap: () => taps++)),
        Expanded(child: PedidosFiltroChip(label: 'Historial', count: 0, selected: false, onTap: () {})),
      ])));
      expect(find.text('3'), findsOneWidget);
      expect(t.getSize(find.byType(PedidosFiltroChip).first).height, greaterThanOrEqualTo(48));
      await t.tap(find.text('Pendientes'));
      expect(taps, 1);
      expect(find.bySemanticsLabel('Pendientes, 3'), findsOneWidget);
    });

    Widget subRow({bool sel0 = true, bool sel1 = false, bool sel2 = false}) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(children: [
            Expanded(child: PedidosSubFiltroChip(label: 'Todos', count: 120, selected: sel0, onTap: () {})),
            const SizedBox(width: 8),
            Expanded(child: PedidosSubFiltroChip(label: 'Pagados', count: 90, tone: FincasTone.success, selected: sel1, onTap: () {})),
            const SizedBox(width: 8),
            Expanded(child: PedidosSubFiltroChip(label: 'Por cobrar', count: 30, tone: FincasTone.error, selected: sel2, onTap: () {})),
          ]),
        );

    testWidgets('sub-filters are three compact, equal pills that use the full width of the screen', (t) async {
      t.view.physicalSize = const Size(390 * 3, 844 * 3);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      await t.pumpWidget(_app(subRow()));
      final r = [for (final f in ['Todos', 'Pagados', 'Por cobrar']) t.getRect(find.ancestor(of: find.text(f), matching: find.byType(PedidosSubFiltroChip)).first)];
      expect(r[0].left, closeTo(16, 0.5)); // starts at the screen margin
      expect(r[2].right, closeTo(390 - 16, 0.5)); // ends at the other margin: nothing is left empty
      expect(r[0].width, closeTo(r[1].width, 0.5));
      expect(r[1].width, closeTo(r[2].width, 0.5));
      for (final x in r) {
        expect(x.height, inInclusiveRange(34, 40)); // compact pills, not tall bars
      }
    });

    testWidgets('sub-filters: selected is a solid pill (ink, green, red by meaning), the others are sand', (t) async {
      Color fillOf(String label) => t.widget<Material>(find.ancestor(of: find.text(label), matching: find.byType(Material)).first).color!;
      await t.pumpWidget(_app(subRow()));
      expect(fillOf('Todos'), FincasColors.ink);
      expect(fillOf('Pagados'), FincasColors.sand);
      await t.pumpWidget(_app(subRow(sel0: false, sel1: true)));
      expect(fillOf('Pagados'), FincasColors.success);
      await t.pumpWidget(_app(subRow(sel0: false, sel2: true)));
      expect(fillOf('Por cobrar'), FincasColors.error);
    });

    testWidgets('sub-filters fit 320pt at 2x text (the count goes under the label)', (t) async {
      await _small(t);
      await t.pumpWidget(_app(subRow(), scale: 2.0));
      expect(t.takeException(), isNull);
      expect(find.text('30'), findsOneWidget);
    });

    testWidgets('sub-filter tap reports the selection', (t) async {
      var taps = 0;
      await t.pumpWidget(_app(Row(children: [Expanded(child: PedidosSubFiltroChip(label: 'Pagados', count: 3, selected: false, onTap: () => taps++))])));
      await t.tap(find.text('Pagados'));
      expect(taps, 1);
      expect(find.bySemanticsLabel('Pagados, 3'), findsOneWidget);
    });

    testWidgets('summary shows the three amounts and the alert only when there is something to collect', (t) async {
      await t.pumpWidget(_app(const PedidosResumen(vendido: 1520, cobrado: 1200, porCobrar: 320, hayAlerta: true)));
      expect(find.text('S/1520'), findsOneWidget);
      expect(find.text('S/1200'), findsOneWidget);
      expect(find.text('S/320'), findsOneWidget);
      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
      await t.pumpWidget(_app(const PedidosResumen(vendido: 10, cobrado: 10, porCobrar: 0)));
      expect(find.byIcon(Icons.warning_amber_rounded), findsNothing);
    });

    testWidgets('summary fits 320pt at 2x text', (t) async {
      await _small(t);
      await t.pumpWidget(_app(const PedidosResumen(vendido: 123456, cobrado: 100000, porCobrar: 23456, hayAlerta: true), scale: 2.0));
      expect(t.takeException(), isNull);
    });
  });

  testWidgets('empty and error states reuse the shared message widget', (t) async {
    await t.pumpWidget(_app(const FincasMessageState(title: 'No hay pedidos pendientes', message: 'Jala hacia abajo para actualizar.')));
    expect(find.text('No hay pedidos pendientes'), findsOneWidget);
  });

  group('color is reserved for two buttons', () {
    testWidgets('Pendientes is a muted espresso when selected; Historial stays neutral (ink when active, sand when not)', (t) async {
      Color fillOf(String label) => t.widget<Material>(find.ancestor(of: find.text(label), matching: find.byType(Material)).first).color!;
      await t.pumpWidget(_app(Row(children: [
        Expanded(child: PedidosFiltroChip(label: 'Pendientes', count: 2, mutedAccent: true, selected: true, onTap: () {})),
        Expanded(child: PedidosFiltroChip(label: 'Historial', count: 5, selected: false, onTap: () {})),
      ])));
      expect(fillOf('Pendientes'), FincasColors.accentMuted); // active: muted espresso
      expect(fillOf('Historial'), FincasColors.sand); // inactive and neutral: no green
      await t.pumpWidget(_app(Row(children: [
        Expanded(child: PedidosFiltroChip(label: 'Pendientes', count: 2, mutedAccent: true, selected: false, onTap: () {})),
        Expanded(child: PedidosFiltroChip(label: 'Historial', count: 5, selected: true, onTap: () {})),
      ])));
      expect(fillOf('Pendientes'), FincasColors.accentBg); // inactive: soft tint of the same family
      expect(fillOf('Historial'), FincasColors.ink); // active history is the main (ink) color
    });
  });

  group('both creation buttons stay visible', () {
    testWidgets('Nuevo pedido (main) and Pre-venta (secondary) are both shown and both work', (t) async {
      var nuevo = 0, pre = 0;
      await t.pumpWidget(MaterialApp(
        theme: FincasTheme.light(),
        home: Scaffold(floatingActionButton: PedidosCrearBotones(onNuevo: () => nuevo++, onPreventa: () => pre++)),
      ));
      expect(find.text('Nuevo pedido'), findsOneWidget);
      expect(find.text('Pre-venta'), findsOneWidget);
      await t.tap(find.text('Pre-venta'));
      await t.tap(find.text('Nuevo pedido'));
      expect((nuevo, pre), (1, 1));
      // the main one is the accent, the secondary one is the light sand button
      final main = t.widget<FloatingActionButton>(find.byType(FloatingActionButton));
      final mainColor = main.backgroundColor ?? FincasTheme.light().floatingActionButtonTheme.backgroundColor;
      expect(mainColor, FincasColors.accent);
      expect(mainColor, FincasColors.espresso);
      expect(t.widget<Material>(find.ancestor(of: find.text('Pre-venta'), matching: find.byType(Material)).first).color, FincasColors.sand);
    });

    testWidgets('on a 320pt screen at 2x text both buttons fit (they wrap to two rows)', (t) async {
      await _small(t);
      await t.pumpWidget(MaterialApp(
        theme: FincasTheme.light(),
        builder: (context, c) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(2.0)), child: c!),
        home: Scaffold(floatingActionButton: Padding(padding: const EdgeInsets.only(left: 16), child: PedidosCrearBotones(onNuevo: () {}, onPreventa: () {}))),
      ));
      expect(t.takeException(), isNull);
      expect(find.text('Pre-venta'), findsOneWidget);
      expect(find.text('Nuevo pedido'), findsOneWidget);
    });
  });
}
