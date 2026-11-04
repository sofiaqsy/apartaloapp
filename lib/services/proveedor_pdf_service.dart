import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'api_service.dart';

/// Reporte de un proveedor en PDF, con el mismo diseño del detalle de pedido (PedidoPdfService): cabecera con el
/// negocio y el N°, franja de datos, cajas con encabezado café y tablas. [reporte] es lo que da
/// /proveedores/:id/reporte; el dinero, las cuentas y los adelantos sólo vienen para dueños.
class ProveedorPdfService {
  static const _brown = PdfColor.fromInt(0xFF5C3317);
  static const _warmBg = PdfColor.fromInt(0xFFF9F5F1);
  static const _cardBorder = PdfColor.fromInt(0xFFE8DDD5);
  static const _textDark = PdfColor.fromInt(0xFF2D1A0E);
  static const _textGrey = PdfColor.fromInt(0xFF7A6A5E);

  static const _vende = {'cherry': 'Cereza', 'parchment': 'Pergamino', 'both': 'Cereza y pergamino'};
  static const _cafe = {'cherry': 'Cereza', 'parchment': 'Pergamino', 'green': 'Verde'};
  static const _tiposCuenta = {'bank_account': 'Cuenta', 'cci': 'CCI', 'phone_wallet': 'Yape o Plin', 'service_number': 'N° de servicio'};

  static String fecha(dynamic iso) {
    final d = DateTime.tryParse('${iso ?? ''}')?.toLocal();
    if (d == null) return '—';
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  }

  static String soles(dynamic v) {
    final n = (v is num) ? v.toDouble() : double.tryParse('${v ?? ''}');
    if (n == null) return '—';
    final t = n.toStringAsFixed(2).replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
    return 'S/ $t';
  }

  static String kg(dynamic v) {
    final n = (v is num) ? v.toDouble() : double.tryParse('${v ?? ''}') ?? 0;
    return '${n.toStringAsFixed(n == n.roundToDouble() ? 0 : 1)} kg';
  }

  static List<Map<String, dynamic>> _lista(dynamic v) =>
      v is List ? v.map((e) => e is Map ? Map<String, dynamic>.from(e) : <String, dynamic>{}).toList() : [];
  static Map<String, dynamic> _mapa(dynamic v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

  static pw.Widget _sectionHeader(String label) => pw.Container(
        width: double.infinity,
        padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: const pw.BoxDecoration(color: _brown),
        child: pw.Text(label, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.white, letterSpacing: 0.8)),
      );

