import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'api_service.dart';
import '../screens/tabs/pedidos/helpers/producto_parser.dart';

class PedidoPdfService {
  // Colores del diseño
  static const _brown = PdfColor.fromInt(0xFF5C3317);
  static const _brownLight = PdfColor.fromInt(0xFF8B5E3C);
  static const _warmBg = PdfColor.fromInt(0xFFF9F5F1);
  static const _cardBorder = PdfColor.fromInt(0xFFE8DDD5);
  static const _textDark = PdfColor.fromInt(0xFF2D1A0E);
  static const _textGrey = PdfColor.fromInt(0xFF7A6A5E);
  static const _green = PdfColor.fromInt(0xFF2E7D32);
  static const _red = PdfColor.fromInt(0xFFC62828);

  static String _grindLabel(dynamic grind) {
    if (grind == null || grind.toString().isEmpty) return '';
    return switch (grind.toString()) {
      'ground' => 'Molido',
      'whole'  => 'Grano',
      'green'  => 'Verde',
      _        => grind.toString(),
    };
  }

  static String _estadoLabel(String estado) {
    return switch (estado.toUpperCase()) {
      'PENDIENTE'      => 'Pendiente',
      'CONFIRMADO'     => 'Confirmado',
      'EN_PREPARACION' => 'En Preparación',
      'LISTO'          => 'Listo',
      'ENVIADO'        => 'Enviado',
      'ENTREGADO'      => 'Entregado',
      'COMPLETADO'     => 'Completado',
      'CANCELADO'      => 'Cancelado',
      _                => estado,
    };
  }

  static PdfColor _estadoColor(String estado) {
    return switch (estado.toUpperCase()) {
      'ENTREGADO' || 'COMPLETADO' || 'CONFIRMADO' => _green,
      'CANCELADO'                                  => _red,
      _                                            => PdfColor.fromInt(0xFFE65100),
    };
  }

