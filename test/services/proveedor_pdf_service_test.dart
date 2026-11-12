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

  test('with evidence (10 Nov 2026): one page per record with all its images, more than 9 continue, and a page when none downloaded', () async {
    int paginas(List<int> bytes) => RegExp(r'/Type\s*/Page(?!s)').allMatches(latin1.decode(bytes)).length;
    // A 1 x 1 PNG, fake.
    final png = base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8/5+hHgAHggJ/PchI7wAAAABJRU5ErkJggg==');
    Future<List<int>> generar(List<EvidenciaPdf> evidencias) => ProveedorPdfService.generarBytes(reporte(dueno: true),
        businessName: 'Negocio Ejemplo', base: pw.Font.helvetica(), bold: pw.Font.helveticaBold(), evidencias: evidencias);
    final sin = paginas(await generar(const []));
    final con = paginas(await generar([
      EvidenciaPdf(que: 'Adelanto ADV-001 · S/ 500.00', fecha: '2026-11-01', imagenes: [png, png, png], archivos: 3), // 3 photos: 1 page
      EvidenciaPdf(que: 'Compra PU-0001', fecha: '2026-11-03', nota: 'Voucher', imagenes: [png]),
      EvidenciaPdf(que: 'Adelanto ADV-002', imagenes: List.filled(11, png), archivos: 11), // 11 photos: 2 pages
      const EvidenciaPdf(que: 'Gasto EX-0001', faltan: 1), // could not be downloaded: 1 page that says so
    ]));
    expect(sin, greaterThan(0));
    expect(con, sin + 5);
  });

  test('evidence goes newest first (12 Nov 2026): the latest record first, and its newest photo first', () {
    final grupos = ProveedorPdfService.agruparEvidencias([
      {'registro': 'advance', 'registro_id': 'ADV-003', 'fecha': '2026-05-24', 'subida': '2026-11-10T10:00:00Z', 'id': 1},
      {'registro': 'advance', 'registro_id': 'ADV-007', 'fecha': '2026-07-20', 'subida': '2026-11-10T09:00:00Z', 'id': 2},
      {'registro': 'advance', 'registro_id': 'ADV-007', 'fecha': '2026-07-20', 'subida': '2026-11-11T09:00:00Z', 'id': 3},
      {'registro': 'advance', 'registro_id': 'ADV-014', 'fecha': '2026-10-23', 'subida': '2026-11-10T08:00:00Z', 'id': 4},
      {'registro': 'purchase', 'registro_id': 'PU-0013', 'fecha': '2026-10-23', 'subida': '2026-11-12T08:00:00Z', 'id': 5},
    ]);
    expect(grupos.map((g) => g.map((e) => e['id']).toList()).toList(), [
      [5], // 23 Oct, uploaded last
      [4], // 23 Oct
      [3, 2], // 20 Jul, newest photo first
      [1], // 24 May
    ]);
  });

  test('the longest history (500 compras) still builds', () async {
    final bytes = await ProveedorPdfService.generarBytes(reporte(dueno: true, compras: 500),
        businessName: 'Negocio Ejemplo', base: pw.Font.helvetica(), bold: pw.Font.helveticaBold());
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
  });

  test('notes leave out "Nombre completo pendiente" (12 Nov 2026)', () {
    expect(ProveedorPdfService.notasSinPendientes('Vende café. Nombre completo pendiente.'), 'Vende café.');
    expect(ProveedorPdfService.notasSinPendientes('Nombre completo pendiente.'), isNull);
    expect(ProveedorPdfService.notasSinPendientes(null), isNull);
    expect(ProveedorPdfService.notasSinPendientes('Trabajador: piso.'), 'Trabajador: piso.');
  });

  test('dates and money read like the pedido PDF', () {
    expect(ProveedorPdfService.fecha('2026-11-03'), '03/11/2026');
    expect(ProveedorPdfService.soles(1800), 'S/ 1,800.00');
    expect(ProveedorPdfService.soles(null), '—');
    expect(ProveedorPdfService.kg(40), '40 kg');
  });
}
