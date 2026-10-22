import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:apartalo_app/models/producto_info.dart';
import 'package:apartalo_app/services/api_service.dart';
import 'package:apartalo_app/theme/fincas_theme.dart';
import 'package:apartalo_app/widgets/fincas_widgets.dart';
import 'package:apartalo_app/widgets/producto_info_general.dart';

Widget _app(Widget child) => MaterialApp(theme: FincasTheme.light(), home: Scaffold(body: SingleChildScrollView(child: child)));

/// A section with its own expanded flag, like the product detail screen has.
class _Seccion extends StatefulWidget {
  const _Seccion({this.inicial = true});
  final bool inicial;
  @override
  State<_Seccion> createState() => _SeccionState();
}

class _SeccionState extends State<_Seccion> {
  late bool abierta = widget.inicial;
  final controlador = TextEditingController(text: 'texto inicial');
  @override
  void dispose() {
    controlador.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(children: [
        FincasSeccionEncabezado(titulo: 'Mi sección', subtitulo: 'Una descripción', expandida: abierta, onAlternar: () => setState(() => abierta = !abierta)),
        FincasPlegable(expandida: abierta, child: TextField(controller: controlador)),
      ]);
}

void main() {
  group('FincasSeccionEncabezado', () {
    testWidgets('shows title and subtitle, and the whole row is a button of at least 48pt', (t) async {
      var toques = 0;
      await t.pumpWidget(_app(FincasSeccionEncabezado(titulo: 'Presentaciones', subtitulo: 'Variantes', onAlternar: () => toques++)));
      expect(find.text('Presentaciones'), findsOneWidget);
      expect(find.text('Variantes'), findsOneWidget);
      expect(t.getSize(find.byType(InkWell).first).height, greaterThanOrEqualTo(48));
      await t.tap(find.text('Presentaciones'));
      expect(toques, 1);
      await t.tap(find.text('Variantes')); // the subtitle is part of the button too
      expect(toques, 2);
    });

    testWidgets('announces whether it is expanded or collapsed', (t) async {
      await t.pumpWidget(_app(FincasSeccionEncabezado(titulo: 'Información general', expandida: true, onAlternar: () {})));
      expect(find.bySemanticsLabel('Información general, expandida'), findsOneWidget);
      await t.pumpWidget(_app(FincasSeccionEncabezado(titulo: 'Información general', expandida: false, onAlternar: () {})));
      expect(find.bySemanticsLabel('Información general, contraída'), findsOneWidget);
    });

    testWidgets('the arrow turns when collapsed', (t) async {
      await t.pumpWidget(_app(FincasSeccionEncabezado(titulo: 'x', expandida: true, onAlternar: () {})));
      expect(t.widget<AnimatedRotation>(find.byType(AnimatedRotation)).turns, 0.5);
      await t.pumpWidget(_app(FincasSeccionEncabezado(titulo: 'x', expandida: false, onAlternar: () {})));
      expect(t.widget<AnimatedRotation>(find.byType(AnimatedRotation)).turns, 0);
    });

    testWidgets('without a toggle it is a plain header: no arrow, not a button', (t) async {
      await t.pumpWidget(_app(const FincasSeccionEncabezado(titulo: 'Fija')));
      expect(find.byType(AnimatedRotation), findsNothing);
      expect(find.byType(InkWell), findsNothing);
    });

    testWidgets('an extra action on the right keeps working and does not toggle', (t) async {
      var toggles = 0, actions = 0;
      await t.pumpWidget(_app(FincasSeccionEncabezado(titulo: 'x', onAlternar: () => toggles++, trailing: IconButton(onPressed: () => actions++, icon: const Icon(Icons.refresh)))));
      await t.tap(find.byIcon(Icons.refresh));
      expect((toggles, actions), (0, 1));
    });

    testWidgets('long titles and large text fit 320pt', (t) async {
      t.view.physicalSize = const Size(320 * 3, 640 * 3);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      await t.pumpWidget(MaterialApp(
        theme: FincasTheme.light(),
        builder: (context, c) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(2.0)), child: c!),
        home: Scaffold(body: FincasSeccionEncabezado(titulo: 'Un título de sección bastante largo para probar', subtitulo: 'Y un subtítulo todavía más largo que el título', onAlternar: () {}, trailing: const Icon(Icons.refresh))),
      ));
      expect(t.takeException(), isNull);
    });
  });

  group('collapsing a section', () {
    testWidgets('collapsing hides the content and expanding shows it again', (t) async {
      await t.pumpWidget(_app(const _Seccion()));
      expect(find.byType(TextField), findsOneWidget);
      await t.tap(find.text('Mi sección'));
      await t.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
      await t.tap(find.text('Mi sección'));
      await t.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('what was typed is kept while collapsed', (t) async {
      await t.pumpWidget(_app(const _Seccion()));
      await t.enterText(find.byType(TextField), 'algo que escribí');
      await t.tap(find.text('Mi sección'));
      await t.pumpAndSettle();
      await t.tap(find.text('Mi sección'));
      await t.pumpAndSettle();
      expect(t.widget<TextField>(find.byType(TextField)).controller!.text, 'algo que escribí');
    });

    testWidgets('it can start collapsed', (t) async {
      await t.pumpWidget(_app(const _Seccion(inicial: false)));
      expect(find.byType(TextField), findsNothing);
      expect(find.text('Mi sección'), findsOneWidget);
    });
  });

  group('Información general collapsible', () {
    const catalogos = CatalogosProducto(categorias: [OpcionCatalogo(id: 'cat-cafe', nombre: 'Café')]);
    const info = ProductoInfo(id: 'p1', nombre: 'Obata', descripcionBreve: 'Resumen', categoriaId: 'cat-cafe');

    Widget host({required ValueChanged<bool> alCambiar}) => MaterialApp(
          theme: FincasTheme.light(),
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                bool abierta = _abiertaGlobal;
                return SingleChildScrollView(
                  child: ProductoInfoGeneral(
                    productId: 'p1',
                    expandida: abierta,
                    onAlternar: () => setState(() => _abiertaGlobal = !_abiertaGlobal),
                    onDirtyChanged: alCambiar,
                    cargar: (_) async => ApiResponse.success(const ProductoInfoData(producto: info, catalogos: catalogos)),
                    guardar: (_, c) async => ApiResponse.success(info),
                  ),
                );
              },
            ),
          ),
        );

    testWidgets('collapsing hides the fields but keeps unsaved edits and the unsaved-changes flag', (t) async {
      _abiertaGlobal = true;
      final avisos = <bool>[];
      await t.pumpWidget(host(alCambiar: avisos.add));
      await t.pumpAndSettle();
      final desc = find.byWidgetPredicate((w) => w is TextField && w.decoration?.labelText == 'Descripción breve');
      await t.enterText(desc, 'Cambio sin guardar');
      await t.pump();
      expect(avisos.last, true);

      await t.tap(find.text('Información general'));
      await t.pumpAndSettle();
      expect(desc, findsNothing); // hidden
      expect(avisos.last, true); // still reported as unsaved, so leaving the screen still asks

      await t.tap(find.text('Información general'));
      await t.pumpAndSettle();
      expect(t.widget<TextField>(desc).controller!.text, 'Cambio sin guardar');
    });

    testWidgets('without a toggle the header is fixed and the section is always open', (t) async {
      await t.pumpWidget(MaterialApp(
        theme: FincasTheme.light(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: ProductoInfoGeneral(
              productId: 'p1',
              cargar: (_) async => ApiResponse.success(const ProductoInfoData(producto: info, catalogos: catalogos)),
            ),
          ),
        ),
      ));
      await t.pumpAndSettle();
      expect(find.byType(AnimatedRotation), findsNothing);
      expect(find.widgetWithText(TextField, 'Resumen'), findsOneWidget);
    });
  });
}

bool _abiertaGlobal = true;