  static pw.Widget _sectionHeader(String label) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: const pw.BoxDecoration(color: _brown),
      child: pw.Row(children: [
        pw.Text(label,
          style: pw.TextStyle(
            fontSize: 10,
            fontWeight: pw.FontWeight.bold,
            color: PdfColors.white,
            letterSpacing: 0.8,
          )),
      ]),
    );
  }

  static pw.Widget _infoRow(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 5),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(width: 90,
            child: pw.Text(label,
              style: const pw.TextStyle(fontSize: 9, color: _textGrey))),
          pw.Expanded(
            child: pw.Text(value,
              style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: _textDark))),
        ],
      ),
    );
  }

  static pw.Widget _dividerLine() => pw.Divider(height: 1, thickness: 0.5, color: _cardBorder);

  static pw.Widget _metaChip(String label, String value) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(label,
          style: const pw.TextStyle(fontSize: 8, color: _textGrey)),
        pw.SizedBox(height: 2),
        pw.Text(value,
          style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold, color: _textDark)),
      ],
    );
  }

  /// Genera el PDF y devuelve los bytes — úsalo para preview o share.
  static Future<Uint8List> generarBytes({
    required Map<String, dynamic> pedido,
    required List<Map<String, dynamic>> productos,
    String? businessName,
  }) async {
    final doc = pw.Document();
    final font = await PdfGoogleFonts.notoSansRegular();
    final fontBold = await PdfGoogleFonts.notoSansBold();

    final negocio = businessName ?? ApiService.businessName;
    final pedidoId = pedido['id']?.toString() ?? '';
    final fecha = pedido['fecha']?.toString() ?? '';
    final hora  = pedido['hora']?.toString() ?? '';
    final cliente = pedido['cliente']?.toString() ?? '';
    final telefono = (pedido['whatsapp'] ?? pedido['telefono'] ?? '').toString();
    final direccion = pedido['direccion']?.toString() ?? '';
    final ciudad = pedido['ciudad']?.toString() ?? '';
    final depto = pedido['departamento']?.toString() ?? '';
    final tipoEnvio = pedido['tipoEnvio']?.toString() ?? '';
    final empresaEnvio = pedido['empresaEnvio']?.toString() ?? '';
    final observaciones = pedido['observaciones']?.toString() ?? '';
    final estado = (pedido['estado'] ?? 'PENDIENTE').toString();
    final estadoPago = (pedido['estadoPago'] ?? 'PENDIENTE_PAGO').toString();
    final costoEnvio = (pedido['costoEnvio'] ?? 0).toDouble();
    final subtotal = (pedido['subtotal'] ?? 0).toDouble();
    final total = (pedido['total'] ?? 0).toDouble();
    final subFinal = subtotal > 0 ? subtotal : (total - costoEnvio);

    final estadoPagoLabel = switch (estadoPago.toUpperCase()) {
      'PAGADO'        => 'Pagado',
      'PARCIAL'       => 'Parcial',
      'NO_APLICA'     => 'Sin cobro',
      _               => 'Pendiente de pago',
    };

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        theme: pw.ThemeData.withFont(base: font, bold: fontBold),
        build: (ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [

            // ── CABECERA ───────────────────────────────────────────
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                // Nombre del negocio
                pw.Expanded(
                  child: pw.Text(negocio.toUpperCase(),
                    style: pw.TextStyle(
                      fontSize: 22,
                      fontWeight: pw.FontWeight.bold,
                      color: _brown,
                      letterSpacing: 1.5,
                    )),
                ),

                // Número y fechas
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text('N° $pedidoId',
                      style: pw.TextStyle(
                        fontSize: 13,
                        fontWeight: pw.FontWeight.bold,
                        color: _brown,
                      )),
                    pw.SizedBox(height: 6),
                    pw.Text('Fecha de emisión: $fecha',
                      style: const pw.TextStyle(fontSize: 8.5, color: _textGrey)),
                    if (hora.isNotEmpty)
                      pw.Text('Hora: $hora',
                        style: const pw.TextStyle(fontSize: 8.5, color: _textGrey)),
                  ],
                ),
              ],
            ),

            pw.SizedBox(height: 10),
            pw.Divider(height: 1, thickness: 1.5, color: _brown),
            pw.SizedBox(height: 12),

            // ── INFO STRIP (moneda / fecha / N° pedido / método pago / estado) ──
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: pw.BoxDecoration(
                color: _warmBg,
                borderRadius: pw.BorderRadius.circular(6),
                border: pw.Border.all(color: _cardBorder),
              ),
              child: pw.Row(
                children: [
                  pw.Expanded(child: _metaChip('Moneda', 'PEN - Soles')),
                  pw.Expanded(child: _metaChip('Fecha de pedido', fecha)),
                  pw.Expanded(child: _metaChip('N° de pedido', pedidoId)),
                  pw.Expanded(child: _metaChip('Estado del pedido', _estadoLabel(estado))),
                ],
              ),
            ),

            pw.SizedBox(height: 12),

            // ── DATOS CLIENTE / DATOS ENVÍO ────────────────────────
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                // Datos del cliente
                pw.Expanded(
                  child: pw.Container(
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(color: _cardBorder),
                      borderRadius: pw.BorderRadius.circular(6),
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        _sectionHeader('  DATOS DEL CLIENTE'),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(10),
                          child: pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.start,
                            children: [
                              _infoRow('Nombre:', cliente.isNotEmpty ? cliente : '—'),
                              _dividerLine(),
                              _infoRow('Teléfono:', telefono.isNotEmpty ? telefono : '—'),
                              if (observaciones.isNotEmpty) ...[
                                _dividerLine(),
                                _infoRow('Obs:', observaciones),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                pw.SizedBox(width: 10),

                // Datos de envío
                pw.Expanded(
                  child: pw.Container(
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(color: _cardBorder),
                      borderRadius: pw.BorderRadius.circular(6),
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        _sectionHeader('  DATOS DE ENVÍO'),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(10),
                          child: pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.start,
                            children: [
                              if (direccion.isNotEmpty)
                                _infoRow('Dirección:', direccion),
                              if (ciudad.isNotEmpty || depto.isNotEmpty) ...[
                                if (direccion.isNotEmpty) _dividerLine(),
                                _infoRow('Distrito:', ciudad.isNotEmpty ? ciudad : '—'),
                                _dividerLine(),
                                _infoRow('Departamento:', depto.isNotEmpty ? depto : '—'),
                              ],
                              if (tipoEnvio.isNotEmpty) ...[
                                _dividerLine(),
                                _infoRow('Tipo envío:', tipoEnvio),
                              ],
                              if (empresaEnvio.isNotEmpty) ...[
                                _dividerLine(),
                                _infoRow('Courier:', empresaEnvio),
                              ],
                              if (direccion.isEmpty && ciudad.isEmpty)
                                pw.Text('Sin datos de envío',
                                  style: const pw.TextStyle(fontSize: 9, color: _textGrey)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),

            pw.SizedBox(height: 12),

            // ── DETALLE DE PRODUCTOS ───────────────────────────────
            pw.Container(
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: _cardBorder),
                borderRadius: pw.BorderRadius.circular(6),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  _sectionHeader('  DETALLE DE PRODUCTOS'),
                  pw.Table(
                    columnWidths: {
                      0: const pw.FixedColumnWidth(22),
                      1: const pw.FlexColumnWidth(3),
                      2: const pw.FlexColumnWidth(2),
                      3: const pw.FixedColumnWidth(40),
                      4: const pw.FixedColumnWidth(60),
                      5: const pw.FixedColumnWidth(55),
                    },
                    border: pw.TableBorder(
                      horizontalInside: pw.BorderSide(color: _cardBorder, width: 0.5),
                    ),
                    children: [
                      // Encabezado de tabla
                      pw.TableRow(
                        decoration: const pw.BoxDecoration(color: _warmBg),
                        children: [
                          _tableHeader('N°'),
                          _tableHeader('Producto'),
                          _tableHeader('Presentación'),
                          _tableHeader('Cant.', center: true),
                          _tableHeader('P. Unit.', center: true),
                          _tableHeader('Subtotal', center: true),
                        ],
                      ),
                      // Filas de productos (agrupados para ocultar split stock/pre-venta)
                      ...agruparProductos(productos).asMap().entries.map((entry) {
                        final i = entry.key;
                        final p = entry.value;
                        final nombre = p['nombre']?.toString() ?? '';
                        final cant = (p['cantidad'] as num?)?.toInt() ?? 1;
                        final precio = (p['precio'] as num?)?.toDouble() ?? 0;
                        final sub = (p['subtotal'] as num?)?.toDouble() ?? (precio * cant);
                        final unit = p['unit']?.toString() ?? '';
                        final grind = _grindLabel(p['grind']);
                        final pres = [if (unit.isNotEmpty && unit != 'unidad') unit, if (grind.isNotEmpty) grind].join(' ');
                        final roastedAt = p['roastedAt']?.toString() ?? '';

                        return pw.TableRow(
                          children: [
                            _tableCell('${i + 1}', center: true),
                            // Nombre + fecha de tueste debajo
                            pw.Padding(
                              padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 7),
                              child: pw.Column(
                                crossAxisAlignment: pw.CrossAxisAlignment.start,
                                children: [
                                  pw.Text(nombre,
                                    style: const pw.TextStyle(fontSize: 8.5, color: _textDark)),
                                  if (roastedAt.isNotEmpty) ...[
                                    pw.SizedBox(height: 2),
                                    pw.Text('Tueste: $roastedAt',
                                      style: const pw.TextStyle(fontSize: 7, color: _textGrey)),
                                  ],
                                ],
                              ),
                            ),
                            _tableCell(pres.isNotEmpty ? pres : '—'),
                            _tableCell('$cant', center: true),
                            _tableCell('S/ ${precio.toStringAsFixed(2)}', center: true),
                            _tableCell('S/ ${sub.toStringAsFixed(2)}', center: true),
                          ],
                        );
                      }),
                    ],
                  ),
                ],
              ),
            ),

            pw.SizedBox(height: 12),

            // ── DETALLE ENVÍO + RESUMEN COSTOS ────────────────────
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                // Detalle envío (izquierda)
                if (costoEnvio > 0 || tipoEnvio.isNotEmpty)
                  pw.Expanded(
                    child: pw.Container(
                      padding: const pw.EdgeInsets.all(10),
                      decoration: pw.BoxDecoration(
                        border: pw.Border.all(color: _cardBorder),
                        borderRadius: pw.BorderRadius.circular(6),
                      ),
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Row(children: [
                            pw.Text('DETALLE DE ENVÍO',
                              style: pw.TextStyle(
                                fontSize: 9,
                                fontWeight: pw.FontWeight.bold,
                                color: _brown,
                                letterSpacing: 0.5,
                              )),
                          ]),
                          pw.SizedBox(height: 8),
                          if (tipoEnvio.isNotEmpty)
                            _infoRow('Método:', tipoEnvio),
                          if (empresaEnvio.isNotEmpty)
                            _infoRow('Empresa:', empresaEnvio),
                          if (costoEnvio > 0)
                            _infoRow('Costo:', 'S/ ${costoEnvio.toStringAsFixed(2)}'),
                        ],
                      ),
                    ),
                  )
                else
                  pw.Expanded(child: pw.SizedBox()),

                pw.SizedBox(width: 10),

                // Resumen costos (derecha)
                pw.SizedBox(
                  width: 190,
                  child: pw.Container(
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(color: _cardBorder),
                      borderRadius: pw.BorderRadius.circular(6),
                    ),
                    child: pw.Column(
                      children: [
                        pw.Padding(
                          padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                          child: pw.Row(children: [
                            pw.Expanded(
                              child: pw.Text('Subtotal de productos:',
                                style: const pw.TextStyle(fontSize: 9, color: _textGrey))),
                            pw.Text('S/ ${subFinal.toStringAsFixed(2)}',
                              style: const pw.TextStyle(fontSize: 9, color: _textDark)),
                          ]),
                        ),
                        if (costoEnvio > 0) ...[
                          pw.Divider(height: 1, thickness: 0.5, color: _cardBorder),
                          pw.Padding(
                            padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                            child: pw.Row(children: [
                              pw.Expanded(
                                child: pw.Text('Costo de envío:',
                                  style: const pw.TextStyle(fontSize: 9, color: _textGrey))),
                              pw.Text('S/ ${costoEnvio.toStringAsFixed(2)}',
                                style: const pw.TextStyle(fontSize: 9, color: _textDark)),
                            ]),
                          ),
                        ],
                        // Total
                        pw.Container(
                          padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: const pw.BoxDecoration(
                            color: _brown,
                            borderRadius: pw.BorderRadius.only(
                              bottomLeft: pw.Radius.circular(5),
                              bottomRight: pw.Radius.circular(5),
                            ),
                          ),
                          child: pw.Row(children: [
                            pw.Expanded(
                              child: pw.Column(
                                crossAxisAlignment: pw.CrossAxisAlignment.start,
                                children: [
                                  pw.Text('TOTAL A PAGAR:',
                                    style: pw.TextStyle(
                                      fontSize: 9,
                                      fontWeight: pw.FontWeight.bold,
                                      color: PdfColors.white,
                                    )),
                                  pw.Text(estadoPagoLabel,
                                    style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.white)),
                                ],
                              ),
                            ),
                            pw.Text('S/ ${total.toStringAsFixed(2)}',
                              style: pw.TextStyle(
                                fontSize: 18,
                                fontWeight: pw.FontWeight.bold,
                                color: PdfColors.white,
                              )),
                          ]),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),

            pw.Spacer(),

            // ── PIE DE PÁGINA ──────────────────────────────────────
            pw.Divider(thickness: 0.5, color: _cardBorder),
            pw.SizedBox(height: 6),
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                // Datos de pago (reemplaza info del negocio)
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('PAGO — BCP',
                        style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: _brown)),
                      pw.SizedBox(height: 3),
                      pw.Text('Soles:  1917137473085',
                        style: const pw.TextStyle(fontSize: 7.5, color: _textDark)),
                      pw.Text('CCI:    00219100713747308552',
                        style: const pw.TextStyle(fontSize: 7.5, color: _textDark)),
                      pw.Text('Titular: VR Coffee',
                        style: const pw.TextStyle(fontSize: 7.5, color: _textGrey)),
                    ],
                  ),
                ),
                // Agradecimiento
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text('¡Gracias por tu compra!',
                      style: pw.TextStyle(
                        fontSize: 11,
                        fontWeight: pw.FontWeight.bold,
                        color: _brown,
                      )),
                    pw.SizedBox(height: 2),
                    pw.Text('Disfruta lo mejor del cafe peruano',
                      style: const pw.TextStyle(fontSize: 8, color: _textGrey)),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );

    return doc.save();
  }

  /// Mantiene la compatibilidad: genera y abre el share sheet directamente.
  static Future<void> generarYCompartir({
    required Map<String, dynamic> pedido,
    required List<Map<String, dynamic>> productos,
    String? businessName,
  }) async {
    final bytes    = await generarBytes(pedido: pedido, productos: productos, businessName: businessName);
    final pedidoId = pedido['id']?.toString() ?? 'pedido';
    await Printing.sharePdf(bytes: bytes, filename: 'pedido_$pedidoId.pdf');
  }

  static pw.Widget _tableHeader(String text, {bool center = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      child: pw.Text(text,
        textAlign: center ? pw.TextAlign.center : pw.TextAlign.left,
        style: pw.TextStyle(
          fontSize: 8.5,
          fontWeight: pw.FontWeight.bold,
          color: _textDark,
        )),
    );
  }

  static pw.Widget _tableCell(String text, {bool center = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 7),
      child: pw.Text(text,
        textAlign: center ? pw.TextAlign.center : pw.TextAlign.left,
        style: const pw.TextStyle(fontSize: 8.5, color: _textDark)),
    );
  }
}