  static pw.Widget _infoRow(String label, String value) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 5),
        child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.SizedBox(width: 90, child: pw.Text(label, style: const pw.TextStyle(fontSize: 9, color: _textGrey))),
          pw.Expanded(child: pw.Text(value, style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: _textDark))),
        ]),
      );

  static pw.Widget _dividerLine() => pw.Divider(height: 1, thickness: 0.5, color: _cardBorder);

  static pw.Widget _metaChip(String label, String value) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Text(label, style: const pw.TextStyle(fontSize: 8, color: _textGrey)),
        pw.SizedBox(height: 2),
        pw.Text(value, style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold, color: _textDark)),
      ]);

  static pw.Widget _cell(String text, {bool header = false, bool right = false}) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        child: pw.Text(text,
            textAlign: right ? pw.TextAlign.right : pw.TextAlign.left,
            style: header
                ? pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: _brown)
                : const pw.TextStyle(fontSize: 8.5, color: _textDark)),
      );

  static pw.Widget _caja(String titulo, List<pw.Widget> filas) => pw.Container(
        decoration: pw.BoxDecoration(border: pw.Border.all(color: _cardBorder), borderRadius: pw.BorderRadius.circular(6)),
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          _sectionHeader('  $titulo'),
          pw.Padding(padding: const pw.EdgeInsets.all(10), child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: filas)),
        ]),
      );

  /// Filas con línea entre ellas; las vacías no se muestran.
  static List<pw.Widget> _filas(List<(String, String?)> datos) {
    final out = <pw.Widget>[];
    for (final (k, v) in datos) {
      if (v == null || v.isEmpty || v == 'null') continue;
      if (out.isNotEmpty) out.add(_dividerLine());
      out.add(_infoRow(k, v));
    }
    if (out.isEmpty) out.add(pw.Text('Sin datos', style: const pw.TextStyle(fontSize: 9, color: _textGrey)));
    return out;
  }

  /// A titled table that continues on the next page when it is long (MultiPage only splits a table placed
  /// directly on the page, not inside a box).
  static List<pw.Widget> _tabla(String titulo, List<String> columnas, List<List<String>> filas, Set<int> derecha) => [
        _sectionHeader('  $titulo'),
        pw.Table(
          border: const pw.TableBorder(
            left: pw.BorderSide(color: _cardBorder),
            right: pw.BorderSide(color: _cardBorder),
            bottom: pw.BorderSide(color: _cardBorder),
            horizontalInside: pw.BorderSide(color: _cardBorder, width: 0.5),
          ),
          children: [
            pw.TableRow(
                decoration: const pw.BoxDecoration(color: _warmBg),
                children: [for (var i = 0; i < columnas.length; i++) _cell(columnas[i], header: true, right: derecha.contains(i))]),
            for (final f in filas) pw.TableRow(children: [for (var i = 0; i < f.length; i++) _cell(f[i], right: derecha.contains(i))]),
          ],
        ),
      ];

  /// [base] y [bold] sólo para las pruebas (sin internet); en la app se usa Noto Sans, como el PDF del pedido.
  static Future<Uint8List> generarBytes(Map<String, dynamic> reporte, {String? businessName, pw.Font? base, pw.Font? bold}) async {
    final doc = pw.Document();
    final font = base ?? await PdfGoogleFonts.notoSansRegular();
    final fontBold = bold ?? await PdfGoogleFonts.notoSansBold();

    final negocio = businessName ?? ApiService.businessName;
    final id = '${reporte['id'] ?? ''}';
    final emitido = fecha(reporte['generado'] ?? DateTime.now().toIso8601String());
    final esDueno = reporte['puede_editar'] == true;
    final es = [
      if (reporte['agricultor'] == true) 'Agricultor',
      if (reporte['comprador'] == true) 'Comprador',
      if (reporte['agricultor'] != true && reporte['comprador'] != true) 'Proveedor',
    ].join(' y ');
    final compras = _lista(reporte['compras_lista']);
    final resumen = _mapa(reporte['compras']);
    final dinero = reporte['dinero'] == null ? null : _mapa(reporte['dinero']);
    final adelantos = _lista(reporte['adelantos_lista']);
    final cuentas = _lista(reporte['cuentas']);
    final abiertos = adelantos.fold<double>(0, (s, a) => s + ((a['saldo'] as num?)?.toDouble() ?? double.tryParse('${a['saldo']}') ?? 0));

    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(28),
      maxPages: 40, // the report brings at most 500 compras
      theme: pw.ThemeData.withFont(base: font, bold: fontBold),
      footer: (ctx) => pw.Column(children: [
        pw.Divider(thickness: 0.5, color: _cardBorder),
        pw.Row(children: [
          pw.Expanded(
              child: pw.Text(esDueno ? 'Documento interno: tiene datos privados del proveedor.' : 'Documento interno.',
                  style: const pw.TextStyle(fontSize: 7.5, color: _textGrey))),
          pw.Text('Página ${ctx.pageNumber} de ${ctx.pagesCount}', style: const pw.TextStyle(fontSize: 7.5, color: _textGrey)),
        ]),
      ]),
      build: (ctx) => [
        // ── CABECERA ──
        pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Expanded(
            child: pw.Row(children: [
              pw.Flexible(
                  child: pw.Text(negocio.toUpperCase(),
                      style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold, color: _brown, letterSpacing: 1.5))),
              pw.SizedBox(width: 10),
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: pw.BoxDecoration(border: pw.Border.all(color: _brown, width: 1), borderRadius: pw.BorderRadius.circular(3)),
                child: pw.Text('PROVEEDOR', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: _brown, letterSpacing: 2)),
              ),
            ]),
          ),
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
            pw.Text('N° $id', style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: _brown)),
            pw.SizedBox(height: 6),
            pw.Text('Fecha de emisión: $emitido', style: const pw.TextStyle(fontSize: 8.5, color: _textGrey)),
          ]),
        ]),
        pw.SizedBox(height: 10),
        pw.Divider(height: 1, thickness: 1.5, color: _brown),
        pw.SizedBox(height: 12),

        // ── FRANJA ──
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: pw.BoxDecoration(color: _warmBg, borderRadius: pw.BorderRadius.circular(6), border: pw.Border.all(color: _cardBorder)),
          child: pw.Row(children: [
            pw.Expanded(child: _metaChip('Moneda', 'PEN - Soles')),
            pw.Expanded(child: _metaChip('Es', es)),
            pw.Expanded(child: _metaChip('Compras', '${resumen['n'] ?? compras.length} · ${kg(resumen['kg'])}')),
            pw.Expanded(child: _metaChip('Última compra', fecha(resumen['ultima']))),
          ]),
        ),
        pw.SizedBox(height: 12),

        // ── DATOS / CUENTAS ──
        pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Expanded(
            child: _caja(
                'DATOS DEL PROVEEDOR',
                _filas([
                  ('Nombre:', '${reporte['nombre'] ?? ''}'),
                  ('DNI o RUC:', reporte['documento']?.toString()),
                  ('Teléfono:', reporte['telefono']?.toString()),
                  ('Comunidad:', reporte['comunidad']?.toString()),
                  ('Vende:', _vende[reporte['vende']] ?? reporte['vende']?.toString()),
                  ('Lo recoge:', reporte['recoge']?.toString()),
                  ('Notas:', reporte['notas']?.toString()),
                ])),
          ),
          if (esDueno) ...[
            pw.SizedBox(width: 10),
            pw.Expanded(
              child: _caja(
                  'CUENTAS PARA PAGARLE',
                  _filas([
                    for (final c in cuentas)
                      (
                        '${_tiposCuenta[c['tipo']] ?? c['tipo']}:',
                        [if (c['banco'] != null) '${c['banco']}', '${c['numero'] ?? ''}', if (c['titular'] != null) '${c['titular']}'].join(' · ')
                      ),
                  ])),
            ),
          ],
        ]),
        pw.SizedBox(height: 12),

        // ── COMPRAS ──
        if (compras.isNotEmpty)
          ..._tabla(
            'COMPRAS',
            [
              'N°',
              'Fecha',
              'Compra',
              'Café',
              'Kilos',
              if (esDueno) ...['Precio/kg', 'Total'],
              'Estado'
            ],
            [
              for (var i = 0; i < compras.length; i++)
                [
                  '${i + 1}',
                  fecha(compras[i]['fecha']),
                  '${compras[i]['id']}',
                  _cafe[compras[i]['estado']] ?? '${compras[i]['estado'] ?? ''}',
                  kg(compras[i]['kg']),
                  if (esDueno) ...[
                    compras[i]['precio'] == null ? '—' : soles(compras[i]['precio']),
                    compras[i]['total'] == null ? '—' : soles(compras[i]['total']),
                  ],
                  '${compras[i]['situacion'] ?? ''}',
                ],
            ],
            esDueno ? {4, 5, 6} : {4},
          ),

        // ── ADELANTOS ──
        if (adelantos.isNotEmpty) ...[
          pw.SizedBox(height: 12),
          ..._tabla(
            'ADELANTOS',
            ['Fecha', 'Adelanto', 'Monto', 'Usado en café', 'Devuelto', 'Saldo'],
            [
              for (final a in adelantos)
                [fecha(a['fecha']), '${a['id']}', soles(a['monto']), soles(a['usado']), soles(a['devuelto']), soles(a['saldo'])],
            ],
            {2, 3, 4, 5},
          ),
        ],

        // ── RESUMEN ──
        if (dinero != null) ...[
          pw.SizedBox(height: 12),
          pw.Row(children: [
            pw.Expanded(child: pw.SizedBox()),
            pw.SizedBox(
              width: 210,
              child: pw.Container(
                decoration: pw.BoxDecoration(border: pw.Border.all(color: _cardBorder), borderRadius: pw.BorderRadius.circular(6)),
                child: pw.Column(children: [
                  _lineaResumen('Comprado:', soles(dinero['comprado'])),
                  pw.Divider(height: 1, thickness: 0.5, color: _cardBorder),
                  _lineaResumen('Adelantos abiertos:', soles(abiertos)),
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: const pw.BoxDecoration(
                        color: _brown, borderRadius: pw.BorderRadius.only(bottomLeft: pw.Radius.circular(5), bottomRight: pw.Radius.circular(5))),
                    child: pw.Row(children: [
                      pw.Expanded(
                          child: pw.Text('LE DEBEMOS:', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColors.white))),
                      pw.Text(soles(dinero['debe']), style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: PdfColors.white)),
                    ]),
                  ),
                ]),
              ),
            ),
          ]),
        ],
      ],
    ));
    return doc.save();
  }

  static pw.Widget _lineaResumen(String k, String v) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        child: pw.Row(children: [
          pw.Expanded(child: pw.Text(k, style: const pw.TextStyle(fontSize: 9, color: _textGrey))),
          pw.Text(v, style: const pw.TextStyle(fontSize: 9, color: _textDark)),
        ]),
      );
}

