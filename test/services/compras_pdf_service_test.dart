import 'dart:io';

import 'package:apartalo_app/services/proveedor_pdf_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;

void main() {
  // Fake test data only (never real farmers).
  Map<String, dynamic> reporte({required bool dueno, required bool anual, int compras = 3}) => {
        'desde': anual ? '2026-01-01' : '2026-11-01',
        'hasta': anual ? '2026-12-31' : '2026-11-30',
        'cierre': '2026-11-04',
        'meses': anual ? 12 : 1,
        'anual': anual,
        'generado': '2026-11-04T15:00:00Z',
        'dueno': dueno,
        'franja': {'kg': 120, 'compras': compras, 'agricultores': 2, 'sin_precio': 1, 'mayor_parte': 66.7, if (dueno) ...{'debe': 300, 'comprado': 2400, 'pagado': 500}},
        'compras': anual
            ? []
            : [
                for (var i = 0; i < compras; i++)
                  {
                    'fecha': '2026-11-03', 'agricultor': 'Agricultor Ejemplo', 'estado': 'parchment', 'kg': 40, 'situacion': 'Por pagar',
                    if (dueno) ...{'precio': 20, 'total': 800, 'pagado': 500, 'de_adelantos': 0, 'debe': 300},
                  },
              ],
        'por_mes': anual
            ? [
                {'mes': '2026-03', 'compras': 2, 'kg': 80, 'agricultores': 2, if (dueno) ...{'total': 1600, 'precio_medio': 20, 'debe': 0}},
                {'mes': '2026-11', 'compras': 1, 'kg': 40, 'agricultores': 1, if (dueno) ...{'total': 800, 'precio_medio': 20, 'debe': 300}},
              ]
            : [],
        'por_agricultor': [
          {'agricultor': 'Agricultor Ejemplo', 'comunidad': 'Sector Ejemplo', 'compras': 2, 'kg': 80, 'parte': 66.7, if (anual) 'meses': 2,
           if (dueno) ...{'total': 1600, 'precio_medio': 20}},
          {'agricultor': 'Agricultor Dos', 'compras': 1, 'kg': 40, 'parte': 33.3, if (anual) 'meses': 1, if (dueno) ...{'total': 800, 'precio_medio': 20}},
        ],
        'por_estado': [
          {'estado': 'parchment', 'compras': 3, 'kg': 120, if (dueno) 'total': 2400},
        ],
        'esperan': {'sin_precio': 1, 'sin_precio_kg': 10, 'por_pagar': 1, if (dueno) 'por_pagar_monto': 300},
        if (dueno) 'pagos': [
          {'fecha': '2026-11-03', 'agricultor': 'Agricultor Ejemplo', 'tipo': 'Transferencia', 'monto': 500, 'compra': 'PU-0001'}
        ],
        if (dueno) 'adelantos': [
          {'id': 'ADV-001', 'fecha': '2026-11-01', 'agricultor': 'Agricultor Ejemplo', 'monto': 500, 'usado': 300, 'devuelto': 0, 'saldo': 200}
        ],
        if (dueno) 'solicitudes': {'aprobadas': 1, 'rechazadas': 0},
        if (dueno) 'adelantos_totales': {'dados': 500, 'abiertos_al_cierre': 200},
        'gastos': [
          {'fecha': '2026-11-02', 'categoria': 'Transporte', 'descripcion': 'Flete', 'estado': 'Pendiente', if (dueno) 'monto': 30}
        ],
      };

  test('builds the monthly and annual reports, for owners and for staff', () async {
    for (final anual in [false, true]) {
      for (final dueno in [true, false]) {
        final bytes = await ComprasPdfService.generarBytes(reporte(dueno: dueno, anual: anual),
            businessName: 'Negocio Ejemplo', base: pw.Font.helvetica(), bold: pw.Font.helveticaBold());
        expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
        final salida = Platform.environment['COMPRAS_PDF_DIR'];
        if (salida != null) File('$salida/compras_${anual ? 'anual' : 'mensual'}_${dueno ? 'dueno' : 'staff'}.pdf').writeAsBytesSync(bytes);
      }
    }
  });

  test('a month with no compras and a long month still build', () async {
    final vacio = reporte(dueno: true, anual: false, compras: 0)..['compras'] = [];
    for (final r in [vacio, reporte(dueno: true, anual: false, compras: 400)]) {
      final bytes = await ComprasPdfService.generarBytes(r, businessName: 'Negocio Ejemplo', base: pw.Font.helvetica(), bold: pw.Font.helveticaBold());
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    }
  });

  test('the period reads as one month, a year or a range', () {
    expect(ComprasPdfService.periodo(DateTime(2026, 11), DateTime(2026, 11)), 'Noviembre 2026');
    expect(ComprasPdfService.periodo(DateTime(2026, 1), DateTime(2026, 12)), 'Año 2026');
    expect(ComprasPdfService.periodo(DateTime(2026, 5), DateTime(2026, 9)), 'May 2026 – Sep 2026');
  });

  test('builds the Producción report for one month and for a range, for owners and for staff', () async {
    Map<String, dynamic> r({required bool dueno, required bool rango}) => {
          'desde': rango ? '2026-05-01' : '2026-11-01',
          'hasta': rango ? '2026-09-30' : '2026-11-30',
          'meses': rango ? 5 : 1,
          'generado': '2026-11-04T15:00:00Z',
          'dueno': dueno,
          'franja': {'tuestes': 2, 'kg_verde': 60, 'kg_tostado': 49.8, 'merma_pct': 17.0, 'kg_verde_vendido': 72, 'kg_tostado_vendido': 90},
          'en_curso': {'programados': 1, 'tostando': 0},
          'tuestes': rango
              ? []
              : [
                  {'fecha': '2026-11-03', 'producto': 'Omagua 250 g', 'lote': 'GV-1', 'kg_verde': 20, 'kg_tostado': 16.6, 'merma_pct': 17.0, 'estado': 'Terminado'},
                  {'fecha': '2026-11-05', 'producto': 'Omagua 1 kg', 'lote': 'GV-1', 'kg_verde': 10, 'estado': 'Programado'},
                ],
          'por_mes': rango
              ? [
                  {'mes': '2026-05', 'tuestes': 1, 'kg_verde': 20, 'kg_tostado': 16.6, 'merma_pct': 17.0},
                  {'mes': '2026-07', 'tuestes': 1, 'kg_verde': 40, 'kg_tostado': 33.2, 'merma_pct': 17.0},
                ]
              : [],
          'por_lote': [
            {'lote': 'GV-1', 'variedad': 'Catimor', 'cosecha': 2026, 'tuestes': 2, 'kg_verde': 60, 'kg_tostado': 49.8, 'merma_pct': 17.0}
          ],
          'verde_hoy': [
            {'lote': 'GV-1', 'variedad': 'Catimor', 'cosecha': 2026, 'kg_inicial': 100, 'kg_ahora': 40}
          ],
          'tostado_hoy': [
            {'fecha': '2026-07-02', 'producto': 'Omagua 250 g', 'lote': 'TT-1', 'kg': 12}
          ],
          // Validated again with Production (4 Nov 2026): no por_procesar; green movements by lot, roasted sold, oversold lots.
          'movimientos_verde': [
            {'lote': 'L-1', 'estado': 'Cerrado', 'cerrado': 760},
            {'lote': 'L-5', 'estado': 'Abierto', 'tostado': 65, 'diferencia': -108, 'saldo': 47},
            {'lote': 'L-7', 'estado': 'Abierto', 'compras': 2, 'pergamino': 88.7, 'estimado': 70.96, 'tostado': 100, 'vendido': 72, 'saldo': 484.96},
          ],
          'vendido_tostado': [
            {'producto': 'Blend de Caturra, Pache, typica', 'kg': 50},
            {'producto': 'Geisha', 'kg': 30},
          ],
          'vendido_de_mas': [
            {'producto': 'Blend de Caturra, Pache, typica', 'lote': 'L-8', 'fecha': '2026-10-17', 'asignado': 120, 'vendido': 126, 'saldo': -6},
          ],
          if (dueno) 'costos': [
            {'categoria': 'Mantenimiento', 'pendiente': 90, 'pagado': 0, 'total': 90}
          ],
          if (dueno && rango) 'costos_por_mes': [
            {'mes': '2026-07', 'pendiente': 90, 'pagado': 0, 'total': 90}
          ],
        };
    for (final rango in [false, true]) {
      for (final dueno in [true, false]) {
        final bytes = await ProduccionPdfService.generarBytes(r(dueno: dueno, rango: rango),
            businessName: 'Negocio Ejemplo', base: pw.Font.helvetica(), bold: pw.Font.helveticaBold());
        expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
        final salida = Platform.environment['COMPRAS_PDF_DIR'];
        if (salida != null) File('$salida/produccion_${rango ? 'rango' : 'mes'}_${dueno ? 'dueno' : 'staff'}.pdf').writeAsBytesSync(bytes);
      }
    }
  });

  test('builds the Logística report for one month and for a range, for owners and for staff (4 Nov 2026)', () async {
    Map<String, dynamic> r({required bool dueno, required bool rango}) => {
          'desde': rango ? '2026-01-01' : '2026-10-01',
          'hasta': rango ? '2026-10-31' : '2026-10-31',
          'meses': rango ? 10 : 1,
          'generado': '2026-11-04T15:00:00Z',
          'dueno': dueno,
          'franja': {'creados': 311, 'entregados': 292, 'cancelados': 19, 'abiertos_hoy': 0},
          'por_mes': rango
              ? [
                  {'mes': '2026-01', 'creados': 20, 'entregados': 19, 'cancelados': 1},
                  {'mes': '2026-02', 'creados': 31, 'entregados': 30, 'cancelados': 1},
                ]
              : [],
          'canales': [
            {'canal': 'manual', 'pedidos': 286},
            {'canal': 'web', 'pedidos': 6},
          ],
          'tiempo': {'entregados_con_fecha': 185, 'con_envio': 200, 'dias_a_envio': 1.8, 'dias_a_entrega': 1.9},
          'envio': {'pedidos': 7, if (dueno) 'monto': 82},
          if (dueno) 'costos': [],
        };
    for (final rango in [false, true]) {
      for (final dueno in [true, false]) {
        final bytes = await LogisticaPdfService.generarBytes(r(dueno: dueno, rango: rango),
            businessName: 'Negocio Ejemplo', base: pw.Font.helvetica(), bold: pw.Font.helveticaBold());
        expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
        final salida = Platform.environment['COMPRAS_PDF_DIR'];
        if (salida != null) File('$salida/logistica_${rango ? 'rango' : 'mes'}_${dueno ? 'dueno' : 'staff'}.pdf').writeAsBytesSync(bytes);
      }
    }
  });

  test('builds the Finca and Finanzas reports (4 Nov 2026)', () async {
    final salida = Platform.environment['COMPRAS_PDF_DIR'];
    for (final dueno in [true, false]) {
      final finca = await FincaPdfService.generarBytes({
        'desde': '2026-11-01', 'hasta': '2026-11-30', 'meses': 1, 'generado': '2026-11-04T15:00:00Z', 'dueno': dueno,
        'franja': {'gastos': 2, 'pendientes': 1, if (dueno) 'total': 420, if (dueno) 'por_pagar': 120},
        'por_categoria': [
          {'categoria': 'Insumos', 'gastos': 1, if (dueno) 'pendiente': 0, if (dueno) 'pagado': 300, if (dueno) 'total': 300},
          {'categoria': 'Mano de obra', 'gastos': 1, if (dueno) 'pendiente': 120, if (dueno) 'pagado': 0, if (dueno) 'total': 120},
        ],
        'gastos': [
          {'fecha': '2026-11-02', 'categoria': 'Mano de obra', 'descripcion': 'Jornal deshierbo', 'estado': 'Pendiente', if (dueno) 'monto': 120},
          {'fecha': '2026-11-03', 'categoria': 'Insumos', 'descripcion': 'Abono', 'estado': 'Pagado', if (dueno) 'monto': 300},
        ],
      }, businessName: 'Negocio Ejemplo', base: pw.Font.helvetica(), bold: pw.Font.helveticaBold());
      expect(String.fromCharCodes(finca.take(5)), '%PDF-');
      if (salida != null) File('$salida/finca_${dueno ? 'dueno' : 'staff'}.pdf').writeAsBytesSync(finca);
    }
    final finanzas = await FinanzasPdfService.generarBytes({
      'desde': '2026-11-01', 'hasta': '2026-11-30', 'meses': 1, 'generado': '2026-11-04T15:00:00Z', 'dueno': true,
      'franja': {'gastos': 150, 'pagado': 458.95, 'compras_debe': 1584, 'retiros': 0},
      'gastos_por_area': [{'area': 'Comercial', 'categoria': 'Combustible', 'pendiente': 0, 'pagado': 150, 'total': 150}],
      'pagos_por_cuenta': [{'cuenta': 'BCP Corriente Soles', 'pagos': 2, 'total': 458.95}],
      'pagos': [
        {'fecha': '2026-11-04', 'cuenta': 'BCP Corriente Soles', 'tipo': 'Compra', 'quien': 'Jhonatan', 'monto': 308.95},
        {'fecha': '2026-11-04', 'cuenta': 'BCP Corriente Soles', 'tipo': 'Gasto', 'monto': 150},
      ],
      'compras': {'comprado': 1892.95, 'pagado': 308.95, 'debe': 1584, 'compras': 2, 'kg': 88.7},
      'adelantos': {'dados': 0, 'abiertos_al_cierre': 0},
      'retiros': [],
    }, businessName: 'Negocio Ejemplo', base: pw.Font.helvetica(), bold: pw.Font.helveticaBold());
    expect(String.fromCharCodes(finanzas.take(5)), '%PDF-');
    if (salida != null) File('$salida/finanzas_dueno.pdf').writeAsBytesSync(finanzas);
  });

  test('builds the Comercialización report, for owners and for staff (4 Nov 2026)', () async {
    final salida = Platform.environment['COMPRAS_PDF_DIR'];
    for (final dueno in [true, false]) {
      final bytes = await ComercialPdfService.generarBytes({
        'desde': '2026-10-01', 'hasta': '2026-10-31', 'meses': 1, 'generado': '2026-11-04T15:00:00Z', 'dueno': dueno,
        'franja': {'pedidos': 29, 'pedidos_antes': 36, if (dueno) 'vendido': 25901, if (dueno) 'ticket': 893.14, if (dueno) 'vendido_antes': 19196.5, if (dueno) 'vendido_anio': 303861},
        'productos': [
          {'producto': 'Blend de Caturra, Pache, typica', 'presentacion': '1 kg', 'pedidos': 12, 'unidades': 40, if (dueno) 'total': 3200},
          {'producto': 'Geisha', 'presentacion': '250 g', 'pedidos': 5, 'unidades': 9, if (dueno) 'total': 450},
        ],
        'clientes': {'activos': 23, 'nuevos': 3, 'silenciosos': 23},
        'silenciosos': [{'nombre': 'Cafe Viejo', 'ultimo': '2026-07-01', 'pedidos': 4}],
        'canales': [{'canal': 'manual', 'pedidos': 28, if (dueno) 'vendido': 25851}, {'canal': 'web', 'pedidos': 1, if (dueno) 'vendido': 50}],
        if (dueno) 'costos': [{'categoria': 'Combustible', 'pendiente': 0, 'pagado': 150, 'total': 150}],
      }, businessName: 'Negocio Ejemplo', base: pw.Font.helvetica(), bold: pw.Font.helveticaBold());
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
      if (salida != null) File('$salida/comercial_${dueno ? 'dueno' : 'staff'}.pdf').writeAsBytesSync(bytes);
    }
  });

  test('month names are in Spanish', () {
    expect(ComprasPdfService.nombreMes(1), 'Enero');
    expect(ComprasPdfService.nombreMes(11), 'Noviembre');
  });
}
