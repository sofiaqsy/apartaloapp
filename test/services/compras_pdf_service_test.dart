import 'dart:io';

import 'package:apartalo_app/services/proveedor_pdf_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;

void main() {
  // Fake test data only (never real farmers).
  Map<String, dynamic> reporte({required bool dueno, required bool anual, int compras = 3}) => {
        'tipo': anual ? 'anual' : 'mensual',
        'anio': 2026,
        if (!anual) 'mes': 11,
        'generado': '2026-11-04T15:00:00Z',
        'dueno': dueno,
        'franja': {'kg': 120, 'compras': compras, 'agricultores': 2, 'sin_precio': 1, 'mayor_parte': 66.7, if (dueno) 'debe': 300},
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
                {'mes': 3, 'compras': 2, 'kg': 80, 'agricultores': 2, if (dueno) ...{'total': 1600, 'precio_medio': 20, 'debe': 0}},
                {'mes': 11, 'compras': 1, 'kg': 40, 'agricultores': 1, if (dueno) ...{'total': 800, 'precio_medio': 20, 'debe': 300}},
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

  test('month names are in Spanish', () {
    expect(ComprasPdfService.nombreMes(1), 'Enero');
    expect(ComprasPdfService.nombreMes(11), 'Noviembre');
  });
}