/// Reporte de Compras, mensual o anual (General Manager, 4 nov 2026), con el mismo diseño del reporte del proveedor.
/// Qué muestra lo decidió el área de Compras: franja de 4 datos, las compras del mes (o una tabla por mes en el
/// anual), por agricultor, por tipo de café, lo que espera, pagos, adelantos y los gastos de Compras. [reporte] es lo
/// que da /compras/reporte; el dinero sólo viene para dueños (lo decide la base).
class ComprasPdfService {
  static const _cortos = ['Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun', 'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic'];
  static String mesCorto(int mes) => _cortos[(mes - 1).clamp(0, 11)];

  /// "Mayo 2026", "Año 2026" o "May 2026 – Sep 2026": el periodo del reporte, para el título y el nombre del archivo.
  static String periodo(DateTime desde, DateTime hasta) {
    final meses = (hasta.year * 12 + hasta.month) - (desde.year * 12 + desde.month) + 1;
    if (meses == 12 && desde.month == 1) return 'Año ${desde.year}';
    if (meses == 1) return '${nombreMes(desde.month)} ${desde.year}';
    return '${mesCorto(desde.month)} ${desde.year} – ${mesCorto(hasta.month)} ${hasta.year}';
  }

  static const _meses = ['Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio', 'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre'];

  static String nombreMes(int mes) => _meses[(mes - 1).clamp(0, 11)];

