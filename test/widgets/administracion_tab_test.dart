import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:apartalo_app/screens/tabs/administracion_tab.dart';
import 'package:apartalo_app/screens/perfil_screen.dart';
import 'package:apartalo_app/services/administracion_service.dart';

void main() {
  final pedidos = <http.Request>[];
  var sugerencia = <String, dynamic>{'area': 'fulfillment', 'cost_centre': 'coffee', 'source': 'to_review'};

  http.Response responder(http.Request req) {
    pedidos.add(req);
    final p = req.url.path;
    if (p.endsWith('/pendientes')) {
      return http.Response(jsonEncode({
        'sinPrecio': [{'id': 'DL-0001', 'kg': 100, 'farmer_id': 'P-J', 'delivery_date': '2026-11-03'}],
        'porPagar': [{'id': 'PU-0001', 'still_owed': 300, 'farmer_id': 'P-J', 'purchase_date': '2026-11-04'}],
        'adelantos': [{'id': 'ADV-002', 'party_id': 'P-MIS', 'open_balance': 1500, 'advance_date': '2026-11-02'}],
        'banco': [],
        'adelantosPorAprobar': [{'id': 'SOL-0001', 'party': 'Misael Cusi', 'amount': 1500, 'reason': 'Compras', 'request_date': '2026-11-02', 'created_by': 'misael@x'}],
        'porRevisar': [{'id': 'EX-0007', 'category': 'Combustible', 'amount': 50, 'description': 'Gasolina', 'expense_date': '2026-11-20', 'created_by': 'misael@x', 'suggestion': {'area': 'sourcing', 'source': 'same_day'}}],
        'gastosPorPagar': [{'id': 'EX-0001', 'category': 'Gas', 'amount': 120, 'description': 'Gasolina', 'expense_date': '2026-11-01', 'created_by': 'staff@x'}],
      }), 200);
    }
    if (p.endsWith('/solicitudes')) {
      return http.Response(jsonEncode({'rol': 'staff', 'solicitudes': [
        {'kind': 'adelanto', 'id': 'SOL-0001', 'request_date': '2026-11-02', 'created_by': 'misael@x', 'description': 'Misael Cusi · Compras', 'amount': 1500, 'status': 'Entregado', 'detail': 'ADV-001 · 2026-11-04'},
        {'kind': 'entrega', 'id': 'DL-0001', 'request_date': '2026-11-03', 'created_by': 'misael@x', 'description': 'Tito · 100 kg parchment', 'amount': 1800, 'status': 'Por pagar', 'detail': 'Falta S/ 300.00'},
        {'kind': 'gasto', 'id': 'EX-0001', 'request_date': '2026-11-01', 'created_by': 'misael@x', 'description': 'Gas · Gasolina', 'amount': 120, 'status': 'Pendiente de pago', 'detail': null},
      ]}), 200);
    }
    if (p.endsWith('/personas')) return http.Response(jsonEncode([{'id': 'P-0001', 'nombre': 'Misael Cusi', 'agricultor': false, 'comprador': true, 'recogidoPor': null}]), 200);
    if (p.endsWith('/categorias')) {
      return http.Response(jsonEncode({
        'categorias': [
          {'category': 'Transporte', 'what_goes_here': 'Pasajes y movilidad de personas.', 'not_here': 'Gasolina (Combustible).', 'default_area': 'sourcing', 'default_cost_centre': 'coffee', 'main': true},
          {'category': 'Combustible', 'what_goes_here': 'Gasolina y petróleo.', 'default_area': 'fulfillment', 'default_cost_centre': 'coffee', 'main': true},
          {'category': 'Mano de obra', 'what_goes_here': 'Pago por día.', 'default_area': 'farm', 'default_cost_centre': 'farm', 'main': true},
          {'category': 'Flete', 'what_goes_here': 'Envío al cliente.', 'default_area': 'fulfillment', 'default_cost_centre': 'coffee', 'main': false},
          {'category': 'Otro', 'what_goes_here': 'Solo si nada encaja.', 'default_area': 'shared', 'default_cost_centre': 'coffee', 'main': false, 'needs_description': true},
        ],
        'areas': [{'id': 'farm', 'name': 'Finca'}, {'id': 'fulfillment', 'name': 'Logística'}, {'id': 'shared', 'name': 'Compartido'}],
      }), 200);
    }
    if (p.endsWith('/personas/buscar')) {
      final q = (req.url.queryParameters['q'] ?? '').toLowerCase();
      final offset = int.parse(req.url.queryParameters['offset'] ?? '0');
      final todos = [
        {'id': 'P-0001', 'nombre': 'Pedro Ramírez Ñique', 'detalle': 'También: Chato', 'agricultor': true, 'vende': 'parchment', 'recogidoPor': null},
        for (var i = 0; i < 30; i++) {'id': 'P-F$i', 'nombre': 'Agricultor ${i.toString().padLeft(2, '0')}', 'agricultor': true, 'vende': 'cherry'},
      ].where((p) => q.isEmpty || '${p['nombre']} ${p['detalle'] ?? ''}'.toLowerCase().contains(q)).toList();
      final pagina = todos.skip(offset).take(20).toList();
      return http.Response(jsonEncode({'personas': pagina, 'total': todos.length, 'hayMas': offset + 20 < todos.length}), 200);
    }
    if (p.endsWith('/sugerir-area')) return http.Response(jsonEncode(sugerencia), 200);
    if (p.endsWith('/mi-area')) {
      final pedido = req.url.queryParameters['area'] ?? 'fulfillment';
      final elegidas = pedido == 'todas' ? ['fulfillment', 'sourcing'] : pedido.split(',');
      return http.Response(jsonEncode({
        'elegidas': elegidas,
        'areas': [{'area': 'fulfillment', 'name': 'Logística', 'role': 'lead', 'principal': true}, {'area': 'sourcing', 'name': 'Compras', 'role': 'member', 'principal': false}],
        'area': 'fulfillment',
        'meses': [{'month': '2026-11-01', 'cost_centre': 'coffee', 'total': 120, 'paid': 0, 'to_pay': 120}],
        'gastos': [
          if (elegidas.contains('fulfillment')) {'id': 'EX-0001', 'area': 'fulfillment', 'category': 'Flete', 'amount': 120, 'description': 'Envío a Lima', 'expense_date': '2026-11-01', 'created_by': 'staff@x', 'status': 'Por pagar'},
          if (elegidas.contains('sourcing')) {'id': 'EX-0002', 'area': 'sourcing', 'category': 'Transporte', 'amount': 30, 'description': 'Lobato', 'expense_date': '2026-11-01', 'created_by': 'staff@x', 'status': 'Por pagar'},
        ],
      }), 200);
    }
    if (p.endsWith('/equipo')) {
      return http.Response(jsonEncode({'equipo': [
        {'profile_id': '11111111-2222-3333-4444-555555555555', 'name': 'Persona Uno', 'email': 'uno@x', 'role': 'staff', 'areas': []},
        {'profile_id': '66666666-2222-3333-4444-555555555555', 'name': 'Persona Dos', 'email': 'dos@x', 'role': 'owner',
          'areas': [{'area': 'finance', 'name': 'Finanzas', 'principal': true}]},
      ]}), 200);
    }
    if (p.endsWith('/sugerencia')) {
      return http.Response(jsonEncode({'sugeridas': [{'area': 'sourcing', 'name': 'Compras', 'records': 4}, {'area': 'farm', 'name': 'Finca', 'records': 2}]}), 200);
    }
    if (p.endsWith('/resumen')) return http.Response(jsonEncode({'rol': 'owner', 'meses': []}), 200);
    if (p.contains('/registrar/')) return http.Response(jsonEncode({'ok': true, 'result': {'expense_id': 'EX-0001'}}), 200);
    return http.Response(jsonEncode({'pedidos': [], 'total': 0}), 200);
  }

  setUp(() {
    pedidos.clear();
    sugerencia = {'area': 'fulfillment', 'cost_centre': 'coffee', 'source': 'to_review'};
    dotenv.testLoad(fileInput: 'API_BASE_URL=https://api.test\nBUSINESS_ID=BIZ-002');
  });

  Future<void> abrir(WidgetTester tester, {required String rol}) async {
    // An iPhone-sized screen (390 x 844 points).
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({'business_role': rol});
    await http.runWithClient(() async {
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: AdministracionTab())));
      await tester.pumpAndSettle();
    }, () => MockClient((req) async => responder(req)));
  }

  testWidgets('four parts; staff ask, only the owner sees money buttons', (tester) async {
    await abrir(tester, rol: 'staff');
    expect(find.text('Administración'), findsOneWidget);
    for (final t in ['Registrar', 'Pendientes', 'Solicitudes', 'Resumen']) {
      expect(find.text(t), findsOneWidget);
    }
    for (final t in ['Registrar gasto', 'Registrar entrega', 'Solicitar adelanto', 'Registrar proveedor']) {
      expect(find.text(t), findsOneWidget);
    }
    expect(find.text('Pasar dinero a caja'), findsNothing);
    expect(find.text('Pagar compras'), findsNothing);
    expect(find.text('Ingreso de dinero'), findsNothing);
  });

  testWidgets('the owner also sees Pagar compra and Retiro a caja', (tester) async {
    await abrir(tester, rol: 'owner');
    expect(find.text('Pasar dinero a caja'), findsOneWidget);
    expect(find.text('Pagar compras'), findsOneWidget);
  });

  testWidgets('an advance is a request: no payment fields', (tester) async {
    await abrir(tester, rol: 'staff');
    await http.runWithClient(() async {
      await tester.tap(find.text('Solicitar adelanto'));
      await tester.pumpAndSettle();
    }, () => MockClient((req) async => responder(req)));
    expect(find.text('Para'), findsOneWidget);
    expect(find.textContaining('Cómo se'), findsNothing);
    expect(find.textContaining('Número de operación'), findsNothing);
  });

  testWidgets('the owner approves an advance from Pendientes, choosing how it is paid', (tester) async {
    await abrir(tester, rol: 'owner');
    await http.runWithClient(() async {
      await tester.tap(find.text('Pendientes'));
      await tester.pumpAndSettle();
      expect(find.text('Adelantos por aprobar (1)'), findsOneWidget);
      await tester.tap(find.byTooltip('Aprobar'));
      await tester.pumpAndSettle();
      expect(find.text('Aprobar adelanto'), findsOneWidget);
      await tester.tap(find.text('Efectivo'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
    }, () => MockClient((req) async => responder(req)));
    final r = pedidos.lastWhere((r) => r.url.path.contains('/registrar/'));
    expect(r.url.path, endsWith('/registrar/aprobarAdelanto'));
    expect(jsonDecode(r.body)['solicitudId'], 'SOL-0001');
  });

  testWidgets('Solicitudes shows where each request stands', (tester) async {
    await abrir(tester, rol: 'staff');
    await http.runWithClient(() async {
      await tester.tap(find.text('Solicitudes'));
      await tester.pumpAndSettle();
    }, () => MockClient((req) async => responder(req)));
    expect(find.text('Entregado'), findsOneWidget);
    expect(find.text('Por pagar'), findsOneWidget);
    expect(find.text('Pendiente de pago'), findsOneWidget);
    expect(find.textContaining('Falta S/ 300.00'), findsOneWidget);
  });

  testWidgets('Proveedor asks what a farmer sells only for a farmer', (tester) async {
    await abrir(tester, rol: 'staff');
    await http.runWithClient(() async {
      await tester.tap(find.text('Registrar proveedor'));
      await tester.pumpAndSettle();
      expect(find.text('Vende'), findsNothing);
      await tester.tap(find.text('Agricultor'));
      await tester.pumpAndSettle();
    }, () => MockClient((req) async => responder(req)));
    expect(find.text('Vende'), findsOneWidget);
    expect(find.text('Lo recoge (comprador) (opcional)'), findsOneWidget);
  });

  testWidgets('the expense form asks for what is missing before sending anything', (tester) async {
    await abrir(tester, rol: 'owner');
    await http.runWithClient(() async {
      await tester.tap(find.text('Registrar gasto'));
      await tester.pumpAndSettle();
      expect(find.text('Guardar'), findsOneWidget);
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
    }, () => MockClient((req) async => responder(req)));
    expect(find.textContaining('Falta: Monto (S/)'), findsOneWidget); // Combustible is already chosen
    expect(pedidos.where((r) => r.url.path.contains('/registrar/')), isEmpty);
  });

  testWidgets('the expense form is a request: category, amount, description; no payment fields', (tester) async {
    await abrir(tester, rol: 'staff');
    await tester.tap(find.text('Registrar gasto'));
    await tester.pumpAndSettle();
    // 16 categories as chips: the description may sit below the first screen.
    await tester.drag(find.text('Monto (S/)'), const Offset(0, -300));
    await tester.pumpAndSettle();
    final yCategoria = tester.getTopLeft(find.text('Categoría')).dy;
    final yMonto = tester.getTopLeft(find.text('Monto (S/)')).dy;
    final yDescripcion = tester.getTopLeft(find.text('Descripción (opcional)')).dy;
    expect(yCategoria < yMonto && yMonto < yDescripcion, isTrue);
    expect(find.text('Cómo se pagó'), findsNothing);
    expect(find.textContaining('Número de operación'), findsNothing);
    expect(find.text('Más opciones'), findsOneWidget);
    expect(find.textContaining('Fecha: hoy'), findsOneWidget);
    expect(find.byType(ChoiceChip), findsWidgets);
    expect(find.text('Registrar gasto'), findsOneWidget); // the form title repeats the button name
  });

  testWidgets('choosing a category fills the area from the database', (tester) async {
    await abrir(tester, rol: 'staff');
    await http.runWithClient(() async {
      await tester.tap(find.text('Registrar gasto'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Combustible'));
      await tester.pumpAndSettle();
    }, () => MockClient((req) async => responder(req)));
    expect(find.textContaining('Área: Logística'), findsOneWidget);
  });

  testWidgets('Registrar gasto opens with Combustible first and already chosen', (tester) async {
    await abrir(tester, rol: 'staff');
    await http.runWithClient(() async {
      await tester.tap(find.text('Registrar gasto'));
      await tester.pumpAndSettle();
    }, () => MockClient((req) async => responder(req)));
    final chips = tester.widgetList<ChoiceChip>(find.byType(ChoiceChip)).toList();
    expect((chips.first.label as Text).data, 'Combustible');
    expect(chips.first.selected, isTrue);
    expect(find.textContaining('Gasolina y petróleo'), findsOneWidget);
  });

  testWidgets('main categories first, the rest behind "Ver más", and what goes in the chosen one', (tester) async {
    await abrir(tester, rol: 'staff');
    await http.runWithClient(() async {
      await tester.tap(find.text('Registrar gasto'));
      await tester.pumpAndSettle();
    }, () => MockClient((req) async => responder(req)));
    expect(find.text('Transporte'), findsOneWidget);
    expect(find.text('Flete'), findsNothing);
    expect(find.text('Operativo'), findsNothing);
    await tester.tap(find.text('Transporte'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Pasajes y movilidad'), findsOneWidget);
    expect(find.textContaining('No va aquí: Gasolina'), findsOneWidget);
    await tester.tap(find.text('Ver más categorías'));
    await tester.pumpAndSettle();
    expect(find.text('Flete'), findsOneWidget);
    expect(find.text('Ver más categorías'), findsNothing);
  });

  testWidgets('fuel: when the database cannot tell, one optional tap; the area is left to the database', (tester) async {
    await abrir(tester, rol: 'staff');
    await http.runWithClient(() async {
      await tester.tap(find.text('Registrar gasto'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Combustible'));
      await tester.pumpAndSettle();
      expect(find.text('¿Para qué fue? (opcional)'), findsOneWidget);
      await tester.tap(find.text('Compra de café'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Área: Compras (automático)'), findsOneWidget);
      await tester.enterText(find.byType(TextField).first, '50');
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
    }, () => MockClient((req) async => responder(req)));
    final r = pedidos.lastWhere((r) => r.url.path.contains('/registrar/'));
    final body = jsonDecode(r.body) as Map;
    expect(body['paraQue'], 'compra');
    expect(body.containsKey('area'), isFalse);
    expect(body.containsKey('centro'), isFalse);
  });

  testWidgets('fuel: a purchase that day sets the area with no question', (tester) async {
    sugerencia = {'area': 'sourcing', 'cost_centre': 'coffee', 'source': 'same_day', 'delivery_id': 'DL-0009'};
    await abrir(tester, rol: 'staff');
    await http.runWithClient(() async {
      await tester.tap(find.text('Registrar gasto'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Combustible'));
      await tester.pumpAndSettle();
    }, () => MockClient((req) async => responder(req)));
    expect(find.text('¿Para qué fue? (opcional)'), findsNothing);
    expect(find.textContaining('Área: Compras (automático)'), findsOneWidget);
  });

  testWidgets('the owner reviews fuel nobody could place, with the suggestion', (tester) async {
    await abrir(tester, rol: 'owner');
    await http.runWithClient(() async {
      await tester.tap(find.text('Pendientes'));
      await tester.pumpAndSettle();
    }, () => MockClient((req) async => responder(req)));
    await tester.scrollUntilVisible(find.text('Áreas por revisar (1)'), 300, scrollable: find.byType(Scrollable).last);
    expect(find.textContaining('Sugerido: Compras'), findsOneWidget);
  });

  testWidgets('choosing a farmer: a search screen in pages, closed with the X, nothing chosen', (tester) async {
    await abrir(tester, rol: 'staff');
    await http.runWithClient(() async {
      await tester.tap(find.text('Registrar entrega'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Agricultor'));
      await tester.pumpAndSettle();
      expect(find.text('Buscar por nombre o apodo'), findsOneWidget);
      expect(find.text('Agricultor 00'), findsOneWidget);
      expect(find.text('Agricultor 25'), findsNothing); // only the first page
      await tester.tap(find.byTooltip('Cerrar'));
      await tester.pumpAndSettle();
    }, () => MockClient((req) async => responder(req)));
    expect(find.text('Guardar'), findsOneWidget); // back in the form
    expect(find.text('Pedro Ramírez Ñique'), findsNothing);
  });

  testWidgets('scrolling down loads the next page of people', (tester) async {
    await abrir(tester, rol: 'staff');
    await http.runWithClient(() async {
      await tester.tap(find.text('Registrar entrega'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Agricultor'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Agricultor 25'), 300, scrollable: find.byType(Scrollable).last);
      await tester.pumpAndSettle();
    }, () => MockClient((req) async => responder(req)));
    expect(find.text('Agricultor 25'), findsOneWidget);
    expect(pedidos.where((r) => r.url.path.endsWith('/personas/buscar')).map((r) => r.url.queryParameters['offset']).toSet(), containsAll(['0', '20']));
  });

  testWidgets('choosing a farmer by nickname fills the field', (tester) async {
    await abrir(tester, rol: 'staff');
    await http.runWithClient(() async {
      await tester.tap(find.text('Registrar entrega'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Agricultor'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'chato');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(find.text('Agricultor 00'), findsNothing);
      await tester.tap(find.text('Pedro Ramírez Ñique'));
      await tester.pumpAndSettle();
    }, () => MockClient((req) async => responder(req)));
    expect(find.text('Guardar'), findsOneWidget);
    expect(find.text('Pedro Ramírez Ñique'), findsOneWidget);
    final pedidosBuscar = pedidos.where((r) => r.url.path.endsWith('/personas/buscar'));
    expect(pedidosBuscar.every((r) => r.url.queryParameters['rol'] == 'agricultor'), isTrue);
  });

  testWidgets('Otro asks what it was before sending', (tester) async {
    await abrir(tester, rol: 'staff');
    await http.runWithClient(() async {
      await tester.tap(find.text('Registrar gasto'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ver más categorías'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Otro').first); // the category, not the "¿Para qué fue?" chip
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, '30');
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
    }, () => MockClient((req) async => responder(req)));
    expect(find.textContaining('Escribe en Descripción qué fue'), findsOneWidget);
    expect(pedidos.where((r) => r.url.path.contains('/registrar/')), isEmpty);
  });

  Future<void> abrirPantalla(WidgetTester tester, Widget pantalla) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await http.runWithClient(() async {
      await tester.pumpWidget(MaterialApp(home: pantalla));
      await tester.pumpAndSettle();
    }, () => MockClient((req) async => responder(req)));
  }

  testWidgets('Mi área shows the area costs by month and the latest expenses, principal marked', (tester) async {
    await abrirPantalla(tester, const MiAreaScreen());
    expect(find.text('Logística · principal'), findsOneWidget);
    expect(find.text('2026-11 · S/ 120.00'), findsOneWidget);
    expect(find.textContaining('por pagar S/ 120.00'), findsOneWidget);
    expect(find.text('Flete · S/ 120.00'), findsOneWidget);
  });

  testWidgets('Mi área: several areas at once, and Todas', (tester) async {
    await abrirPantalla(tester, const MiAreaScreen());
    expect(find.text('Lobato'), findsNothing);
    await http.runWithClient(() async {
      await tester.tap(find.text('Compras'));
      await tester.pumpAndSettle();
    }, () => MockClient((req) async => responder(req)));
    expect(pedidos.last.url.queryParameters['area'], 'fulfillment,sourcing');
    expect(find.textContaining('Compras · Lobato'), findsOneWidget); // the area shows on each expense
    expect(find.textContaining('Logística · Envío a Lima'), findsOneWidget);
    await http.runWithClient(() async {
      await tester.tap(find.text('Logística · principal'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Compras'));
      await tester.pumpAndSettle(); // the last one stays chosen
    }, () => MockClient((req) async => responder(req)));
    expect(pedidos.last.url.queryParameters['area'], 'sourcing');
    await http.runWithClient(() async {
      await tester.tap(find.text('Todas'));
      await tester.pumpAndSettle();
    }, () => MockClient((req) async => responder(req)));
    expect(pedidos.last.url.queryParameters['area'], 'todas');
  });

  testWidgets('Perfil: staff see their areas and Mi área, not Equipo', (tester) async {
    await abrirPantalla(tester, const PerfilScreen(businessId: 'BIZ-002', businessName: 'Finca Rosal', esDueno: false));
    expect(find.text('Logística · principal'), findsOneWidget);
    expect(find.text('Compras'), findsOneWidget);
    expect(find.text('Mi área'), findsOneWidget);
    expect(find.text('Equipo'), findsNothing);
  });

  testWidgets('Perfil: tapping an area ticks it (no new screen); Mi área opens with the ticked ones', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await abrirPantalla(tester, const PerfilScreen(businessId: 'BIZ-002', businessName: 'Finca Rosal', esDueno: true));
    expect(find.textContaining('ves todas'), findsNothing);
    expect(find.text('Logística'), findsOneWidget); // the principal is ticked at the start, in the Mi área line
    await tester.tap(find.text('Compras'));
    await tester.pumpAndSettle();
    expect(find.byType(MiAreaScreen), findsNothing); // stays in Perfil
    expect(find.text('Logística + Compras'), findsOneWidget);
    expect((await SharedPreferences.getInstance()).getStringList('mi_area_elegidas'), containsAll(['fulfillment', 'sourcing']));
    await http.runWithClient(() async {
      await tester.tap(find.text('Mi área'));
      await tester.pumpAndSettle();
    }, () => MockClient((req) async => responder(req)));
    expect(find.byType(MiAreaScreen), findsOneWidget);
    expect(pedidos.last.url.queryParameters['area']!.split(',').toSet(), {'fulfillment', 'sourcing'});
  });

  testWidgets('Perfil: owners open Equipo and see each person with role and areas', (tester) async {
    await abrirPantalla(tester, const PerfilScreen(businessId: 'BIZ-002', businessName: 'Finca Rosal', esDueno: true));
    await http.runWithClient(() async {
      await tester.tap(find.text('Equipo'));
      await tester.pumpAndSettle();
    }, () => MockClient((req) async => responder(req)));
    expect(find.text('Persona Uno'), findsOneWidget);
    expect(find.text('Dueño · Finanzas (principal)'), findsOneWidget);
    expect(find.text('Invitar y solicitudes'), findsOneWidget);
  });

  testWidgets('Áreas de una persona: suggested areas ticked, three areas with one principal, saved', (tester) async {
    await abrirPantalla(tester, const AreasPersonaScreen(persona: {'profile_id': '11111111-2222-3333-4444-555555555555', 'name': 'Persona Uno', 'areas': []}));
    expect(find.text('Sugerida · 4 registros'), findsOneWidget);
    expect(find.text('Principal'), findsOneWidget); // Compras, the most used
    await http.runWithClient(() async {
      await tester.scrollUntilVisible(find.text('Estrategia'), 200, scrollable: find.byType(Scrollable).last);
      await tester.tap(find.text('Estrategia'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Confirmar'), 200, scrollable: find.byType(Scrollable).last);
      await tester.tap(find.text('Confirmar'));
      await tester.pumpAndSettle();
    }, () => MockClient((req) async => responder(req)));
    final r = pedidos.lastWhere((r) => r.url.path.endsWith('/registrar/areasPersona'));
    final body = jsonDecode(r.body) as Map;
    expect((body['areas'] as List).toSet(), {'sourcing', 'farm', 'strategy'});
    expect(body['principal'], 'sourcing');
  });

  testWidgets('Áreas de una persona: the X closes without saving', (tester) async {
    await abrirPantalla(tester, const AreasPersonaScreen(persona: {'profile_id': '11111111-2222-3333-4444-555555555555', 'name': 'Persona Uno', 'areas': []}));
    await http.runWithClient(() async {
      await tester.tap(find.text('Producción'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Cerrar'));
      await tester.pumpAndSettle();
    }, () => MockClient((req) async => responder(req)));
    expect(pedidos.where((r) => r.url.path.contains('/registrar/')), isEmpty);
  });

  testWidgets('tapping outside a field hides the keyboard', (tester) async {
    await abrir(tester, rol: 'owner');
    await tester.tap(find.text('Registrar gasto'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(EditableText).first); // the amount field
    await tester.pumpAndSettle();
    bool tecladoAbierto() => tester.widget<EditableText>(find.byType(EditableText).first).focusNode.hasFocus;
    expect(tecladoAbierto(), isTrue);
    await tester.tapAt(const Offset(4, 600)); // the empty margin beside the fields
    await tester.pumpAndSettle();
    expect(tecladoAbierto(), isFalse);
  });

  testWidgets('the X closes the form without saving', (tester) async {
    await abrir(tester, rol: 'owner');
    await tester.tap(find.text('Registrar gasto'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Cancelar'));
    await tester.pumpAndSettle();
    expect(find.text('Guardar'), findsNothing);
    expect(find.text('Registrar'), findsOneWidget);
    expect(pedidos.where((r) => r.url.path.contains('/registrar/')), isEmpty);
  });

  testWidgets('pendientes lists what waits for a price, a payment and open advances', (tester) async {
    await abrir(tester, rol: 'owner');
    await http.runWithClient(() async {
      await tester.tap(find.text('Pendientes'));
      await tester.pumpAndSettle();
    }, () => MockClient((req) async => responder(req)));
    expect(find.text('Sin precio (1)'), findsOneWidget);
    expect(find.text('Compras por pagar (1)'), findsOneWidget);
    await tester.scrollUntilVisible(find.textContaining('ADV-002'), 300, scrollable: find.byType(Scrollable).last);
    expect(find.textContaining('ADV-002'), findsOneWidget);
    expect(find.text('Gastos por pagar (1)'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Banco por cruzar (0)'), 300, scrollable: find.byType(Scrollable).last);
    expect(find.text('Banco por cruzar (0)'), findsOneWidget);
  });

  testWidgets('the owner pays a requested expense from Pendientes, choosing how', (tester) async {
    await abrir(tester, rol: 'owner');
    await http.runWithClient(() async {
      await tester.tap(find.text('Pendientes'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Gas · S/ 120.00'));
      await tester.pumpAndSettle();
      expect(find.text('Pagar gasto'), findsOneWidget);
      expect(find.text('Cómo se pagó'), findsOneWidget);
      await tester.tap(find.text('Efectivo'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
    }, () => MockClient((req) async => responder(req)));
    final pago = pedidos.lastWhere((r) => r.url.path.contains('/registrar/'));
    expect(pago.url.path, endsWith('/registrar/pagoGasto'));
    expect(jsonDecode(pago.body)['gastoId'], 'EX-0001');
    expect(jsonDecode(pago.body)['metodo'], 'cash');
  });

  testWidgets('staff do not see expenses to pay', (tester) async {
    await abrir(tester, rol: 'staff');
    await http.runWithClient(() async {
      await tester.tap(find.text('Pendientes'));
      await tester.pumpAndSettle();
    }, () => MockClient((req) async => responder(req)));
    expect(find.textContaining('Gastos por pagar'), findsNothing);
  });

  test('each send has its own retry key, long enough for the database', () {
    final a = AdministracionService.nuevaClave('gasto');
    final b = AdministracionService.nuevaClave('gasto');
    expect(a, isNot(b));
    expect(a.length, inInclusiveRange(8, 80));
  });

  test('a form sends to the business route with the retry key', () async {
    await http.runWithClient(() async {
      final r = await AdministracionService.registrar('gasto', {'monto': 80}, clave: 'gasto-123-abcdefgh');
      expect(r.isSuccess, isTrue);
    }, () => MockClient((req) async => responder(req)));
    final req = pedidos.single;
    expect(req.url.toString(), 'https://api.test/api/administracion/BIZ-002/registrar/gasto');
    expect(jsonDecode(req.body), {'monto': 80, 'clientRef': 'gasto-123-abcdefgh'});
  });
}
