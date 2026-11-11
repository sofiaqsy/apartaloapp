import 'dart:convert';

import 'package:apartalo_app/services/proveedor_pdf_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;

void main() {
  // Fake test data only (never real providers).
  Map<String, dynamic> reporte({required bool dueno, int compras = 3}) => {
        'id': 'P-0001',
        'nombre': 'Agricultor Ejemplo',
        'tipo': 'person',
        'agricultor': true,
        'comprador': false,
        'vende': 'parchment',
        'comunidad': 'Sector Ejemplo',
        'puede_editar': dueno,
        'generado': '2026-11-03T15:00:00Z',
        'documento': dueno ? '00000000' : null,
        'telefono': dueno ? '999000000' : null,
        'cuentas': dueno
            ? [
                {'id': 1, 'tipo': 'bank_account', 'banco': 'BCP', 'numero': '000-0000000-0-00', 'titular': 'Agricultor Ejemplo'}
              ]
            : null,
        'compras': {'n': compras, 'kg': 40 * compras, 'ultima': '2026-11-03'},
        'dinero': dueno ? {'comprado': 800, 'debe': 300} : null,
        'adelantos_lista': dueno
            ? [
                {'id': 'ADV-001', 'fecha': '2026-11-01', 'monto': 500, 'usado': 300, 'devuelto': 0, 'saldo': 200}
              ]
            : null,
        'compras_lista': [
          for (var i = 0; i < compras; i++)
            {
              'id': 'DL-$i',
              'fecha': '2026-11-03',
              'estado': 'parchment',
              'kg': 40,
              'situacion': 'Por pagar',
              'precio': dueno ? 20 : null,
              'total': dueno ? 800 : null
            },
        ],
      };

  test('builds the owner report and the staff report', () async {
    for (final dueno in [true, false]) {
      final bytes = await ProveedorPdfService.generarBytes(reporte(dueno: dueno),
          businessName: 'Negocio Ejemplo', base: pw.Font.helvetica(), bold: pw.Font.helveticaBold());
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    }
  });

  test('with evidence (10 Nov 2026): one page per image after the report, and a page when one could not be downloaded', () async {
    int paginas(List<int> bytes) => RegExp(r'/Type\s*/Page(?!s)').allMatches(latin1.decode(bytes)).length;
    // A 1 x 1 PNG, fake.
    final png = base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8/5+hHgAHggJ/PchI7wAAAABJRU5ErkJggg==');
    Future<List<int>> generar(List<EvidenciaPdf> evidencias) => ProveedorPdfService.generarBytes(reporte(dueno: true),
        businessName: 'Negocio Ejemplo', base: pw.Font.helvetica(), bold: pw.Font.helveticaBold(), evidencias: evidencias);
    final sin = paginas(await generar(const []));
    final con = paginas(await generar([
      EvidenciaPdf(que: 'Adelanto ADV-001 · S/ 500.00', fecha: '2026-11-01', imagenes: [png]),
      EvidenciaPdf(que: 'Compra PU-0001', fecha: '2026-11-03', nota: 'Voucher', imagenes: [png, png]), // a PDF of 2 pages
      const EvidenciaPdf(que: 'Gasto EX-0001'), // could not be downloaded
    ]));
    expect(sin, greaterThan(0));
    expect(con, sin + 4);
  });

  test('the longest history (500 compras) still builds', () async {
    final bytes = await ProveedorPdfService.generarBytes(reporte(dueno: true, compras: 500),
        businessName: 'Negocio Ejemplo', base: pw.Font.helvetica(), bold: pw.Font.helveticaBold());
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
  });

  test('dates and money read like the pedido PDF', () {
    expect(ProveedorPdfService.fecha('2026-11-03'), '03/11/2026');
    expect(ProveedorPdfService.soles(1800), 'S/ 1,800.00');
    expect(ProveedorPdfService.soles(null), '—');
    expect(ProveedorPdfService.kg(40), '40 kg');
  });
}