  static String _n(dynamic v) => '${(v is num) ? v.toInt() : int.tryParse('${v ?? ''}') ?? 0}';
  /// "2026-05" → "Mayo 2026" (en el anual, sólo "Mayo").
  static String _etiquetaMes(dynamic v) {
    final t = '${v ?? ''}'.split('-');
    if (t.length < 2) return nombreMes(int.tryParse(t.first) ?? 1);
    return '${nombreMes(int.tryParse(t[1]) ?? 1)} ${t[0]}';
  }

  static String _cuantos(dynamic v, String uno, String varios) => '${_n(v)} ${_n(v) == '1' ? uno : varios}';
  static String _pct(dynamic v) => v == null ? '—' : '${v is num ? v.toStringAsFixed(1) : v}%';

  static Future<Uint8List> generarBytes(Map<String, dynamic> reporte, {String? businessName, pw.Font? base, pw.Font? bold}) async {
    final doc = pw.Document();
    final font = base ?? await PdfGoogleFonts.notoSansRegular();
    final fontBold = bold ?? await PdfGoogleFonts.notoSansBold();

    final negocio = businessName ?? ApiService.businessName;
    // Un rango de meses (purchasing_report_v2): un mes lista cada compra; varios traen la tabla por mes.
    final desde = DateTime.tryParse('${reporte['desde'] ?? ''}') ?? DateTime.now();
    final hasta = DateTime.tryParse('${reporte['hasta'] ?? ''}') ?? desde;
    final variosMeses = (int.tryParse('${reporte['meses'] ?? 1}') ?? 1) > 1;
    final anual = reporte['anual'] == true;
    final titulo = anual ? 'Reporte anual' : (variosMeses ? 'Reporte por meses' : 'Reporte mensual');
    final rango = periodo(desde, hasta);
    final cierre = ProveedorPdfService.fecha(reporte['cierre'] ?? reporte['hasta']);
    final esDueno = reporte['dueno'] == true;
    final franja = ProveedorPdfService._mapa(reporte['franja']);
    final esperan = ProveedorPdfService._mapa(reporte['esperan']);
    final compras = ProveedorPdfService._lista(reporte['compras']);
    final porMes = ProveedorPdfService._lista(reporte['por_mes']);
    final porAgricultor = ProveedorPdfService._lista(reporte['por_agricultor']);
    final porEstado = ProveedorPdfService._lista(reporte['por_estado']);
    final pagos = ProveedorPdfService._lista(reporte['pagos']);
    final adelantos = ProveedorPdfService._lista(reporte['adelantos']);
    final solicitudes = ProveedorPdfService._mapa(reporte['solicitudes']);
    final totalesAdelantos = ProveedorPdfService._mapa(reporte['adelantos_totales']);
    final gastos = ProveedorPdfService._lista(reporte['gastos']);
    String cafe(dynamic e) => ProveedorPdfService._cafe[e] ?? '${e ?? ''}';
    String soles(dynamic v) => v == null ? '—' : ProveedorPdfService.soles(v);
    const tabla = ProveedorPdfService._tabla;
    pw.Widget espacio() => pw.SizedBox(height: 12);
    pw.Widget nada(String t) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 6),
        child: pw.Text(t, style: const pw.TextStyle(fontSize: 9, color: ProveedorPdfService._textGrey)));

    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(28),
      maxPages: 40,
      theme: pw.ThemeData.withFont(base: font, bold: fontBold),
      footer: (ctx) => pw.Column(children: [
        pw.Divider(thickness: 0.5, color: ProveedorPdfService._cardBorder),
        pw.Row(children: [
          pw.Expanded(
              child: pw.Text(esDueno ? 'Documento interno: tiene precios y pagos.' : 'Documento interno.',
                  style: const pw.TextStyle(fontSize: 7.5, color: ProveedorPdfService._textGrey))),
          pw.Text('Página ${ctx.pageNumber} de ${ctx.pagesCount}', style: const pw.TextStyle(fontSize: 7.5, color: ProveedorPdfService._textGrey)),
        ]),
      ]),
      build: (ctx) => [
        // ── CABECERA ──
        pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Expanded(
            child: pw.Row(children: [
              pw.Flexible(
                  child: pw.Text(negocio.toUpperCase(),
                      style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold, color: ProveedorPdfService._brown, letterSpacing: 1.5))),
              pw.SizedBox(width: 10),
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: ProveedorPdfService._brown, width: 1), borderRadius: pw.BorderRadius.circular(3)),
                child: pw.Text('COMPRAS',
                    style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: ProveedorPdfService._brown, letterSpacing: 2)),
              ),
            ]),
          ),
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
            pw.Text(titulo,
                style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: ProveedorPdfService._brown)),
            pw.SizedBox(height: 3),
            pw.Text(rango, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: ProveedorPdfService._textDark)),
            pw.SizedBox(height: 4),
            pw.Text('Fecha de emisión: ${ProveedorPdfService.fecha(reporte['generado'] ?? DateTime.now().toIso8601String())}',
                style: const pw.TextStyle(fontSize: 8.5, color: ProveedorPdfService._textGrey)),
          ]),
        ]),
        pw.SizedBox(height: 10),
        pw.Divider(height: 1, thickness: 1.5, color: ProveedorPdfService._brown),
        pw.SizedBox(height: 12),

        // ── FRANJA ──
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: pw.BoxDecoration(
              color: ProveedorPdfService._warmBg,
              borderRadius: pw.BorderRadius.circular(6),
              border: pw.Border.all(color: ProveedorPdfService._cardBorder)),
          child: pw.Row(children: [
            pw.Expanded(child: ProveedorPdfService._metaChip('Kilos comprados', ProveedorPdfService.kg(franja['kg']))),
            pw.Expanded(child: ProveedorPdfService._metaChip('Compras recibidas', _n(franja['compras']))),
            pw.Expanded(child: ProveedorPdfService._metaChip('Agricultores', _n(franja['agricultores']))),
            pw.Expanded(
                child: esDueno
                    ? ProveedorPdfService._metaChip('Le debemos', soles(franja['debe']))
                    : ProveedorPdfService._metaChip('Sin precio', _cuantos(franja['sin_precio'], 'compra', 'compras'))),
            if (variosMeses) pw.Expanded(child: ProveedorPdfService._metaChip('Mayor parte de un agricultor', _pct(franja['mayor_parte']))),
          ]),
        ),
        // Finanzas: lo comprado y lo pagado en el periodo, lado a lado (pueden ser distintos: se paga después).
        if (esDueno) ...[
          pw.SizedBox(height: 8),
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: pw.BoxDecoration(borderRadius: pw.BorderRadius.circular(6), border: pw.Border.all(color: ProveedorPdfService._cardBorder)),
            child: pw.Row(children: [
              pw.Expanded(child: ProveedorPdfService._metaChip('Comprado en el periodo', soles(franja['comprado']))),
              pw.Expanded(child: ProveedorPdfService._metaChip('Pagado en el periodo', soles(franja['pagado']))),
              pw.Expanded(child: ProveedorPdfService._metaChip('Adelantos dados', soles(totalesAdelantos['dados']))),
              pw.Expanded(child: ProveedorPdfService._metaChip('Adelantos abiertos al $cierre', soles(totalesAdelantos['abiertos_al_cierre']))),
            ]),
          ),
        ],
        espacio(),

        // ── COMPRAS DEL MES / POR MES ──
        if (!variosMeses) ...[
          if (compras.isEmpty)
            pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [ProveedorPdfService._sectionHeader('  COMPRAS DEL MES'), nada('No hubo compras este mes.')])
          else
            ...tabla(
              'COMPRAS DEL MES',
              ['Fecha', 'Agricultor', 'Café', 'Kilos', if (esDueno) ...['Precio/kg', 'Total', 'Pagado', 'De adelantos', 'Debe'], 'Estado'],
              [
                for (final c in compras)
                  [
                    ProveedorPdfService.fecha(c['fecha']),
                    '${c['agricultor'] ?? ''}',
                    cafe(c['estado']),
                    ProveedorPdfService.kg(c['kg']),
                    if (esDueno) ...[soles(c['precio']), soles(c['total']), soles(c['pagado']), soles(c['de_adelantos']), soles(c['debe'])],
                    '${c['situacion'] ?? ''}',
                  ],
              ],
              esDueno ? {3, 4, 5, 6, 7, 8} : {3},
            ),
        ] else
          ...tabla(
            'POR MES',
            ['Mes', 'Compras', 'Kilos', 'Agricultores', if (esDueno) ...['Total', 'Precio medio/kg', 'Debe']],
            [
              for (final m in porMes)
                [
                  _etiquetaMes(m['mes']),
                  _n(m['compras']),
                  ProveedorPdfService.kg(m['kg']),
                  _n(m['agricultores']),
                  if (esDueno) ...[soles(m['total']), soles(m['precio_medio']), soles(m['debe'])],
                ],
              if (porMes.isEmpty) ['Sin compras en el periodo', '', '', '', if (esDueno) ...['', '', '']],
            ],
            esDueno ? {1, 2, 3, 4, 5, 6} : {1, 2, 3},
          ),
        espacio(),

        // ── POR AGRICULTOR ──
        if (porAgricultor.isNotEmpty) ...[
          ...tabla(
            'POR AGRICULTOR',
            ['Agricultor', 'Comunidad', 'Compras', 'Kilos', 'Parte', if (variosMeses) 'Meses', if (esDueno) ...['Total', 'Precio medio/kg']],
            [
              for (final a in porAgricultor)
                [
                  '${a['agricultor'] ?? ''}',
                  '${a['comunidad'] ?? '—'}',
                  _n(a['compras']),
                  ProveedorPdfService.kg(a['kg']),
                  _pct(a['parte']),
                  if (variosMeses) _n(a['meses']),
                  if (esDueno) ...[soles(a['total']), soles(a['precio_medio'])],
                ],
            ],
            {2, 3, 4, if (variosMeses) 5, if (esDueno) ...[variosMeses ? 6 : 5, variosMeses ? 7 : 6]},
          ),
          espacio(),
        ],

        // ── POR TIPO DE CAFÉ / LO QUE ESPERA ──
        pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Expanded(
            child: ProveedorPdfService._caja(
                'POR TIPO DE CAFÉ',
                ProveedorPdfService._filas([
                  for (final e in porEstado)
                    (
                      '${cafe(e['estado'])}:',
                      '${_cuantos(e['compras'], 'compra', 'compras')} · ${ProveedorPdfService.kg(e['kg'])}${esDueno ? ' · ${soles(e['total'])}' : ''}'
                    ),
                ])),
          ),
          pw.SizedBox(width: 10),
          pw.Expanded(
            child: ProveedorPdfService._caja(
                'LO QUE ESPERA',
                ProveedorPdfService._filas([
                  ('Sin precio:', '${_cuantos(esperan['sin_precio'], 'compra', 'compras')} · ${ProveedorPdfService.kg(esperan['sin_precio_kg'])}'),
                  ('Por pagar:', '${_cuantos(esperan['por_pagar'], 'compra', 'compras')}${esDueno ? ' · ${soles(esperan['por_pagar_monto'])}' : ''}'),
                  if (esDueno) ('Adelantos:', '${_cuantos(solicitudes['aprobadas'], 'aprobado', 'aprobados')} · ${_cuantos(solicitudes['rechazadas'], 'rechazado', 'rechazados')}'),
                ])),
          ),
        ]),

        // ── PAGOS ──
        if (esDueno && pagos.isNotEmpty) ...[
          espacio(),
          ...tabla(
            'PAGOS',
            ['Fecha', 'Agricultor', 'Compra', 'Cómo', 'Monto'],
            [
              for (final p in pagos)
                [ProveedorPdfService.fecha(p['fecha']), '${p['agricultor'] ?? ''}', '${p['compra'] ?? ''}', '${p['tipo'] ?? ''}', soles(p['monto'])],
            ],
            {4},
          ),
        ],

        // ── ADELANTOS ──
        if (esDueno && adelantos.isNotEmpty) ...[
          espacio(),
          ...tabla(
            'ADELANTOS',
            ['Fecha', 'Adelanto', 'Agricultor', 'Monto', 'Usado en café', 'Devuelto', 'Saldo al $cierre'],
            [
              for (final a in adelantos)
                [
                  ProveedorPdfService.fecha(a['fecha']),
                  '${a['id']}',
                  '${a['agricultor'] ?? ''}',
                  soles(a['monto']),
                  soles(a['usado']),
                  soles(a['devuelto']),
                  soles(a['saldo'])
                ],
            ],
            {3, 4, 5, 6},
          ),
        ],

        // ── GASTOS DE COMPRAS ──
        if (gastos.isNotEmpty) ...[
          espacio(),
          ...tabla(
            'GASTOS DE COMPRAS',
            ['Fecha', 'Categoría', 'Descripción', if (esDueno) 'Monto', 'Estado'],
            [
              for (final g in gastos)
                [
                  ProveedorPdfService.fecha(g['fecha']),
                  '${g['categoria'] ?? ''}',
                  '${g['descripcion'] ?? ''}',
                  if (esDueno) soles(g['monto']),
                  '${g['estado'] ?? ''}',
                ],
            ],
            esDueno ? {3} : <int>{},
          ),
        ],
      ],
    ));
    return doc.save();
  }
}

