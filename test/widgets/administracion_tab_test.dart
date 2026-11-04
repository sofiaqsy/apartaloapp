import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:apartalo_app/screens/tabs/administracion_tab.dart';
import 'package:apartalo_app/screens/tabs/pedidos/widgets/detalle_pedido/detalle_pedido_sheet.dart';
import 'package:apartalo_app/screens/perfil_screen.dart';
import 'package:apartalo_app/services/administracion_service.dart';
import 'package:apartalo_app/services/proveedor_pdf_service.dart';

void main() {
  final pedidos = <http.Request>[];
  var sugerencia = <String, dynamic>{'area': 'fulfillment', 'cost_centre': 'coffee', 'source': 'to_review'};
  // Las áreas marcadas en Perfil deciden qué tarjetas muestra Registrar.
  var marcadas = ['farm', 'sourcing', 'production', 'commercial', 'fulfillment', 'finance'];
  var sinComercial = false;
  var esDuenoMock = true; // el servidor de prueba responde como la persona de cada prueba (dueño o equipo) // el servidor no manda Comercialización (no es área de la persona)

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
          {'category': 'Personal', 'what_goes_here': 'Sueldo fijo.', 'default_area': 'people', 'default_cost_centre': 'coffee', 'main': true},
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
    if (p.endsWith('/comercial/clientes')) {
      return http.Response(jsonEncode({
        'clientes': [{'clave': 'c1', 'nombre': 'Cafe Uno', 'pedidos': 2, 'ultimo': '2026-11-02', 'primero': '2026-10-01', 'total': 150, 'telefono': '999111'}],
        'total': 1, 'hay_mas': false,
      }), 200);
    }
    if (p.endsWith('/comercial/productos')) {
      return http.Response(jsonEncode({
        'desde': '2026-01-01',
        'productos': [{'producto': 'Blend', 'presentacion': '1 kg', 'unidades': 3, 'pedidos': 2, 'total': 100}],
        'total': 1, 'hay_mas': false,
      }), 200);
    }
    if (p.contains('/api/pedidos/') && req.url.queryParameters['vista'] == null && req.url.queryParameters['limite'] == '20') {
      Map<String, dynamic> pedido(String id, String cliente) =>
          {'id': id, 'cliente': cliente, 'estado': 'ENTREGADO', 'fecha': '2/11/2026', 'productos': [], 'total': 50, 'estadoPago': 'PAGADO', 'evidencias': [], 'pagos': []};
      final todos = req.url.queryParameters['cliente'] == 'Cafe Uno' ? [pedido('ORD-301', 'Cafe Uno')] : [pedido('ORD-300', 'Cafe Venta')];
      return http.Response(jsonEncode({'pedidos': todos, 'total': todos.length, 'pagina': 1, 'totalPaginas': 1, 'hayMas': false}), 200);
    }
    if (p.endsWith('/comercial/reporte')) return http.Response(jsonEncode({'error': 'Sin señal'}), 503);
    if (p.endsWith('/gastos-area')) {
      // The Gastos tab of a process, 20 at a time (4 Nov 2026).
      final area = req.url.queryParameters['area'];
      final todos = [
        {'id': 'EX-0001', 'area': 'fulfillment', 'category': 'Flete', 'amount': 120, 'description': 'Envío a Lima', 'expense_date': '2026-11-01', 'created_by': 'staff@x', 'status': 'Pendiente de pago'},
        {'id': 'EX-0002', 'area': 'sourcing', 'category': 'Transporte', 'amount': 30, 'description': 'Lobato', 'expense_date': '2026-11-01', 'created_by': 'staff@x', 'status': 'Pendiente de pago'},
        {'id': 'EX-0003', 'area': 'farm', 'category': 'Mano de obra', 'amount': 120, 'description': 'Jornal deshierbo', 'expense_date': '2026-11-02', 'created_by': 'staff@x', 'status': 'Pagado'},
      ].where((g) => g['area'] == area).toList();
      return http.Response(jsonEncode({'gastos': todos, 'hayMas': false}), 200);
    }
    if (p.endsWith('/finca/reporte') || p.endsWith('/finanzas/reporte')) return http.Response(jsonEncode({'error': 'Sin señal'}), 503);
    if (p.endsWith('/mi-area')) {
      final pedido = req.url.queryParameters['area'] ?? 'fulfillment';
      final elegidas = pedido == 'todas' ? ['fulfillment', 'sourcing'] : pedido.split(',');
      return http.Response(jsonEncode({
        'elegidas': elegidas,
        'areas': [
          {'area': 'fulfillment', 'name': 'Logística', 'role': 'lead', 'principal': true},
          {'area': 'sourcing', 'name': 'Compras', 'role': 'member', 'principal': false},
          if (!p.endsWith('/mi-area') || req.url.queryParameters['area'] == null) ...[
            {'area': 'farm', 'name': 'Finca', 'role': 'member', 'principal': false},
            {'area': 'production', 'name': 'Producción', 'role': 'member', 'principal': false},
            {'area': 'commercial', 'name': 'Comercial', 'role': 'member', 'principal': false},
            {'area': 'finance', 'name': 'Finanzas', 'role': 'member', 'principal': false},
          ],
        ],
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
    if (p.endsWith('/api/productos/BIZ-002')) {
      return http.Response(jsonEncode({'productos': [
        {'codigo': 'prod-pack', 'nombre': 'Pack x3: Blend, Obata y Geisha', 'estado': 'ACTIVO'},
        {'codigo': 'prod-geisha', 'nombre': 'Geisha', 'categoria': 'Café', 'estado': 'ACTIVO'},
        {'codigo': 'prod-blend', 'nombre': 'Blend de Caturra, Pache, typica', 'categoria': 'Café', 'estado': 'ACTIVO'},
      ], 'total': 3}), 200);
    }
    // The report is checked up to the request; building the PDF needs the fonts from the internet (tested apart).
    if (p.endsWith('/compras/reporte') || p.endsWith('/produccion/reporte')) return http.Response(jsonEncode({'error': 'Sin señal'}), 503);
    if (p.contains('/api/pedidos/') && ['PENDIENTES', 'HISTORIAL'].contains(req.url.queryParameters['vista']) && req.url.queryParameters['limite'] == '20') {
      // The store orders, 20 a page, as the Pedidos tab gets them (Logística, 4 Nov 2026).
      final vista = req.url.queryParameters['vista'];
      final pagina = int.tryParse(req.url.queryParameters['pagina'] ?? '1') ?? 1;
      Map<String, dynamic> pedido(String id, String cliente, String estado, String fecha) =>
          {'id': id, 'cliente': cliente, 'estado': estado, 'fecha': fecha, 'productos': [], 'total': 50, 'estadoPago': 'PAGADO', 'evidencias': [], 'pagos': []};
      final todos = vista == 'PENDIENTES'
          ? [pedido('ORD-101', 'Cafe Uno', 'PENDIENTE', '1/11/2026'), pedido('ORD-102', 'Cafe Dos', 'ENVIADO', '2/11/2026')]
          : [for (var i = 0; i < 22; i++) pedido('ORD-${200 + i}', 'Cliente $i', i == 0 ? 'CANCELADO' : 'ENTREGADO', '${20 - i % 20}/10/2026')];
      final pagina20 = todos.skip((pagina - 1) * 20).take(20).toList();
      return http.Response(jsonEncode({'pedidos': pagina20, 'total': todos.length, 'pagina': pagina, 'totalPaginas': (todos.length / 20).ceil(), 'hayMas': pagina * 20 < todos.length}), 200);
    }
    if (p.endsWith('/logistica/reporte')) return http.Response(jsonEncode({'error': 'Sin señal'}), 503);
    if (p.endsWith('/lotes-verdes/g7/cuenta')) {
      // The lot as an account statement, newest first, 20 lines a page (4 Nov 2026): 5 recent lines, 19 older roasts and
      // the Entrada inicial, 25 in all.
      final todas = <Map<String, dynamic>>[
        {'fecha': '2026-11-04', 'tipo': 'compra', 'titulo': 'Compra DL-0008 · José Luis Gamboa Villano', 'detalle': '72 kg de pergamino al 80%', 'kg': 57.6, 'saldo': 484.96},
        {'fecha': '2026-11-04', 'tipo': 'compra', 'titulo': 'Compra DL-0009 · Jhonatan', 'detalle': '16.7 kg de pergamino al 80%', 'kg': 13.36, 'saldo': 427.36},
        {'fecha': '2026-11-03', 'tipo': 'venta', 'titulo': 'Venta de café verde · pedido ORD-1', 'kg': -72, 'saldo': 414},
        {'fecha': '2026-11-02', 'tipo': 'tueste', 'titulo': 'Tueste · Blend de Caturra', 'detalle': '80 kg tostado', 'kg': -100, 'saldo': 486},
        for (var i = 0; i < 20; i++) {'fecha': '2026-10-01', 'tipo': 'tueste', 'titulo': 'Tueste antiguo $i', 'kg': -1, 'saldo': 586 + i},
        {'fecha': '2026-09-17', 'tipo': 'inicio', 'titulo': 'Entrada inicial', 'kg': 1000, 'saldo': 1000},
      ];
      final desde = int.tryParse(req.url.queryParameters['offset'] ?? '0') ?? 0;
      final pagina = todas.skip(desde).take(20).toList();
      return http.Response(jsonEncode({
        'cuenta': {'lineas': pagina, 'total': todas.length, 'hay_mas': desde + pagina.length < todas.length, 'saldo': 484.96, 'entradas': 1070.96, 'salidas': 586}
      }), 200);
    }
    if (p.endsWith('/lotes-verdes/g7')) {
      return http.Response(jsonEncode({
        'lote': {
          'id': 'g7', 'codigo': 'L-7', 'estado': 'available', 'kg_ahora': 414, 'kg_inicial': 1000, 'variedad': 'Blend', 'cosecha': 2026,
          'origen': 'Finca Rosal', 'llego': '2026-09-17', 'producto': 'Blend de Caturra', 'crece': true,
          'estimado_kg': 70.96,
          'compras': [
            {'id': 'DL-0009', 'fecha': '2026-11-04', 'agricultor': 'Jhonatan', 'pergamino': 16.7, 'verde': 13.36, 'factor_pct': 80},
            {'id': 'DL-0008', 'fecha': '2026-11-04', 'agricultor': 'José Luis Gamboa Villano', 'pergamino': 72, 'verde': 57.6, 'factor_pct': 80},
          ],
          'movimientos': [
            {'fecha': '2026-11-03', 'tipo': 'Agregado', 'kg': 240, 'pergamino': 300, 'rendimiento_pct': 80, 'compras': [{'id': 'DL-0901', 'agricultor': 'Tito Lobato'}]}
          ],
          'tuestes': [{'id': 'e9', 'fecha': '2026-11-02T15:00:00Z', 'estado': 'completed', 'kg_verde': 100, 'kg_tostado': 80, 'producto': 'Blend de Caturra'}],
          'tuestes_total': 2,

        }
      }), 200);
    }
    if (p.endsWith('/lotes-verdes/g1')) {
      return http.Response(jsonEncode({
        'lote': {'id': 'g1', 'codigo': 'L-1', 'estado': 'available', 'kg_ahora': 760, 'kg_inicial': 1000, 'variedad': 'Catimor', 'cosecha': 2026, 'movimientos': [], 'tuestes': [], 'tuestes_total': 0}
      }), 200);
    }
    if (p.endsWith('/lotes-verdes/g8')) {
      return http.Response(jsonEncode({
        'lote': {'id': 'g8', 'codigo': 'L-8', 'estado': 'available', 'kg_ahora': 140, 'kg_inicial': 1000, 'producto': 'Essential', 'movimientos': [], 'tuestes': [], 'tuestes_total': 0}
      }), 200);
    }
    if (p.endsWith('/lotes-verdes/g7/compras')) {
      return http.Response(jsonEncode({
        'compras': [
          {'id': 'DL-0902', 'fecha': '2026-11-02', 'agricultor': 'Tito Lobato', 'estado': 'parchment', 'kg': 200},
          {'id': 'DL-0901', 'fecha': '2026-11-01', 'agricultor': 'Pedro Ramírez Ñique', 'estado': 'parchment', 'kg': 300},
        ]
      }), 200);
    }
    if (p.endsWith('/lotes-verdes/g7/agregar')) {
      return http.Response(jsonEncode({'ok': true, 'resultado': {'lote': 'L-7', 'kg_antes': 414, 'kg_despues': 654, 'rendimiento_pct': 80}}), 200);
    }
    if (p.endsWith('/lotes-verdes/g1/cerrar')) {
      return http.Response(jsonEncode({'ok': true, 'resultado': {'lote': 'L-1', 'kg_que_mostraba': 760}}), 200);
    }
    if (p.endsWith('/produccion/tostados/r8/cuenta') && req.url.queryParameters['producto'] == 'p3') {
      return http.Response(jsonEncode({
        'cuenta': {
          'lineas': [
            {'fecha': '2026-10-25', 'tipo': 'venta', 'titulo': 'Venta · pedido ORD-9', 'detalle': '2 × 20 kg', 'kg': -40, 'saldo': 340},
            {'fecha': '2026-10-20', 'tipo': 'tueste', 'titulo': 'Tueste · Essential', 'detalle': '80 kg tostados en total', 'kg': 380, 'saldo': 380},
          ],
          'total': 2, 'hay_mas': false, 'saldo': 340, 'entradas': 380, 'salidas': 40,
        }
      }), 200);
    }
    if (p.endsWith('/produccion/tostados/r8')) {
      return http.Response(jsonEncode({
        'tostado': {
          'id': 'r8', 'lote': 'L-8', 'tostado_el': '2026-10-20T15:00:00Z', 'terminado_el': '2026-10-20T15:14:00Z', 'kg_verde': 100, 'kg_tostado': 80,
          'merma_pct': 20, 'tostadora': 'Tostadora Villa Rica', 'tiempo_s': 780, 'notas': 'Buen desarrollo',
          'verde': {'lote': 'L-8', 'variedad': 'Geisha', 'cosecha': 2026, 'origen': 'Finca Rosal'},
          'productos': [{'nombre': 'Essential', 'asignado': 380, 'vendido': 40, 'disponible': 340}],
        }
      }), 200);
    }
    if (p.endsWith('/compras')) {
      final offset = int.parse(req.url.queryParameters['offset'] ?? '0');
      final todas = [
        {'id': 'DL-0001', 'fecha': '2026-11-03', 'agricultor': 'Pedro Ramírez Ñique', 'estado': 'parchment', 'kg': 100, 'producto': 'Blend de Caturra, Pache, typica', 'situacion': 'Sin precio'},
        {'id': 'DL-0002', 'fecha': '2026-11-02', 'agricultor': 'Agricultor Parte', 'estado': 'parchment', 'kg': 50, 'situacion': 'Pagado en parte', 'descuento': true, 'debe': 500},
        {'id': 'DL-0003', 'fecha': '2026-11-02', 'agricultor': 'Agricultor Rechazo', 'estado': 'cherry', 'kg': 20, 'situacion': 'Rechazado'},
        for (var i = 0; i < 24; i++) {'id': 'DL-1$i', 'fecha': '2026-10-01', 'agricultor': 'Agricultor ${i.toString().padLeft(2, '0')}', 'estado': 'cherry', 'kg': 10, 'situacion': 'Pagado', 'precio': 5},
      ];
      final pagina = todas.skip(offset).take(20).toList();
      return http.Response(jsonEncode({'compras': pagina, 'total': todas.length, 'hayMas': offset + 20 < todas.length}), 200);
    }
    if (p.contains('/proveedores/')) {
      return http.Response(jsonEncode({'proveedor': {
        'id': 'P-0001', 'nombre': 'Pedro Ramírez Ñique', 'tipo': 'person', 'comunidad': 'Sector Ejemplo', 'agricultor': true, 'vende': 'parchment',
        'comprador': false, 'procesos': [], 'documento': esDuenoMock ? '00000000' : null, 'telefono': esDuenoMock ? '999000000' : null,
        'cuentas': esDuenoMock ? [{'id': 5, 'tipo': 'bank_account', 'banco': 'BCP', 'numero': '000-0000000-0-00', 'titular': 'Pedro Ramírez Ñique'}] : null,
        'puede_editar': esDuenoMock,
        'adelantos_lista': esDuenoMock
            ? [{'id': 'ADV-007', 'fecha': '2026-11-01', 'monto': 500, 'usado': 300, 'devuelto': 0, 'saldo': 200, 'estado': 'partly_used'}]
            : null,
        'compras': {'n': 2, 'kg': 130, 'ultima': '2026-11-03'},
        'dinero': esDuenoMock ? {'comprado': 1800, 'debe': 300} : null, 'adelantos': esDuenoMock ? {'n': 1, 'saldo': 200} : null,
        'recientes': [{'id': 'DL-0001', 'fecha': '2026-11-03', 'estado': 'parchment', 'kg': 100}],
      }}), 200);
    }
    if (p.endsWith('/finanzas/lista')) {
      final filas = {
        'compras': [
          {'id': 'PU-0001', 'entrega': 'DL-0001', 'fecha': '2026-11-04', 'agricultor': 'Pedro Ramírez Ñique', 'kg': 100, 'total': 1800, 'pagado': 1500, 'debe': 300,
           'monto': 300, 'metodo': 'transfer', 'solicitud': 8, 'evidencias': 1, 'estado': 'Pendiente', 'espera': 0},
          {'id': 'PU-0002', 'entrega': 'DL-0002', 'fecha': '2026-11-02', 'agricultor': 'Agricultor Parte', 'kg': 50, 'total': 1000, 'pagado': 500, 'debe': 500,
           'monto': 200, 'metodo': 'advance', 'adelanto': 'ADV-007', 'solicitud': 9, 'estado': 'Urgente', 'espera': 9},
          {'id': 'PU-0003', 'entrega': 'DL-0003', 'fecha': '2026-10-20', 'agricultor': 'Agricultor Pagado', 'kg': 20, 'total': 400, 'pagado': 400, 'debe': 0, 'estado': 'Pagado'},
        ],
        'gastos': [
          {'id': 'EX-0001', 'fecha': '2026-11-01', 'categoria': 'Gas', 'descripcion': 'Gasolina', 'area': 'fulfillment', 'monto': 120, 'por': 'staff@x', 'estado': 'Pendiente', 'espera': 2, 'revisar': true},
          {'id': 'EX-0002', 'fecha': '2026-10-25', 'categoria': 'Mano de obra', 'descripcion': 'Jornal', 'area': 'farm', 'monto': 80, 'por': 'staff@x',
           'estado': 'Pagado', 'pagado_el': '2026-10-26', 'metodo': 'transfer', 'pagado_por': 'owner@x'},
        ],
        'adelantos': [
          {'id': 'SOL-0001', 'fecha': '2026-11-02', 'para': 'Misael Cusi', 'monto': 1500, 'motivo': 'Compras', 'por': 'misael@x', 'estado': 'Pendiente', 'espera': 1},
          {'id': 'SOL-0002', 'fecha': '2026-10-28', 'para': 'Tito Ejemplo', 'monto': 300, 'motivo': 'Abono', 'por': 'misael@x', 'estado': 'Rechazado',
           'decidido_el': '2026-10-29T10:00:00Z', 'motivo_rechazo': 'No ahora'},
        ],
      }[req.url.queryParameters['tipo']]!;
      return http.Response(jsonEncode({'filas': filas, 'total': filas.length, 'hayMas': false}), 200);
    }
    if (p.endsWith('/evidencias') && req.method == 'GET') {
      return http.Response(jsonEncode({'evidencias': [
        {'id': 3, 'tipo': 'image/jpeg', 'nota': 'Voucher', 'fecha': '2026-11-03T15:00:00Z', 'por': 'owner@x', 'url': null},
      ]}), 200);
    }
    if (p.endsWith('/evidencias') && req.method == 'POST') return http.Response(jsonEncode({'ok': true, 'evidencia': {'evidence_id': 4}}), 200);
    if (p.endsWith('/adelantos')) {
      return http.Response(jsonEncode({
        'porAprobar': [{'id': 'SOL-0001', 'request_date': '2026-11-02', 'party': 'Misael Cusi', 'amount': 1500, 'reason': 'Compras', 'created_by': 'misael@x'}],
        'adelantos': [
          {'id': 'ADV-007', 'party_id': 'P-0001', 'nombre': 'Pedro Ramírez Ñique', 'advance_date': '2026-11-01', 'amount': 500, 'used_in_coffee': 300, 'returned_in_money': 0, 'open_balance': 200, 'status': 'partly_used'},
          {'id': 'ADV-003', 'party_id': 'P-0002', 'nombre': 'Agricultor Dos', 'advance_date': '2026-10-01', 'amount': 400, 'used_in_coffee': 400, 'returned_in_money': 0, 'open_balance': 0, 'status': 'settled'},
        ],
        'hayMas': false,
      }), 200);
    }
    if (p.endsWith('/compras/DL-0002')) {
      return http.Response(jsonEncode({'compra': {
        'id': 'DL-0002', 'fecha': '2026-11-02', 'agricultor': 'Agricultor Parte', 'estado': 'parchment', 'kg': 50,
        'situacion': 'Pagado en parte', 'compra_id': 'PU-0002', 'debe': 500, 'solicitado': null,
        'adelantos': [{'id': 'ADV-007', 'saldo': 200, 'fecha': '2026-11-01'}], 'compra': null, 'pagos': [],
      }}), 200);
    }
    if (p.contains('/compras/')) {
      return http.Response(jsonEncode({'compra': {
        'id': 'DL-0001', 'fecha': '2026-11-03', 'agricultor': 'Pedro Ramírez Ñique', 'estado': 'parchment', 'kg': 100,
        'producto': 'Blend de Caturra, Pache, typica', 'situacion': 'Sin precio', 'lote': {'id': 'L-0001', 'calidad': 'pending'},
        'revision': {'humedad': 12.5, 'rendimiento': null}, 'registrado_por': 'misael@x', 'compra': null, 'pagos': [],
      }}), 200);
    }
    if (p.endsWith('/procesos')) {
      final dueno = esDuenoMock;
      return http.Response(jsonEncode({
        'compras': {
          'mes': {'recibidos': 2, 'kg': 130}, 'ultimo': '2026-11-03', 'sin_precio': {'n': 1, 'kg': 100},
          'por_pagar': dueno ? {'n': 1, 'total': 300} : null, 'adelantos': {'n': 1, 'saldo': 1500},
          'almacen': [{'estado': 'parchment', 'lotes': 2, 'kg': 130}],
          'recientes': [{'id': 'DL-0001', 'fecha': '2026-11-03', 'agricultor': 'Pedro Ramírez Ñique', 'estado': 'parchment', 'kg': 100, 'precio': null}],
        },
        'produccion': {
          // The Blend lot first (it grows), then the others; each with the product that uses it (4 Nov 2026).
          'lotes_verdes': [
            {'id': 'g7', 'codigo': 'L-7', 'kg_ahora': 414, 'kg_inicial': 1000, 'cosecha': 2026, 'variedad': 'Blend', 'producto': 'Blend de Caturra', 'crece': true, 'compras_n': 2, 'estimado_kg': 70.96},
            {'id': 'g1', 'codigo': 'L-1', 'kg_ahora': 760, 'kg_inicial': 1000, 'cosecha': 2026, 'variedad': 'Catimor'},
            {'id': 'g8', 'codigo': 'L-8', 'kg_ahora': 140, 'kg_inicial': 1000, 'cosecha': 2026, 'variedad': 'Blend', 'producto': 'Essential'},
          ],
          'verde_kg': 760,
          'tuestes': [
            {'id': 'e1', 'estado': 'in_progress', 'fecha': '2026-11-03T15:00:00Z', 'kg_verde': 20, 'lote': 'L-1', 'producto': 'Omagua 250 g'},
            {'id': 'e2', 'estado': 'planned', 'fecha': '2026-11-04T15:00:00Z', 'kg_verde': 30, 'lote': 'L-1', 'producto': 'Omagua 1 kg'},
          ],
          'mes': {'tuestes': 5, 'kg_verde': 820, 'kg_tostado': 683, 'merma_pct': 16.7},
          'tostado_kg': 385, 'por_procesar': [{'estado': 'parchment', 'calidad': 'pending', 'lotes': 2, 'kg': 88.7}],
          // By product, as the product screen counts it (production_summary_v2, 4 Nov 2026).
          'productos': [
            {'id': 'p3', 'nombre': 'Essential', 'kg_tostado': 340, 'lotes': [{'id': 'r8', 'lote': 'L-8', 'fecha': '2026-10-20', 'kg': 340}], 'tuestes': []},
            {'id': 'p1', 'nombre': 'Omagua 250 g', 'kg_tostado': 45, 'lotes': [{'lote': 'L-7', 'fecha': '2026-11-02', 'kg': 45}],
              'tuestes': [{'id': 'e1', 'estado': 'in_progress', 'fecha': '2026-11-03T15:00:00Z', 'kg_verde': 20, 'lote': 'L-1'}]},
            {'id': 'p2', 'nombre': 'Omagua 1 kg', 'kg_tostado': 0, 'lotes': [],
              'tuestes': [{'id': 'e2', 'estado': 'planned', 'fecha': '2026-11-04T15:00:00Z', 'kg_verde': 30, 'lote': 'L-1'}]},
          ],
        },
        'finca': {
          'gastos_mes': {'n': 2, 'total': dueno ? 180 : null}, 'gastos_anio': {'n': 5, 'total': 900},
          'por_pagar': {'total': 120}, 'parcelas': {'n': 3, 'hectareas': 6.5}, 'actividades_mes': 4,
          'cosecha': {'anio': 2026, 'kg': 0},
          'recientes': [{'id': 'EX-0009', 'fecha': '2026-11-02', 'categoria': 'Mano de obra', 'descripcion': 'Jornal deshierbo', 'estado': 'Pendiente de pago', 'monto': 120}],
        },
        'finanzas': dueno
            ? {
                'compras': {'n': 1, 'total': 300}, 'gastos': {'n': 1, 'total': 120}, 'adelantos': {'n': 1, 'total': 1500},
                'compras_por_pagar': [
                  {'id': 'PU-0001', 'entrega': 'DL-0001', 'fecha': '2026-11-04', 'agricultor': 'Pedro Ramírez Ñique', 'kg': 100, 'total': 1800, 'pagado': 1500, 'debe': 300,
                   'monto': 300, 'metodo': 'transfer', 'solicitud': 8, 'evidencias': 1},
                  {'id': 'PU-0002', 'entrega': 'DL-0002', 'fecha': '2026-11-02', 'agricultor': 'Agricultor Parte', 'kg': 50, 'total': 1000, 'pagado': 500, 'debe': 500,
                   'monto': 200, 'metodo': 'advance', 'adelanto': 'ADV-007', 'solicitud': 9},
                ],
                'gastos_por_pagar': [{'id': 'EX-0001', 'fecha': '2026-11-01', 'categoria': 'Gas', 'descripcion': 'Gasolina', 'area': 'fulfillment', 'monto': 120, 'por': 'staff@x'}],
                'adelantos_por_aprobar': [{'id': 'SOL-0001', 'fecha': '2026-11-02', 'para': 'Misael Cusi', 'monto': 1500, 'motivo': 'Compras', 'por': 'misael@x'}],
              }
            : {'solo_duenos': true},
        'logistica': {
          'por_despachar': 2, 'en_camino': 1, 'entregados_mes': 5, 'gastos_mes': {'n': 1, 'total': dueno ? 40 : null},
          'por_pagar': {'total': 40}, 'abiertos': 3,
          'pedidos': [
            {'numero': 'P-101', 'cliente': 'Cafe Uno', 'estado': 'pending', 'fecha': '2026-11-01T10:00:00Z'},
            {'numero': 'P-102', 'cliente': 'Cafe Dos', 'estado': 'shipped', 'fecha': '2026-11-02T10:00:00Z'},
          ],
        },
        if (!sinComercial) 'comercial': {'meses': [
          {'month': '${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}-01', 'orders': 3, 'total': 3000, 'unpaid': 3000},
        ]},
      }), 200);
    }
    if (p.contains('/tostador/events/')) return http.Response(jsonEncode({'ok': true}), 200);
    if (p.endsWith('/resumen')) return http.Response(jsonEncode({'rol': 'owner', 'meses': []}), 200);
    if (p.contains('/registrar/')) return http.Response(jsonEncode({'ok': true, 'result': {'expense_id': 'EX-0001'}}), 200);
    return http.Response(jsonEncode({'pedidos': [], 'total': 0}), 200);
  }

  setUp(() {
    pedidos.clear();
    sugerencia = {'area': 'fulfillment', 'cost_centre': 'coffee', 'source': 'to_review'};
    marcadas = ['farm', 'sourcing', 'production', 'commercial', 'fulfillment', 'finance'];
    sinComercial = false;
    dotenv.testLoad(fileInput: 'API_BASE_URL=https://api.test\nBUSINESS_ID=BIZ-002');
  });

  // Registrar gasto sin área fija ya no tiene botón (cada proceso tiene el suyo); el formulario se abre directo.
  Future<void> abrirGasto(WidgetTester tester) async {
    abrirFormularioParaPruebas(tester.element(find.byType(AdministracionTab)), 'gasto');
    await tester.pumpAndSettle();
  }

  Future<void> entrarFinanzas(WidgetTester tester) async {
    await tester.scrollUntilVisible(find.text('Finanzas'), 200, scrollable: find.byType(Scrollable).last);
    await http.runWithClient(() async {
      await tester.tap(find.text('Finanzas'));
      await tester.pumpAndSettle();
    }, () => MockClient((req) async => responder(req)));
  }

  Future<void> abrir(WidgetTester tester, {required String rol}) async {
    // An iPhone-sized screen (390 x 844 points).
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    esDuenoMock = rol == 'owner';
    SharedPreferences.setMockInitialValues({'business_role': rol, 'mi_area_elegidas': marcadas});
    await http.runWithClient(() async {
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: AdministracionTab())));
      await tester.pumpAndSettle();
    }, () => MockClient((req) async => responder(req)));
  }

  testWidgets('two parts (Pendientes was removed on 4 Nov 2026); staff ask, only the owner sees money buttons', (tester) async {
    await abrir(tester, rol: 'staff');
    expect(find.text('Administración'), findsOneWidget);
    for (final t in ['Procesos', 'Resumen']) {
      expect(find.text(t), findsOneWidget);
    }
    expect(find.text('Pendientes'), findsNothing);
    expect(find.text('Solicitudes'), findsNothing);
    // Registrar: one card per process, with its summary, and Registrar gasto below.
    // Each card shows its 2 most important data; the other 2 are inside.
    for (final t in ['Comercialización', 'Producción', 'Compras', 'Café verde', 'Café tostado', '760 kg', 'Comprado', 'Sin precio']) {
      expect(find.text(t), findsOneWidget, reason: t);
    }
    for (final t in ['Lotes de tostado este mes', 'Merma', 'En almacén', 'Última compra']) {
      expect(find.text(t), findsNothing, reason: t);
    }
    // Registrar gasto and the cash withdrawal live inside the processes (3 Nov 2026).
    expect(find.text('Registrar gasto'), findsNothing);
    // Always 4 data per process; staff never see money.
    expect(find.text('Por pagar'), findsNothing);
    expect(find.text('Adelantos abiertos'), findsNothing);
    expect(find.text('Registrar retiro de efectivo'), findsNothing);
    await http.runWithClient(() async {
      await tester.tap(find.text('Compras'));
      await tester.pumpAndSettle();
    }, () => MockClient((req) async => responder(req)));
    for (final t in ['Registrar compra', 'Solicitar adelanto', 'Registrar proveedor', 'Registrar gasto', 'Adelantos', 'Pedro Ramírez Ñique']) {
      expect(find.text(t), findsOneWidget);
    }
    expect(find.text('Pagar compras'), findsNothing);
    expect(find.text('Ingreso de dinero'), findsNothing);
  });

  testWidgets('Compras requests the payment; Finanzas pays and has the cash withdrawal', (tester) async {
    await abrir(tester, rol: 'owner');
    for (final t in ['Comprado', 'S/ 300']) {
      expect(find.text(t), findsWidgets, reason: t);
    }
    expect(find.text('Adelantos abiertos'), findsNothing); // inside Compras, not on the card
    await http.runWithClient(() async {
      await tester.tap(find.text('Compras'));
      await tester.pumpAndSettle();
    }, () => MockClient((req) async => responder(req)));
    expect(find.text('Pagar compras'), findsNothing);
    expect(find.text('Registrar retiro de efectivo'), findsNothing);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await entrarFinanzas(tester);
    for (final t in ['Registrar retiro de efectivo', 'Compras', 'Gastos', 'Adelantos', 'Proveedores', 'Pedro Ramírez Ñique']) {
      expect(find.text(t), findsOneWidget, reason: t);
    }
  });

  testWidgets('an advance is a request: no payment fields', (tester) async {
    await abrir(tester, rol: 'staff');
    await http.runWithClient(() async {
      await tester.tap(find.text('Compras'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Solicitar adelanto'));
      await tester.pumpAndSettle();
    }, () => MockClient((req) async => responder(req)));
    expect(find.text('Para'), findsOneWidget);
    expect(find.textContaining('Cómo se'), findsNothing);
    expect(find.textContaining('Número de operación'), findsNothing);
  });

  testWidgets('the owner approves an advance in Finanzas, choosing how it is paid', (tester) async {
    await abrir(tester, rol: 'owner');
    await entrarFinanzas(tester);
    await http.runWithClient(() async {
      await tester.tap(find.text('Adelantos').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Misael Cusi'));
      await tester.pumpAndSettle();
      expect(find.text('Rechazar'), findsOneWidget); // two actions: a small menu
      await tester.tap(find.text('Aprobar y entregar'));
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

  testWidgets('Finanzas pays a compra by transfer without asking for the operation number (the bank fills it in)', (tester) async {
    await abrir(tester, rol: 'owner');
    await entrarFinanzas(tester);
    await http.runWithClient(() async {
      await tester.tap(find.text('Pedro Ramírez Ñique'));
      await tester.pumpAndSettle();
      expect(find.text('Subir evidencia'), findsOneWidget); // the row opens what can be done with it
      await tester.tap(find.text('Pagar compra'));
      await tester.pumpAndSettle();
      expect(find.text('Pagar compra'), findsOneWidget);
      expect(find.text('Transferencia'), findsOneWidget);
      expect(find.textContaining('Número de operación'), findsNothing);
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
      // After paying, the evidence is offered at once (the row then leaves Finanzas).
      expect(find.text('¿Subir la evidencia?'), findsOneWidget);
      await tester.tap(find.text('Después'));
      await tester.pumpAndSettle();
    }, () => MockClient((req) async => responder(req)));
    final r = pedidos.lastWhere((r) => r.url.path.contains('/registrar/'));
    expect(r.url.path, endsWith('/registrar/pago'));
    final body = jsonDecode(r.body) as Map;
    expect(body['compraId'], 'PU-0001');
    expect(body['metodo'], 'transfer');
    expect(body.containsKey('operacion'), isFalse);
  });

  testWidgets('Proveedor asks what a farmer sells only for a farmer', (tester) async {
    await abrir(tester, rol: 'staff');
    await http.runWithClient(() async {
      await tester.tap(find.text('Compras'));
      await tester.pumpAndSettle();
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
      await abrirGasto(tester);
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
    await abrirGasto(tester);
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
      await abrirGasto(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Combustible'));
      await tester.pumpAndSettle();
    }, () => MockClient((req) async => responder(req)));
    expect(find.textContaining('Área: Logística'), findsOneWidget);
  });

  testWidgets('Personal is under Ver más categorías even if the database marks it main', (tester) async {
    await abrir(tester, rol: 'staff');
    await http.runWithClient(() async {
      await abrirGasto(tester);
      await tester.pumpAndSettle();
    }, () => MockClient((req) async => responder(req)));
    expect(find.text('Personal'), findsNothing);
    await tester.tap(find.text('Ver más categorías'));
    await tester.pumpAndSettle();
    expect(find.text('Personal'), findsOneWidget);
  });

  testWidgets('Registrar gasto opens with Combustible first and already chosen', (tester) async {
    await abrir(tester, rol: 'staff');
    await http.runWithClient(() async {
      await abrirGasto(tester);
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
      await abrirGasto(tester);
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

  testWidgets('fuel: no "Para qué" question; the area is left to the database', (tester) async {
    await abrir(tester, rol: 'staff');
    await http.runWithClient(() async {
      await abrirGasto(tester);
      await tester.pumpAndSettle();
      expect(find.textContaining('Para qué fue'), findsNothing);
      expect(find.textContaining('(automático)'), findsOneWidget);
      await tester.enterText(find.byType(TextField).first, '50');
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
    }, () => MockClient((req) async => responder(req)));
    final r = pedidos.lastWhere((r) => r.url.path.contains('/registrar/'));
    final body = jsonDecode(r.body) as Map;
    expect(body['categoria'], 'Combustible');
    expect(body.containsKey('paraQue'), isFalse);
    expect(body.containsKey('area'), isFalse);
  });

  testWidgets('fuel: a purchase that day sets the area with no question', (tester) async {
    sugerencia = {'area': 'sourcing', 'cost_centre': 'coffee', 'source': 'same_day', 'delivery_id': 'DL-0009'};
    await abrir(tester, rol: 'staff');
    await http.runWithClient(() async {
      await abrirGasto(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Combustible'));
      await tester.pumpAndSettle();
    }, () => MockClient((req) async => responder(req)));
    expect(find.textContaining('Para qué fue'), findsNothing);
    expect(find.textContaining('Área: Compras (automático)'), findsOneWidget);
  });

  testWidgets('the owner says what fuel nobody could place was for, from its detail in Finanzas', (tester) async {
    await abrir(tester, rol: 'owner');
    await entrarFinanzas(tester);
    await http.runWithClient(() async {
      await tester.tap(find.text('Gastos').last);
      await tester.pumpAndSettle();
      expect(find.textContaining('Logística por revisar'), findsOneWidget);
      await tester.tap(find.text('Gas'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Elegir para qué fue'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Compra de café'));
      await tester.pumpAndSettle();
    }, () => MockClient((req) async => responder(req)));
    final r = pedidos.lastWhere((r) => r.url.path.endsWith('/registrar/corregirArea'));
    expect(jsonDecode(r.body), containsPair('area', 'sourcing'));
    expect(jsonDecode(r.body), containsPair('gastoId', 'EX-0001'));
  });

  testWidgets('a gasto whose area is known has no Elegir para qué fue', (tester) async {
    await abrir(tester, rol: 'owner');
    await entrarFinanzas(tester);
    await http.runWithClient(() async {
      await tester.tap(find.text('Gastos').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mano de obra'));
      await tester.pumpAndSettle();
    }, () => MockClient((req) async => responder(req)));
    expect(find.text('Elegir para qué fue'), findsNothing);
  });

  testWidgets('choosing a farmer: a search screen in pages, closed with the X, nothing chosen', (tester) async {
    await abrir(tester, rol: 'staff');
    await http.runWithClient(() async {
      await tester.tap(find.text('Compras'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Registrar compra'));
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
      await tester.tap(find.text('Compras'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Registrar compra'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Agricultor'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Agricultor 25'), 300, scrollable: find.byType(Scrollable).last);
      await tester.pumpAndSettle();
    }, () => MockClient((req) async => responder(req)));
    expect(find.text('Agricultor 25'), findsOneWidget);
    expect(pedidos.where((r) => r.url.path.endsWith('/personas/buscar')).map((r) => r.url.queryParameters['offset']).toSet(), containsAll(['0', '20']));
  });

  testWidgets('the coffee button says it records coffee we received', (tester) async {
    await abrir(tester, rol: 'staff');
    expect(find.text('Registrar entrega'), findsNothing);
    await http.runWithClient(() async {
      await tester.tap(find.text('Compras'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Registrar compra'));
      await tester.pumpAndSettle();
    }, () => MockClient((req) async => responder(req)));
    expect(find.text('Registrar compra'), findsOneWidget); // the form title repeats the button
  });

  testWidgets('Registrar compra does not ask who collected it', (tester) async {
    await abrir(tester, rol: 'staff');
    await http.runWithClient(() async {
      await tester.tap(find.text('Compras'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Registrar compra'));
      await tester.pumpAndSettle();
    }, () => MockClient((req) async => responder(req)));
    expect(find.textContaining('Recogido por'), findsNothing);
    expect(find.text('Agricultor'), findsOneWidget);
  });

  testWidgets('choosing a farmer by nickname fills the field', (tester) async {
    await abrir(tester, rol: 'staff');
    await http.runWithClient(() async {
      await tester.tap(find.text('Compras'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Registrar compra'));
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
      await abrirGasto(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ver más categorías'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Otro'));
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
    await abrirGasto(tester);
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
    await abrirGasto(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Cancelar'));
    await tester.pumpAndSettle();
    expect(find.text('Guardar'), findsNothing);
    expect(find.text('Procesos'), findsOneWidget);
    expect(pedidos.where((r) => r.url.path.contains('/registrar/')), isEmpty);
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

  testWidgets('Producción shows the green lots and the roasts, with Iniciar and Finalizar', (tester) async {
    await abrir(tester, rol: 'staff');
    await http.runWithClient(() async {
      await tester.tap(find.text('Producción'));
      await tester.pumpAndSettle();
    }, () => MockClient((req) async => responder(req)));
    // Opens on Café verde, the first tab, then Tostado, Proveedores and Gastos (4 Nov 2026).
    // "Tuestes" is now "Lotes de tostado" and "Lotes" is "Café verde" (4 Nov 2026).
    expect(find.text('Tuestes'), findsNothing);
    expect(find.text('Lotes'), findsNothing);
    for (final t in ['L-1', 'Catimor · cosecha 2026', '760 kg / 1,000 kg', '76%']) {
      expect(find.text(t), findsOneWidget, reason: t);
    }
    expect(find.text('Finalizar'), findsNothing);
    await tester.tap(find.text('Tostado').last);
    await tester.pump();
    // Roasted coffee by product, the same as the product screen (4 Nov 2026): each product with its kilos, its lots
    // and its roasts in progress or planned.
    for (final t in ['Tostar café', 'Registrar gasto', 'Essential', 'Omagua 250 g', 'Omagua 1 kg',
        'Martes 20 de octubre', 'Lunes 2 de noviembre', 'L-8', 'L-7', 'Tostando', 'Programado']) {
      expect(find.text(t), findsOneWidget, reason: t);
    }
    // Only the date on each lot: everything here is roasted, so "Tostado" is not repeated (4 Nov 2026).
    expect(find.textContaining('Tostado el'), findsNothing);
    // No title or total on top, and the kilos only once: on the lot (4 Nov 2026).
    expect(find.text('Café tostado por producto'), findsNothing);
    expect(find.text('385 kg'), findsNothing);
    expect(find.text('340 kg'), findsOneWidget);
    // In the order the database sends: the order of the Productos tab.
    final orden = ['Essential', 'Omagua 250 g', 'Omagua 1 kg'].map((t) => tester.getTopLeft(find.text(t)).dy).toList();
    expect(orden[0] < orden[1] && orden[1] < orden[2], isTrue);
    // A roasted lot opens its detail.
    await http.runWithClient(() async {
      await tester.tap(find.text('Martes 20 de octubre'));
      await tester.pumpAndSettle();
    }, () => MockClient((req) async => responder(req)));
    for (final t in ['Lote de tostado', 'Café verde que entró', '100 kg', '80 kg', '20%', 'Asignado', '380 kg', 'Vendido', '40 kg', 'Disponible',
        'Tostadora Villa Rica', '13:00 min']) {
      expect(find.text(t), findsWidgets, reason: t);
    }
    await tester.scrollUntilVisible(find.text('Buen desarrollo'), 200, scrollable: find.byType(Scrollable).last);
    expect(find.text('Finca Rosal'), findsWidgets);
    expect(find.text('Temperatura de carga'), findsNothing); // not recorded, so not shown
    // Estado de lote, like the green lots (4 Nov 2026): the roast adds, each sale takes out, with the balance.
    await tester.scrollUntilVisible(find.text('Venta · pedido ORD-9'), 200, scrollable: find.byType(Scrollable).last);
    for (final t in ['Estado de lote', 'Tueste · Essential', '+380 kg', '−40 kg', 'Saldo 340 kg']) {
      expect(find.text(t), findsOneWidget, reason: t);
    }
    expect(pedidos.lastWhere((r) => r.url.path.endsWith('/tostados/r8/cuenta')).url.queryParameters['offset'], '0');
    expect(tester.takeException(), isNull);
    await tester.pageBack();
    await tester.pumpAndSettle();
    // No data on top, like Compras (4 Nov 2026): the Procesos card already shows it.
    for (final t in ['16.7%', '820 kg → 683 kg', '1 tostando ahora']) {
      expect(find.text(t), findsNothing, reason: t);
    }
    expect(find.text('Finalizar'), findsOneWidget); // the roast in progress
    expect(find.text('Iniciar'), findsOneWidget); // the planned one
  });

  testWidgets('Café verde: each lot opens its detail; the Blend lot lists its compras with the estimate; Cerrar lote after the count', (tester) async {
    await abrir(tester, rol: 'owner');
    Future<void> tocar(Finder f) => http.runWithClient(() async {
          await tester.ensureVisible(f);
          await tester.tap(f);
          await tester.pumpAndSettle();
        }, () => MockClient((req) async => responder(req)));
    await tocar(find.text('Producción'));
    expect(find.textContaining('Blend de Caturra · lote del Blend'), findsOneWidget);
    expect(find.text('Essential'), findsOneWidget);
    // Each Blend compra adds 80% of its parchment as estimated green to the lot by itself (4 Nov 2026).
    expect(find.text('2 compras · 71.0 kg de verde estimado'), findsOneWidget);
    // The actions are inside each lot's detail, not on the list (4 Nov 2026).
    expect(find.text('Agregar café al lote'), findsNothing);
    expect(find.text('Cerrar lote'), findsNothing);

    // L-8 is Essential's coffee: its detail has no action.
    await tocar(find.text('L-8'));
    expect(find.text('Lote L-8'), findsOneWidget);
    expect(find.text('Agregar café al lote'), findsNothing);
    expect(find.text('Cerrar lote'), findsNothing);
    await tester.pageBack();
    await tester.pumpAndSettle();

    // L-1: Cerrar lote, only after a count of 0 kg. The two fields are apart, never touching.
    await tocar(find.text('L-1'));
    expect(find.text('Agregar café al lote'), findsNothing);
    await tocar(find.text('Cerrar lote'));
    expect(find.text('¿Cerrar el lote L-1?'), findsOneWidget);
    final kg = tester.getRect(find.widgetWithText(TextField, 'Kilos que encontró el conteo'));
    final motivo = tester.getRect(find.widgetWithText(TextField, 'Motivo'));
    expect(motivo.top - kg.bottom, greaterThanOrEqualTo(12));
    await tester.enterText(find.widgetWithText(TextField, 'Kilos que encontró el conteo'), '120');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Cerrar lote'));
    await tester.pump();
    expect(find.textContaining('El conteo encontró café'), findsOneWidget);
    expect(pedidos.any((r) => r.url.path.endsWith('/cerrar')), isFalse);
    await tester.enterText(find.widgetWithText(TextField, 'Kilos que encontró el conteo'), '0');
    await tester.enterText(find.widgetWithText(TextField, 'Motivo'), 'Conteo del 5 nov: sin sacos');
    await tocar(find.widgetWithText(ElevatedButton, 'Cerrar lote'));
    final cierre = pedidos.lastWhere((r) => r.url.path.endsWith('/lotes-verdes/g1/cerrar'));
    expect(jsonDecode(cierre.body)['kgContados'], 0);
    expect(jsonDecode(cierre.body)['motivo'], 'Conteo del 5 nov: sin sacos');
    expect(find.text('Lote L-1'), findsNothing); // a closed lot goes back to the list

    // L-7, the Blend lot: its data and its account statement.
    await tocar(find.text('L-7'));
    for (final t in ['Lote L-7', 'Lote del Blend: crece con café pilado']) {
      expect(find.text(t), findsOneWidget, reason: t);
    }
    // One list, like an account statement: compras +, roasts and green sales −, with the balance after each line.
    for (final t in ['Saldo', 'Entradas', '+1,071.0 kg', 'Salidas', '−586 kg']) {
      expect(find.text(t), findsOneWidget, reason: t);
    }
    final lista = find.byType(Scrollable).last;
    await tester.scrollUntilVisible(find.text('Compra DL-0008 · José Luis Gamboa Villano'), 200, scrollable: lista);
    for (final t in ['Estado de lote', '+57.6 kg', 'Saldo 485.0 kg']) {
      expect(find.text(t), findsWidgets, reason: t);
    }
    expect(find.text('25'), findsOneWidget); // the count on the title is all the lines, not the page
    // What comes in is green and what goes out is orange (4 Nov 2026).
    expect(tester.widget<Text>(find.text('+57.6 kg')).style?.color, Colors.green.shade800);
    await tester.scrollUntilVisible(find.text('−100 kg'), 200, scrollable: lista);
    expect(tester.widget<Text>(find.text('−100 kg')).style?.color, Colors.orange.shade800);
    for (final t in ['Tueste · Blend de Caturra', 'Venta de café verde · pedido ORD-1', '−72 kg']) {
      expect(find.text(t), findsOneWidget, reason: t);
    }
    // 20 lines a page: the second page is asked to the server only near the end of the list.
    final cuentas = () => pedidos.where((r) => r.url.path.endsWith('/lotes-verdes/g7/cuenta')).toList();
    expect(cuentas().map((r) => r.url.queryParameters['offset']), ['0']);
    expect(find.text('Entrada inicial'), findsNothing);
    await http.runWithClient(() async {
      await tester.scrollUntilVisible(find.text('Entrada inicial'), 300, scrollable: lista);
      await tester.pumpAndSettle();
    }, () => MockClient((req) async => responder(req)));
    expect(cuentas().map((r) => r.url.queryParameters['offset']), ['0', '20']);
    for (final t in ['Tueste antiguo 19', '+1,000 kg', 'Saldo 1,000 kg']) {
      expect(find.text(t), findsOneWidget, reason: t);
    }
    expect(find.textContaining('en total'), findsNothing); // no text at the end of a list
    expect(find.text('Compras del lote'), findsNothing);
    expect(find.text('Tuestes con este lote'), findsNothing);
    // No Agregar café al lote any more: the estimate is added by itself (4 Nov 2026).
    expect(find.text('Agregar café al lote'), findsNothing);
    expect(find.text('Cerrar lote'), findsNothing); // the Blend lot stays open
    expect(tester.takeException(), isNull);
  });

  testWidgets('staff open a green lot and see its data, but not Cerrar lote', (tester) async {
    await abrir(tester, rol: 'staff');
    await http.runWithClient(() async {
      await tester.tap(find.text('Producción'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('L-1'));
      await tester.pumpAndSettle();
    }, () => MockClient((req) async => responder(req)));
    expect(find.text('Lote L-1'), findsOneWidget);
    expect(find.text('Agregar café al lote'), findsNothing);
    expect(find.text('Cerrar lote'), findsNothing);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Café comprado por procesar'), findsNothing); // removed from Café verde (4 Nov 2026)
  });

  testWidgets('Producción copies Compras: a Gastos tab after Proveedores, and the PDF button with its own report', (tester) async {
    await abrir(tester, rol: 'owner');
    await http.runWithClient(() async {
      await tester.tap(find.text('Producción'));
      await tester.pumpAndSettle();
      final tabs = ['Café verde', 'Tostado', 'Proveedores', 'Gastos'].map((t) => tester.getCenter(find.text(t).last).dx).toList();
      for (var i = 1; i < tabs.length; i++) {
        expect(tabs[i], greaterThan(tabs[i - 1]));
      }
      // The long name gets the widest tab, so it is not shrunk on the iPhone (4 Nov 2026).
      double ancho(String t) => tester.getSize(find.ancestor(of: find.text(t).last, matching: find.byType(InkWell)).first).width;
      expect(ancho('Café verde'), greaterThan(ancho('Gastos')));
      expect(find.text('Lotes de tostado'), findsNothing); // the tab is "Tostado" now (4 Nov 2026)
      await tester.tap(find.text('Gastos').last);
      await tester.pumpAndSettle();
    }, () => MockClient((req) async => responder(req)));
    expect(pedidos.any((r) => r.url.path.endsWith('/gastos-area') && r.url.queryParameters['area'] == 'production'), isTrue);
    await http.runWithClient(() async {
      await tester.tap(find.byIcon(Icons.picture_as_pdf_outlined));
      await tester.pumpAndSettle();
      expect(find.text('Generar reporte'), findsWidgets);
      await tester.tap(find.text('Generar PDF'));
      await tester.pumpAndSettle();
    }, () => MockClient((req) async => responder(req)));
    final hoy = DateTime.now();
    final mes = '${hoy.year}-${hoy.month.toString().padLeft(2, '0')}';
    final r = pedidos.lastWhere((r) => r.url.path.endsWith('/produccion/reporte'));
    expect(r.url.queryParameters, {'desde': mes, 'hasta': mes});
    expect(pedidos.any((r) => r.url.path.endsWith('/compras/reporte')), isFalse);
  });

  testWidgets('Finalizar asks the roasted kilos and never more than the green coffee', (tester) async {
    await abrir(tester, rol: 'staff');
    await http.runWithClient(() async {
      await tester.tap(find.text('Producción'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tostado').last); // Café verde is the first tab now (4 Nov 2026)
      await tester.pump();
      await tester.tap(find.text('Finalizar'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'Kilos de café tostado'), '25');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Finalizar tueste'));
      await tester.pumpAndSettle();
      expect(find.textContaining('No puede salir más que el café verde'), findsOneWidget);
      await tester.enterText(find.widgetWithText(TextField, 'Kilos de café tostado'), '16,8');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Finalizar tueste'));
      await tester.pumpAndSettle();
    }, () => MockClient((req) async => responder(req)));
    final req = pedidos.lastWhere((r) => r.url.path.contains('/complete-admin'));
    expect(jsonDecode(req.body)['outKg'], 16.8);
  });

  testWidgets('a gasto from Producción always goes to the Producción area', (tester) async {
    await abrir(tester, rol: 'staff');
    await http.runWithClient(() async {
      await tester.tap(find.text('Producción'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Registrar gasto'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'Monto (S/)'), '45');
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
    }, () => MockClient((req) async => responder(req)));
    final req = pedidos.lastWhere((r) => r.url.path.endsWith('/registrar/gasto'));
    expect(jsonDecode(req.body)['area'], 'production');
  });

  testWidgets('cards in the GM\'s order (Comercialización, Producción, Compras, Finca), three in sight on an iPhone', (tester) async {
    await abrir(tester, rol: 'owner');
    final arriba = [for (final t in ['Comercialización', 'Producción', 'Compras']) tester.getTopLeft(find.text(t)).dy];
    expect(arriba, orderedEquals([...arriba]..sort()));
    // On the phone the app bar and the bottom tabs take about 190 points of the 844.
    final abajo = tester.getBottomLeft(find.text('S/ 300')).dy;
    expect(abajo, lessThan(844 - 190), reason: 'bottom of the Compras card at $abajo');
    await tester.scrollUntilVisible(find.text('Finca'), 200, scrollable: find.byType(Scrollable).last);
    expect(tester.getTopLeft(find.text('Finca')).dy, greaterThan(tester.getTopLeft(find.text('Compras')).dy));
  });

  testWidgets('Finca redesigned with Farm (4 Nov 2026): no data on top, Gastos 20 a page that open their detail, Proveedores, PDF', (tester) async {
    await abrir(tester, rol: 'staff');
    await tester.scrollUntilVisible(find.text('Finca'), 200, scrollable: find.byType(Scrollable).last);
    expect(find.text('Cosecha'), findsOneWidget); // the Procesos card keeps its indicators
    await http.runWithClient(() async {
      await tester.tap(find.text('Finca'));
      await tester.pumpAndSettle();
    }, () => MockClient((req) async => responder(req)));
    expect(find.text('Cosecha'), findsNothing); // no data on top of the screen
    for (final t in ['Registrar gasto', 'Gastos', 'Proveedores', 'Mano de obra', 'Pagado']) {
      expect(find.text(t), findsWidgets, reason: t);
    }
    expect(find.byIcon(Icons.picture_as_pdf_outlined), findsOneWidget);
    final g = pedidos.lastWhere((r) => r.url.path.endsWith('/gastos-area'));
    expect(g.url.queryParameters['area'], 'farm');
    expect(g.url.queryParameters['limit'], '20');
    // A gasto opens its detail; staff do not see the evidence.
    await tester.tap(find.text('Mano de obra'));
    await tester.pumpAndSettle();
    for (final t in ['Gasto', 'Jornal deshierbo', 'EX-0003']) {
      expect(find.text(t), findsWidgets, reason: t);
    }
    expect(find.text('Ver evidencia'), findsNothing);
    await tester.pageBack();
    await tester.pumpAndSettle();
    // Registrar gasto keeps the Finca area.
    await http.runWithClient(() async {
      await tester.tap(find.text('Registrar gasto'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'Monto (S/)'), '60');
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
    }, () => MockClient((req) async => responder(req)));
    final req = pedidos.lastWhere((r) => r.url.path.endsWith('/registrar/gasto'));
    expect(jsonDecode(req.body)['area'], 'farm');
    expect(tester.takeException(), isNull);
  });

  testWidgets('Finanzas redesigned with Finance (4 Nov 2026): no data on top, tabs without numbers, Proveedores and the PDF', (tester) async {
    await abrir(tester, rol: 'owner');
    await tester.scrollUntilVisible(find.text('Finanzas'), 200, scrollable: find.byType(Scrollable).last);
    await http.runWithClient(() async {
      await tester.tap(find.text('Finanzas'));
      await tester.pumpAndSettle();
    }, () => MockClient((req) async => responder(req)));
    expect(find.textContaining('Compras ('), findsNothing);
    expect(find.text('Adelantos por aprobar'), findsNothing); // the indicators stay on the Procesos card
    expect(find.byIcon(Icons.picture_as_pdf_outlined), findsOneWidget);
    await http.runWithClient(() async {
      await tester.tap(find.text('Proveedores').last);
      await tester.pumpAndSettle();
    }, () => MockClient((req) async => responder(req)));
    expect(pedidos.any((r) => r.url.path.endsWith('/personas/buscar') && r.url.queryParameters['area'] == 'finance'), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Comercialización like the other processes (4 Nov 2026): no data on top, 5 tabs, orders, customers and products 20 a page, PDF', (tester) async {
    await abrir(tester, rol: 'owner');
    await tester.scrollUntilVisible(find.text('Vendido este mes'), 200, scrollable: find.byType(Scrollable).last);
    expect(find.text('Comercialización'), findsOneWidget); // the first card keeps its indicators
    await http.runWithClient(() async {
      await tester.tap(find.text('Comercialización'));
      await tester.pumpAndSettle();
    }, () => MockClient((req) async => responder(req)));
    expect(find.text('Reporte de ventas'), findsNothing); // the old report is gone
    expect(find.text('Ticket promedio'), findsNothing); // no data on top
    for (final t in ['Registrar pedido', 'Registrar gasto', 'Pedidos', 'Clientes', 'Productos', 'Proveedores', 'Gastos']) {
      expect(find.text(t), findsWidgets, reason: t);
    }
    expect(find.byIcon(Icons.picture_as_pdf_outlined), findsOneWidget);
    // Pedidos: 20 a page, newest first; each opens the order detail.
    final ped = pedidos.lastWhere((r) => r.url.path.contains('/api/pedidos/'));
    expect(ped.url.queryParameters['limite'], '20');
    expect(find.text('Cafe Venta'), findsOneWidget);
    // Clientes: from the orders; each opens its detail with its orders.
    await http.runWithClient(() async {
      await tester.tap(find.text('Clientes').last);
      await tester.pumpAndSettle();
    }, () => MockClient((req) async => responder(req)));
    expect(pedidos.any((r) => r.url.path.endsWith('/comercial/clientes') && r.url.queryParameters['limit'] == '20'), isTrue);
    expect(find.text('Cafe Uno'), findsOneWidget);
    expect(find.textContaining('2 pedidos · S/ 150'), findsOneWidget);
    await http.runWithClient(() async {
      await tester.tap(find.text('Cafe Uno'));
      await tester.pumpAndSettle();
    }, () => MockClient((req) async => responder(req)));
    for (final t in ['Cliente', 'Total comprado', 'Último pedido']) {
      expect(find.text(t), findsOneWidget, reason: t);
    }
    expect(pedidos.lastWhere((r) => r.url.path.contains('/api/pedidos/')).url.queryParameters['cliente'], 'Cafe Uno');
    await tester.pageBack();
    await tester.pumpAndSettle();
    // Productos: the best sellers this year, information only.
    await http.runWithClient(() async {
      await tester.tap(find.text('Productos').last);
      await tester.pumpAndSettle();
    }, () => MockClient((req) async => responder(req)));
    for (final t in ['Más vendidos este año', 'Blend', '3 uds.']) {
      expect(find.text(t), findsOneWidget, reason: t);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('Resumen points to Comercialización for the sales', (tester) async {
    await abrir(tester, rol: 'staff');
    await tester.tap(find.text('Resumen'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Las ventas están en Procesos → Comercialización'), findsOneWidget);
  });

  testWidgets('Registrar shows only the cards of the areas ticked in Perfil', (tester) async {
    marcadas = ['sourcing'];
    await abrir(tester, rol: 'owner');
    expect(find.text('Compras'), findsOneWidget);
    for (final t in ['Finca', 'Producción', 'Comercialización']) {
      expect(find.text(t), findsNothing, reason: t);
    }
  });

  testWidgets('with no process area ticked, Registrar says where to tick them', (tester) async {
    marcadas = ['finance'];
    await abrir(tester, rol: 'staff');
    expect(find.text('Compras'), findsNothing);
    expect(find.textContaining('Perfil → Mis áreas'), findsOneWidget);
  });

  testWidgets('a process the server does not send (not the person\'s area) has no card even if ticked', (tester) async {
    sinComercial = true;
    await abrir(tester, rol: 'staff');
    expect(find.text('Compras'), findsOneWidget);
    expect(find.text('Comercialización'), findsNothing);
  });

  testWidgets('Compras lists the farmers in pages of 20, searchable, each opening its detail', (tester) async {
    await abrir(tester, rol: 'staff');
    await http.runWithClient(() async {
      await tester.tap(find.text('Compras'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Proveedores'));
      await tester.pumpAndSettle();
      expect(find.text('31'), findsOneWidget); // the count goes in the header, never at the end
      final primero = pedidos.lastWhere((r) => r.url.path.endsWith('/personas/buscar'));
      expect(primero.url.queryParameters['rol'], 'agricultor'); // Compras: only the farmers who sell coffee
      expect(pedidos.where((r) => r.url.path.endsWith('/personas/buscar')).length, 1); // only the first page
      await tester.enterText(find.widgetWithText(TextField, 'Buscar por nombre o apodo'), 'chato');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(find.text('Pedro Ramírez Ñique'), findsOneWidget); // found by nickname
      expect(find.text('1'), findsWidgets);
      expect(find.byIcon(Icons.chevron_right), findsWidgets); // each provider opens its detail
      await tester.enterText(find.widgetWithText(TextField, 'Buscar por nombre o apodo'), '');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      final antes = pedidos.where((r) => r.url.path.endsWith('/personas/buscar')).length;
      await tester.drag(find.text('31'), const Offset(0, -3000));
      await tester.pumpAndSettle();
      expect(pedidos.where((r) => r.url.path.endsWith('/personas/buscar')).length, greaterThan(antes)); // next page
    }, () => MockClient((req) async => responder(req)));
  });

  testWidgets('Finca and Producción list their own providers', (tester) async {
    await abrir(tester, rol: 'owner');
    await http.runWithClient(() async {
      await tester.tap(find.text('Producción'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Proveedores'));
      await tester.pumpAndSettle();
    }, () => MockClient((req) async => responder(req)));
    expect(pedidos.lastWhere((r) => r.url.path.endsWith('/personas/buscar')).url.queryParameters['area'], 'production');
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Finca'), 200, scrollable: find.byType(Scrollable).last);
    await http.runWithClient(() async {
      await tester.tap(find.text('Finca'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Proveedores'));
      await tester.pumpAndSettle();
    }, () => MockClient((req) async => responder(req)));
    expect(pedidos.lastWhere((r) => r.url.path.endsWith('/personas/buscar')).url.queryParameters['area'], 'farm');
  });

  testWidgets('all the Compras buttons are the same size', (tester) async {
    await abrir(tester, rol: 'owner');
    await http.runWithClient(() async {
      await tester.tap(find.text('Compras'));
      await tester.pumpAndSettle();
    }, () => MockClient((req) async => responder(req)));
    final tamanos = {
      for (final t in ['Registrar compra', 'Solicitar adelanto', 'Registrar proveedor', 'Registrar gasto'])
        tester.getSize(find.ancestor(of: find.text(t), matching: find.byType(InkWell)).first),
    };
    expect(tamanos, hasLength(1));
  });

  testWidgets('Logística with the practices of Compras and Producción: no data on top, 4 tabs, orders 20 a page, Gastos and the PDF button', (tester) async {
    await abrir(tester, rol: 'staff');
    await tester.scrollUntilVisible(find.text('Logística'), 200, scrollable: find.byType(Scrollable).last);
    expect(find.text('Por despachar'), findsOneWidget); // the Procesos card keeps its indicators
    await http.runWithClient(() async {
      await tester.tap(find.text('Logística'));
      await tester.pumpAndSettle();
    }, () => MockClient((req) async => responder(req)));
    // No data on top: the card's numbers are not repeated here.
    expect(find.text('2 pedidos'), findsNothing);
    for (final t in ['Registrar gasto', 'Por despachar', 'Entregados', 'Proveedores', 'Gastos']) {
      expect(find.text(t), findsWidgets, reason: t);
    }
    expect(find.byIcon(Icons.picture_as_pdf_outlined), findsOneWidget);
    // Por despachar: the oldest first, asked with orden=antiguos.
    final abiertos = pedidos.lastWhere((r) => r.url.path.contains('/api/pedidos/') && r.url.queryParameters['vista'] == 'PENDIENTES');
    expect(abiertos.url.queryParameters['orden'], 'antiguos');
    expect(abiertos.url.queryParameters['limite'], '20');
    expect(tester.getTopLeft(find.text('Cafe Uno')).dy, lessThan(tester.getTopLeft(find.text('Cafe Dos')).dy));
    expect(find.text('En camino'), findsOneWidget);
    expect(find.text('Pedido ORD-101'), findsOneWidget);
    // Entregados: 20 a page; the second page only near the end.
    await http.runWithClient(() async {
      await tester.tap(find.text('Entregados').last);
      await tester.pumpAndSettle();
    }, () => MockClient((req) async => responder(req)));
    final historial = () => pedidos.where((r) => r.url.path.contains('/api/pedidos/') && r.url.queryParameters['vista'] == 'HISTORIAL').toList();
    expect(historial().map((r) => r.url.queryParameters['pagina']), ['1']);
    expect(find.text('Cancelado'), findsOneWidget);
    await http.runWithClient(() async {
      await tester.scrollUntilVisible(find.text('Cliente 21'), 300, scrollable: find.byType(Scrollable).last);
      await tester.pumpAndSettle();
    }, () => MockClient((req) async => responder(req)));
    expect(historial().map((r) => r.url.queryParameters['pagina']), ['1', '2']);
    expect(find.textContaining('en total'), findsNothing); // no text at the end of a list
    // Gastos: the Logística gastos.
    await http.runWithClient(() async {
      await tester.drag(find.byType(Scrollable).last, const Offset(0, 5000)); // back to the top, where the tabs are
      await tester.pumpAndSettle();
      await tester.tap(find.text('Gastos').last);
      await tester.pumpAndSettle();
    }, () => MockClient((req) async => responder(req)));
    expect(pedidos.any((r) => r.url.path.endsWith('/gastos-area') && r.url.queryParameters['area'] == 'fulfillment'), isTrue);
    // Registrar gasto keeps the Logística area.
    await http.runWithClient(() async {
      await tester.tap(find.text('Registrar gasto'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'Monto (S/)'), '35');
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
    }, () => MockClient((req) async => responder(req)));
    final req = pedidos.lastWhere((r) => r.url.path.endsWith('/registrar/gasto'));
    expect(jsonDecode(req.body)['area'], 'fulfillment');
    expect(tester.takeException(), isNull);
  });

  testWidgets('Logística: an order opens its full detail, the same as in Pedidos', (tester) async {
    // The order detail is Apartalo's own screen; with this short test order its layout may overflow, which is not what
    // this test checks: only that the order opens it.
    final antes = FlutterError.onError;
    FlutterError.onError = (d) {
      if (!d.toString().contains('overflowed')) antes?.call(d);
    };
    addTearDown(() => FlutterError.onError = antes);
    await abrir(tester, rol: 'owner');
    await tester.scrollUntilVisible(find.text('Logística'), 200, scrollable: find.byType(Scrollable).last);
    await http.runWithClient(() async {
      await tester.tap(find.text('Logística'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cafe Uno'));
      await tester.pumpAndSettle();
    }, () => MockClient((req) async => responder(req)));
    expect(find.byType(DetallePedidoSheet), findsOneWidget);
  });

  testWidgets('Registrar compra links a product: the Blend ticked by default, coffee first, and it is sent', (tester) async {
    await abrir(tester, rol: 'staff');
    await http.runWithClient(() async {
      await tester.tap(find.text('Compras'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Registrar compra'));
      await tester.pumpAndSettle();
      expect(find.text('Producto vinculado (opcional)'), findsOneWidget);
      final blend = tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Blend de Caturra, Pache, typica'));
      expect(blend.selected, isTrue);
      expect(tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Geisha')).selected, isFalse);
      // coffee products first, the pack after them
      expect(tester.getTopLeft(find.text('Geisha')).dy, lessThanOrEqualTo(tester.getTopLeft(find.text('Pack x3: Blend, Obata y Geisha')).dy));
      await tester.tap(find.text('Agricultor'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pedro Ramírez Ñique'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'Kilos'), '40');
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();
    }, () => MockClient((req) async => responder(req)));
    final req = pedidos.lastWhere((r) => r.url.path.endsWith('/registrar/entrega'));
    expect(jsonDecode(req.body)['productoId'], 'prod-blend');
  });

  testWidgets('Compras: no summary on top, the Compras tab lists purchases that open their detail', (tester) async {
    await abrir(tester, rol: 'owner');
    await http.runWithClient(() async {
      await tester.tap(find.text('Compras'));
      await tester.pumpAndSettle();
      expect(find.text('Adelantos abiertos'), findsNothing); // no summary on top any more
      expect(find.text('Últimos recibidos'), findsNothing);
      expect(find.text('Recibidos'), findsNothing);
      expect(find.text('Adelantos'), findsOneWidget);
      expect(find.text('Sin precio'), findsOneWidget); // its state, on a row with an arrow
      expect(find.byIcon(Icons.chevron_right), findsWidgets);
      await tester.tap(find.text('Pedro Ramírez Ñique'));
      await tester.pumpAndSettle();
      for (final t in ['Compra', 'Blend de Caturra, Pache, typica', 'L-0001 · calidad por revisar', '12.5 %', 'Revisión de calidad', 'Poner precio']) {
        expect(find.text(t), findsWidgets, reason: t);
      }
    }, () => MockClient((req) async => responder(req)));
    expect(pedidos.any((r) => r.url.path.endsWith('/compras/DL-0001')), isTrue);
  });

  testWidgets('the Compras list loads the next page near the end', (tester) async {
    await abrir(tester, rol: 'staff');
    await http.runWithClient(() async {
      await tester.tap(find.text('Compras'));
      await tester.pumpAndSettle();
      final antes = pedidos.where((r) => r.url.path.endsWith('/compras')).length;
      await tester.drag(find.text('Pedro Ramírez Ñique'), const Offset(0, -4000));
      await tester.pumpAndSettle();
      expect(pedidos.where((r) => r.url.path.endsWith('/compras')).length, greaterThan(antes));
    }, () => MockClient((req) async => responder(req)));
  });

  testWidgets('owners see the payment mark on each compra too; the price goes in the line below', (tester) async {
    await abrir(tester, rol: 'owner');
    await http.runWithClient(() async {
      await tester.tap(find.text('Compras'));
      await tester.pumpAndSettle();
    }, () => MockClient((req) async => responder(req)));
    expect(find.text('Pagado en parte'), findsOneWidget);
    expect(find.textContaining('falta S/ 500'), findsOneWidget);
    expect(find.text('Pagado'), findsWidgets); // a priced compra shows its mark, not its price
    expect(find.text('S/ 5/kg'), findsNothing);
    expect(find.textContaining('S/ 5/kg'), findsWidgets);
  });

  testWidgets('a compra shows one of the five states, and the discount label', (tester) async {
    await abrir(tester, rol: 'staff');
    await http.runWithClient(() async {
      await tester.tap(find.text('Compras'));
      await tester.pumpAndSettle();
    }, () => MockClient((req) async => responder(req)));
    for (final t in ['Sin precio', 'Pagado en parte', 'Rechazado']) {
      expect(find.text(t), findsWidgets, reason: t);
    }
    expect(find.textContaining('Con descuento'), findsOneWidget);
  });

  testWidgets('a compra with a price says the payment was requested; staff never see Finanzas', (tester) async {
    await abrir(tester, rol: 'staff');
    expect(find.text('Finanzas'), findsNothing); // money is only for owners
    await http.runWithClient(() async {
      await tester.tap(find.text('Compras'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Agricultor Parte'));
      await tester.pumpAndSettle();
    }, () => MockClient((req) async => responder(req)));
    expect(find.text('Pagar compra'), findsNothing);
  });

  testWidgets('Solicitar pago completo asks all that is owed by transfer; staff cannot mark it paid from advances', (tester) async {
    await abrir(tester, rol: 'staff');
    await http.runWithClient(() async {
      await tester.tap(find.text('Compras'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Agricultor Parte'));
      await tester.pumpAndSettle();
      expect(find.text('Marcar como pagado desde adelantos'), findsNothing); // owners only
      await tester.tap(find.text('Solicitar pago completo'));
      await tester.pumpAndSettle();
      expect(find.textContaining('S/ 500 por transferencia'), findsOneWidget);
      await tester.tap(find.text('Solicitar'));
      await tester.pumpAndSettle();
    }, () => MockClient((req) async => responder(req)));
    final r = pedidos.lastWhere((r) => r.url.path.endsWith('/registrar/solicitarPago'));
    final body = jsonDecode(r.body) as Map;
    expect(body['compraId'], 'PU-0002');
    expect(body['metodo'], 'transfer');
    expect(body.containsKey('monto'), isFalse); // empty = all that is owed
  });

  testWidgets('an owner marks a compra as paid from advances only when they choose it', (tester) async {
    await abrir(tester, rol: 'owner');
    await http.runWithClient(() async {
      await tester.tap(find.text('Compras'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Agricultor Parte'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Marcar como pagado desde adelantos'));
      await tester.pumpAndSettle();
      expect(find.textContaining('ADV-007 (queda S/ 200)'), findsOneWidget);
      await tester.tap(find.text('Marcar como pagado'));
      await tester.pumpAndSettle();
    }, () => MockClient((req) async => responder(req)));
    final r = pedidos.lastWhere((r) => r.url.path.endsWith('/registrar/pagoDesdeAdelantos'));
    expect((jsonDecode(r.body) as Map)['compraId'], 'PU-0002');
  });

  testWidgets('Finanzas keeps the last month with Pendiente, Urgente or Pagado, and a paid row has no Pagar', (tester) async {
    await abrir(tester, rol: 'owner');
    await entrarFinanzas(tester);
    for (final t in ['Pendiente', 'Urgente', 'Pagado']) {
      expect(find.text(t), findsWidgets, reason: t);
    }
    expect(find.textContaining('espera 9 días'), findsOneWidget);
    expect(pedidos.any((r) => r.url.path.endsWith('/finanzas/lista') && r.url.queryParameters['tipo'] == 'compras'), isTrue);
    expect(pedidos.any((r) => r.url.queryParameters['tipo'] == 'gastos'), isFalse); // a tab loads only when opened
    await http.runWithClient(() async {
      await tester.tap(find.text('Agricultor Pagado'));
      await tester.pumpAndSettle();
    }, () => MockClient((req) async => responder(req)));
    // Tocar la fila abre su detalle; debajo, sólo evidencia (ya está pagada).
    expect(find.text('Ver la compra completa'), findsOneWidget);
    expect(find.text('Subir evidencia'), findsOneWidget);
    expect(find.text('Pagar compra'), findsNothing);
  });

  testWidgets('a waiting compra opens its detail with Pagar compra, Subir evidencia and Ver evidencia under it', (tester) async {
    await abrir(tester, rol: 'owner');
    await entrarFinanzas(tester);
    await http.runWithClient(() async {
      await tester.tap(find.text('Pedro Ramírez Ñique'));
      await tester.pumpAndSettle();
    }, () => MockClient((req) async => responder(req)));
    for (final t in ['Pidieron pagar', 'S/ 300', 'Transferencia', 'Pagar compra', 'Subir evidencia', 'Ver evidencia (1)']) {
      expect(find.text(t), findsWidgets, reason: t);
    }
    expect(find.text('Ver detalle'), findsNothing); // no menu: the detail opens at once
  });

  testWidgets('a paid gasto opens its detail with when and how it was paid', (tester) async {
    await abrir(tester, rol: 'owner');
    await entrarFinanzas(tester);
    await http.runWithClient(() async {
      await tester.tap(find.text('Gastos').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mano de obra'));
      await tester.pumpAndSettle();
    }, () => MockClient((req) async => responder(req)));
    for (final t in ['Pagado el', 'Transferencia', 'owner@x', 'Subir evidencia', 'S/ 80']) {
      expect(find.textContaining(t), findsWidgets, reason: t);
    }
  });

  testWidgets('Finanzas confirms a payment with an advance with one tap', (tester) async {
    await abrir(tester, rol: 'owner');
    await entrarFinanzas(tester);
    await http.runWithClient(() async {
      expect(find.textContaining('con el adelanto ADV-007'), findsOneWidget);
      await tester.tap(find.text('Agricultor Parte'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pagar con el adelanto'));
      await tester.pumpAndSettle();
      expect(find.text('¿Pagar con el adelanto?'), findsOneWidget);
      await tester.tap(find.text('Confirmar'));
      await tester.pumpAndSettle();
    }, () => MockClient((req) async => responder(req)));
    final r = pedidos.lastWhere((r) => r.url.path.contains('/registrar/'));
    expect(r.url.path, endsWith('/registrar/pagoConAdelanto'));
    expect(jsonDecode(r.body)['solicitudId'], 9);
  });

  testWidgets('Compras shows Adelantos (instead of En almacén): requests waiting and each advance with what is left', (tester) async {
    await abrir(tester, rol: 'staff');
    await http.runWithClient(() async {
      await tester.tap(find.text('Compras'));
      await tester.pumpAndSettle();
      expect(find.text('En almacén'), findsNothing);
      await tester.tap(find.text('Adelantos'));
      await tester.pumpAndSettle();
    }, () => MockClient((req) async => responder(req)));
    for (final t in ['Esperan a Finanzas', 'Misael Cusi', 'queda S/ 200', 'Liquidado']) {
      expect(find.text(t), findsWidgets, reason: t);
    }
    expect(find.textContaining('ADV-007 · S/ 500 · usado en café S/ 300'), findsOneWidget);
  });

  testWidgets('Compras has a Gastos tab after Proveedores: the Compras gastos with their status', (tester) async {
    await abrir(tester, rol: 'staff');
    await http.runWithClient(() async {
      await tester.tap(find.text('Compras'));
      await tester.pumpAndSettle();
      final tabs = ['Compras', 'Adelantos', 'Proveedores', 'Gastos'].map((t) => tester.getCenter(find.text(t).last).dx).toList();
      for (var i = 1; i < tabs.length; i++) {
        expect(tabs[i], greaterThan(tabs[i - 1]));
      }
      await tester.tap(find.text('Gastos').last);
      await tester.pumpAndSettle();
    }, () => MockClient((req) async => responder(req)));
    expect(pedidos.any((r) => r.url.path.endsWith('/gastos-area') && r.url.queryParameters['area'] == 'sourcing'), isTrue);
    for (final t in ['Transporte', 'Pendiente']) {
      expect(find.text(t), findsWidgets, reason: t);
    }
    expect(find.textContaining('30 · Lobato'), findsOneWidget);
    expect(find.text('Flete'), findsNothing); // only the Compras area
    expect(tester.takeException(), isNull);
  });

  testWidgets('Compras PDF button opens Generar reporte: Mensual with Desde and Hasta, or Anual; the server is asked only then', (tester) async {
    await abrir(tester, rol: 'owner');
    final hoy = DateTime.now();
    await http.runWithClient(() async {
      await tester.tap(find.text('Compras'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.picture_as_pdf_outlined));
      await tester.pumpAndSettle();
    }, () => MockClient((req) async => responder(req)));
    // A short form, not a list of every month.
    for (final t in ['Generar reporte', 'Mensual', 'Anual', 'FECHA DE INICIO', 'FECHA DE FIN', 'PERÍODO DEL REPORTE', '1 mes seleccionado', 'Generar PDF']) {
      expect(find.text(t), findsWidgets, reason: t);
    }
    expect(find.text('${ComprasPdfService.nombreMes(hoy.month)} ${hoy.year}'), findsNWidgets(3)); // this month by default
    expect(pedidos.any((r) => r.url.path.endsWith('/compras/reporte')), isFalse);
    // The period is information, not a button: nothing to tap on it.
    expect(find.ancestor(of: find.text('PERÍODO DEL REPORTE'), matching: find.byType(InkWell)), findsNothing);
    // The start date opens its months right here; a future month cannot be chosen.
    await tester.tap(find.text('FECHA DE INICIO'));
    await tester.pumpAndSettle();
    if (hoy.month < 12) {
      final futuro = tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, ComprasPdfService.mesCorto(hoy.month + 1)).first);
      expect(futuro.onSelected, isNull);
    }
    // Anual: the year with arrows; the next year is not offered.
    await tester.tap(find.text('Anual'));
    await tester.pumpAndSettle();
    expect(find.text('Año ${hoy.year}'), findsOneWidget);
    expect(tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.chevron_right)).onPressed, isNull);
    await tester.tap(find.byIcon(Icons.chevron_left));
    await tester.pumpAndSettle();
    await http.runWithClient(() async {
      await tester.tap(find.text('Generar PDF'));
      await tester.pumpAndSettle();
    }, () => MockClient((req) async => responder(req)));
    final r = pedidos.lastWhere((r) => r.url.path.endsWith('/compras/reporte'));
    expect(r.url.queryParameters, {'desde': '${hoy.year - 1}-01', 'hasta': '${hoy.year - 1}-12'});
    expect(find.byType(SnackBar), findsOneWidget); // the error is said, nothing is left half done
  });

  testWidgets('Generar reporte: Hasta follows Desde, and more than 12 months is refused next to the button', (tester) async {
    await abrir(tester, rol: 'owner');
    final hoy = DateTime.now();
    await http.runWithClient(() async {
      await tester.tap(find.text('Compras'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.picture_as_pdf_outlined));
      await tester.pumpAndSettle();
    }, () => MockClient((req) async => responder(req)));
    // Inicio: January of last year. Fin moves only if it was before; here Fin stays this month: more than 12 months.
    await tester.tap(find.text('FECHA DE INICIO'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.chevron_left).first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Ene').first);
    await tester.pumpAndSettle();
    expect(find.text('Un reporte cubre como máximo 12 meses.'), findsOneWidget);
    expect(tester.widget<ButtonStyleButton>(find.ancestor(of: find.text('Generar PDF'), matching: find.byWidgetPredicate((w) => w is ButtonStyleButton))).onPressed, isNull);
    expect(find.text('Ene ${hoy.year - 1} – ${ComprasPdfService.mesCorto(hoy.month)} ${hoy.year}'), findsOneWidget);
    // The X closes without asking anything.
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    expect(find.text('Generar reporte'), findsNothing);
    expect(pedidos.any((r) => r.url.path.endsWith('/compras/reporte')), isFalse);
  });

  testWidgets('lists end without a text: no "en total" and no "Se ven los…" at the bottom', (tester) async {
    await abrir(tester, rol: 'owner');
    await http.runWithClient(() async {
      await tester.tap(find.text('Compras'));
      await tester.pumpAndSettle();
      await tester.drag(find.text('Pedro Ramírez Ñique'), const Offset(0, -6000));
      await tester.pumpAndSettle();
    }, () => MockClient((req) async => responder(req)));
    expect(find.textContaining('en total'), findsNothing);
    expect(find.textContaining('Se ven los'), findsNothing);
  });

  testWidgets('the label of a row sits at the right edge, next to the arrow', (tester) async {
    await abrir(tester, rol: 'owner');
    await http.runWithClient(() async {
      await tester.tap(find.text('Compras'));
      await tester.pumpAndSettle();
    }, () => MockClient((req) async => responder(req)));
    final flecha = tester.getTopLeft(find.byIcon(Icons.chevron_right).first).dx;
    final etiqueta = tester.getTopRight(find.text('Sin precio').first).dx;
    expect(flecha - etiqueta, lessThan(20)); // label right before the arrow
  });

  testWidgets('a provider opens its detail; staff never see DNI, phone, accounts or money', (tester) async {
    await abrir(tester, rol: 'staff');
    await http.runWithClient(() async {
      await tester.tap(find.text('Compras'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Proveedores'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pedro Ramírez Ñique'));
      await tester.pumpAndSettle();
    }, () => MockClient((req) async => responder(req)));
    for (final t in ['Proveedor', 'Pergamino', 'Sector Ejemplo', 'Lo que le compramos', '130 kg', 'Últimas compras']) {
      expect(find.text(t), findsWidgets, reason: t);
    }
    for (final t in ['DNI o RUC', 'Teléfono', 'Cuentas para pagarle', 'Le debemos', 'Editar datos', 'Agregar cuenta', 'Adelantos']) {
      expect(find.text(t), findsNothing, reason: t);
    }
    expect(find.text('Generar reporte'), findsOneWidget); // everyone can make the report (without money for staff)
    // Opening the detail never asks for the report: it is read only when Generar reporte is tapped.
    expect(pedidos.where((r) => r.url.path.endsWith('/reporte')), isEmpty);
  });

  testWidgets('a process screen asks the server only for its own summary', (tester) async {
    await abrir(tester, rol: 'owner');
    pedidos.clear();
    await http.runWithClient(() async {
      await tester.tap(find.text('Compras'));
      await tester.pumpAndSettle();
    }, () => MockClient((req) async => responder(req)));
    final procesos = pedidos.where((r) => r.url.path.endsWith('/procesos')).toList();
    expect(procesos, isNotEmpty);
    expect(procesos.last.url.queryParameters['solo'], 'compras');
  });

  testWidgets('owners edit a provider and its accounts, and see its advances', (tester) async {
    await abrir(tester, rol: 'owner');
    await http.runWithClient(() async {
      await tester.tap(find.text('Compras'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Proveedores'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pedro Ramírez Ñique'));
      await tester.pumpAndSettle();
    }, () => MockClient((req) async => responder(req)));
    for (final t in ['Generar reporte', 'Editar datos', 'Agregar cuenta']) {
      expect(find.text(t), findsWidgets, reason: t);
    }
    await tester.scrollUntilVisible(find.text('S/ 500 · ADV-007'), 200, scrollable: find.byType(Scrollable).last);
    expect(find.text('Saldo S/ 200'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Editar datos'), -200, scrollable: find.byType(Scrollable).last);
    await http.runWithClient(() async {
      await tester.tap(find.text('Editar datos'));
      await tester.pumpAndSettle();
    }, () => MockClient((req) async => responder(req)));
    expect(find.text('Editar proveedor'), findsWidgets);
    expect(find.descendant(of: find.byType(TextFormField), matching: find.text('Pedro Ramírez Ñique')), findsOneWidget); // filled with today's data
    await tester.tap(find.byIcon(Icons.close).last);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('000-0000000-0-00'), 200, scrollable: find.byType(Scrollable).last);
    await tester.tap(find.text('000-0000000-0-00'));
    await tester.pumpAndSettle();
    expect(find.text('Editar cuenta'), findsOneWidget);
    expect(find.text('Quitar cuenta'), findsOneWidget);
  });

  testWidgets('owners see the provider\'s DNI, phone, accounts and what we owe', (tester) async {
    await abrir(tester, rol: 'owner');
    await http.runWithClient(() async {
      await tester.tap(find.text('Compras'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Proveedores'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pedro Ramírez Ñique'));
      await tester.pumpAndSettle();
    }, () => MockClient((req) async => responder(req)));
    for (final t in ['DNI o RUC', 'Teléfono', 'Cuentas para pagarle', '000-0000000-0-00', 'Cuenta · BCP · Pedro Ramírez Ñique', 'Le debemos', 'S/ 300']) {
      expect(find.text(t), findsWidgets, reason: t);
    }
  });

  testWidgets('Finanzas shows how much evidence a row has and opens it', (tester) async {
    await abrir(tester, rol: 'owner');
    await entrarFinanzas(tester);
    expect(find.textContaining('1 evidencia'), findsOneWidget);
    await http.runWithClient(() async {
      await tester.tap(find.text('Pedro Ramírez Ñique'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ver evidencia (1)'));
      await tester.pumpAndSettle();
    }, () => MockClient((req) async => responder(req)));
    expect(find.text('Evidencia'), findsWidgets);
    expect(find.text('Subir evidencia'), findsOneWidget);
    expect(find.text('3 nov'), findsOneWidget); // one photo, with its date
    final r = pedidos.lastWhere((r) => r.url.path.endsWith('/evidencias'));
    expect(r.url.queryParameters, {'tipo': 'purchase', 'id': 'PU-0001'});
  });

  testWidgets('gastos and advance requests also offer Subir evidencia', (tester) async {
    await abrir(tester, rol: 'owner');
    await entrarFinanzas(tester);
    await http.runWithClient(() async {
      await tester.tap(find.text('Gastos').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Gas'));
      await tester.pumpAndSettle();
    }, () => MockClient((req) async => responder(req)));
    expect(find.text('Pagar gasto'), findsOneWidget);
    expect(find.text('Subir evidencia'), findsOneWidget);
    expect(find.textContaining('Ver evidencia'), findsNothing); // none yet
    await tester.tapAt(const Offset(10, 10)); // close the menu
    await tester.pumpAndSettle();
    await http.runWithClient(() async {
      await tester.tap(find.text('Adelantos').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Misael Cusi'));
      await tester.pumpAndSettle();
    }, () => MockClient((req) async => responder(req)));
    for (final t in ['Aprobar y entregar', 'Rechazar', 'Subir evidencia']) {
      expect(find.text(t), findsOneWidget, reason: t);
    }
  });

  testWidgets('the photo goes to the server with what it belongs to', (tester) async {
    await abrir(tester, rol: 'owner');
    late dynamic r;
    await http.runWithClient(() async {
      r = await AdministracionService.subirEvidencia(tipo: 'expense', id: 'EX-0001', bytes: [0xff, 0xd8, 0xff, 0xe0]);
    }, () => MockClient((req) async => responder(req)));
    expect(r.isSuccess, isTrue);
    final body = jsonDecode(pedidos.last.body) as Map;
    expect(body['tipo'], 'expense');
    expect(body['id'], 'EX-0001');
    expect(base64Decode(body['archivoBase64'] as String), [0xff, 0xd8, 0xff, 0xe0]);
  });
}