/// Reporte de Producción (General Manager, 4 nov 2026), con el mismo diseño del de Compras. Qué muestra lo decidió el
/// área de Producción: franja (lotes de tostado, verde que entró, tostado que salió, merma media); los lotes de tostado del mes (o una
/// tabla por mes); merma por lote verde; stock de verde y de tostado hoy; café por procesar hoy; costos (sólo dueños).
/// [reporte] es lo que da /produccion/reporte.
class ProduccionPdfService {
  static String _kg(dynamic v) => v == null ? '—' : ProveedorPdfService.kg(v);
  static String _pct(dynamic v) => v == null ? '—' : '${v is num ? v.toStringAsFixed(1) : v}%';
  static const _cafe = {'cherry': 'Cereza', 'parchment': 'Pergamino', 'green': 'Verde'};

  static Future<Uint8List> generarBytes(Map<String, dynamic> reporte, {String? businessName, pw.Font? base, pw.Font? bold}) async {
    final doc = pw.Document();
    final font = base ?? await PdfGoogleFonts.notoSansRegular();
    final fontBold = bold ?? await PdfGoogleFonts.notoSansBold();
    const tabla = ProveedorPdfService._tabla;

    final negocio = businessName ?? ApiService.businessName;
    final desde = DateTime.tryParse('${reporte['desde'] ?? ''}') ?? DateTime.now();
    final hasta = DateTime.tryParse('${reporte['hasta'] ?? ''}') ?? desde;
    final variosMeses = (int.tryParse('${reporte['meses'] ?? 1}') ?? 1) > 1;
    final anual = reporte['anual'] == true;
    final titulo = anual ? 'Reporte anual' : (variosMeses ? 'Reporte por meses' : 'Reporte mensual');
    final esDueno = reporte['dueno'] == true;
    final franja = ProveedorPdfService._mapa(reporte['franja']);
    final enCurso = ProveedorPdfService._mapa(reporte['en_curso']);
    final tuestes = ProveedorPdfService._lista(reporte['tuestes']);
    final porMes = ProveedorPdfService._lista(reporte['por_mes']);
    final porLote = ProveedorPdfService._lista(reporte['por_lote']);
    final verde = ProveedorPdfService._lista(reporte['verde_hoy']);
    final tostado = ProveedorPdfService._lista(reporte['tostado_hoy']);
    final porProcesar = ProveedorPdfService._lista(reporte['por_procesar']);
    final costos = ProveedorPdfService._lista(reporte['costos']);
    final costosMes = ProveedorPdfService._lista(reporte['costos_por_mes']);
    final hoy = ProveedorPdfService.fecha(reporte['generado'] ?? DateTime.now().toIso8601String());
    String soles(dynamic v) => v == null ? '—' : ProveedorPdfService.soles(v);
    pw.Widget espacio() => pw.SizedBox(height: 12);
    pw.Widget nada(String titulo, String t) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          ProveedorPdfService._sectionHeader('  $titulo'),
          pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 4),
              child: pw.Text(t, style: const pw.TextStyle(fontSize: 9, color: ProveedorPdfService._textGrey))),
        ]);
    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(28),
      maxPages: 40,
      theme: pw.ThemeData.withFont(base: font, bold: fontBold),
      footer: (ctx) => pw.Column(children: [
        pw.Divider(thickness: 0.5, color: ProveedorPdfService._cardBorder),
        pw.Row(children: [
          pw.Expanded(
              child: pw.Text(esDueno ? 'Documento interno: tiene costos.' : 'Documento interno.',
                  style: const pw.TextStyle(fontSize: 7.5, color: ProveedorPdfService._textGrey))),
          pw.Text('Página ${ctx.pageNumber} de ${ctx.pagesCount}', style: const pw.TextStyle(fontSize: 7.5, color: ProveedorPdfService._textGrey)),
        ]),
      ]),
      build: (ctx) => [
        // ── CABECERA ──
        pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Expanded(
            child: pw.Row(children: [
              pw.Flexible(
                  child: pw.Text(negocio.toUpperCase(),
                      style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold, color: ProveedorPdfService._brown, letterSpacing: 1.5))),
              pw.SizedBox(width: 10),
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: ProveedorPdfService._brown, width: 1), borderRadius: pw.BorderRadius.circular(3)),
                child: pw.Text('PRODUCCIÓN',
                    style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: ProveedorPdfService._brown, letterSpacing: 2)),
              ),
            ]),
          ),
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
            pw.Text(titulo, style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: ProveedorPdfService._brown)),
            pw.SizedBox(height: 3),
            pw.Text(ComprasPdfService.periodo(desde, hasta),
                style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: ProveedorPdfService._textDark)),
            pw.SizedBox(height: 4),
            pw.Text('Fecha de emisión: $hoy', style: const pw.TextStyle(fontSize: 8.5, color: ProveedorPdfService._textGrey)),
          ]),
        ]),
        pw.SizedBox(height: 10),
        pw.Divider(height: 1, thickness: 1.5, color: ProveedorPdfService._brown),
        pw.SizedBox(height: 12),

        // ── FRANJA ──
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: pw.BoxDecoration(
              color: ProveedorPdfService._warmBg,
              borderRadius: pw.BorderRadius.circular(6),
              border: pw.Border.all(color: ProveedorPdfService._cardBorder)),
          child: pw.Row(children: [
            pw.Expanded(child: ProveedorPdfService._metaChip('Lotes de tostado terminados', ComprasPdfService._n(franja['tuestes']))),
            pw.Expanded(child: ProveedorPdfService._metaChip('Café verde que entró', _kg(franja['kg_verde']))),
            pw.Expanded(child: ProveedorPdfService._metaChip('Café tostado que salió', _kg(franja['kg_tostado']))),
            pw.Expanded(child: ProveedorPdfService._metaChip('Merma media', _pct(franja['merma_pct']))),
          ]),
        ),
        espacio(),

        // ── A. LOTES DE TOSTADO DEL MES / POR MES ── (antes "Tuestes": General Manager, 4 nov 2026)
        if (!variosMeses)
          if (tuestes.isEmpty)
            nada('LOTES DE TOSTADO DEL MES', 'No hubo lotes de tostado este mes.')
          else
            ...tabla(
              'LOTES DE TOSTADO DEL MES',
              ['Fecha', 'Producto', 'Lote verde', 'Verde', 'Tostado', 'Merma', 'Estado'],
              [
                for (final t in tuestes)
                  [
                    ProveedorPdfService.fecha(t['fecha']),
                    '${t['producto'] ?? '—'}',
                    '${t['lote'] ?? '—'}',
                    _kg(t['kg_verde']),
                    _kg(t['kg_tostado']),
                    _pct(t['merma_pct']),
                    '${t['estado'] ?? ''}',
                  ],
              ],
              {3, 4, 5},
            )
        else if (porMes.isEmpty)
          nada('POR MES', 'No hubo lotes de tostado terminados en el periodo.')
        else
          ...tabla(
            'POR MES',
            ['Mes', 'Lotes de tostado', 'Verde', 'Tostado', 'Merma'],
            [
              for (final m in porMes)
                [ComprasPdfService._etiquetaMes(m['mes']), ComprasPdfService._n(m['tuestes']), _kg(m['kg_verde']), _kg(m['kg_tostado']), _pct(m['merma_pct'])],
            ],
            {1, 2, 3, 4},
          ),
        pw.Padding(
          padding: const pw.EdgeInsets.only(top: 6),
          child: pw.Text(
              'Hoy: ${ComprasPdfService._cuantos(enCurso['programados'], 'lote de tostado programado', 'lotes de tostado programados')} · '
              '${ComprasPdfService._cuantos(enCurso['tostando'], 'tostando', 'tostando')}',
              style: const pw.TextStyle(fontSize: 8.5, color: ProveedorPdfService._textGrey)),
        ),
        espacio(),

        // ── B. MERMA POR LOTE VERDE ──
        if (porLote.isNotEmpty) ...[
          ...tabla(
            'MERMA POR LOTE VERDE',
            ['Lote', 'Variedad', 'Cosecha', 'Lotes de tostado', 'Verde', 'Tostado', 'Merma'],
            [
              for (final l in porLote)
                [
                  '${l['lote'] ?? '—'}',
                  '${l['variedad'] ?? '—'}',
                  '${l['cosecha'] ?? '—'}',
                  ComprasPdfService._n(l['tuestes']),
                  _kg(l['kg_verde']),
                  _kg(l['kg_tostado']),
                  _pct(l['merma_pct']),
                ],
            ],
            {3, 4, 5, 6},
          ),
          espacio(),
        ],

        // ── C. CAFÉ VERDE HOY ──
        if (verde.isEmpty)
          nada('CAFÉ VERDE EN STOCK HOY ($hoy)', 'No hay café verde en stock.')
        else
          ...tabla(
            'CAFÉ VERDE EN STOCK HOY ($hoy)',
            ['Lote', 'Variedad', 'Cosecha', 'Entró', 'Queda'],
            [
              for (final g in verde)
                ['${g['lote'] ?? '—'}', '${g['variedad'] ?? '—'}', '${g['cosecha'] ?? '—'}', _kg(g['kg_inicial']), _kg(g['kg_ahora'])],
            ],
            {3, 4},
          ),
        espacio(),

        // ── D. CAFÉ TOSTADO HOY ──
        if (tostado.isEmpty)
          nada('CAFÉ TOSTADO DISPONIBLE HOY ($hoy)', 'No hay café tostado disponible.')
        else
          ...tabla(
            'CAFÉ TOSTADO DISPONIBLE HOY ($hoy)',
            // Por producto, como en la pantalla del producto (General Manager, 4 nov 2026).
            ['Producto', 'Lote', 'Tostado el', 'Disponible'],
            [
              for (final t in tostado) ['${t['producto'] ?? '—'}', '${t['lote'] ?? '—'}', ProveedorPdfService.fecha(t['fecha']), _kg(t['kg'])],
            ],
            {3},
          ),

        // ── E. POR PROCESAR HOY ──
        if (porProcesar.isNotEmpty) ...[
          espacio(),
          ...tabla(
            'CAFÉ COMPRADO POR PROCESAR HOY ($hoy)',
            ['Café', 'Lotes', 'Kilos', 'Calidad'],
            [
              for (final p in porProcesar)
                [
                  _cafe[p['estado']] ?? '${p['estado'] ?? ''}',
                  ComprasPdfService._n(p['lotes']),
                  _kg(p['kg']),
                  p['calidad'] == 'pending' ? 'Por revisar' : '${p['calidad'] ?? ''}',
                ],
            ],
            {1, 2},
          ),
        ],

        // ── F. COSTOS (sólo dueños) ──
        if (esDueno) ...[
          espacio(),
          if (costos.isEmpty)
            nada('COSTOS DE PRODUCCIÓN', 'No hubo gastos de Producción en el periodo.')
          else
            ...tabla(
              'COSTOS DE PRODUCCIÓN',
              ['Categoría', 'Pendiente', 'Pagado', 'Total'],
              [
                for (final c in costos) ['${c['categoria'] ?? ''}', soles(c['pendiente']), soles(c['pagado']), soles(c['total'])],
              ],
              {1, 2, 3},
            ),
          if (variosMeses && costosMes.isNotEmpty) ...[
            espacio(),
            ...tabla(
              'COSTOS POR MES',
              ['Mes', 'Pendiente', 'Pagado', 'Total'],
              [
                for (final c in costosMes) [ComprasPdfService._etiquetaMes(c['mes']), soles(c['pendiente']), soles(c['pagado']), soles(c['total'])],
              ],
              {1, 2, 3},
            ),
          ],
        ],
      ],
    ));
    return doc.save();
  }
}
