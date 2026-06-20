import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import '../../helpers/estado_pago_helper.dart';

/// Sección unificada de pago + comprobantes.
/// Cada pago muestra sus comprobantes enlazados (por paymentId).
class SeccionPagoWidget extends StatelessWidget {
  final Map<String, dynamic> pedido;
  final String estadoPago;
  final double montoPagado;
  final List<Map<String, dynamic>> pagos;
  final List<Map<String, dynamic>> evidencias;
  final bool actualizando;
  final bool subiendoEvidencia;
  final Function(String estadoPago, {double? monto, bool? esNuevoPago}) onCambiarEstadoPago;
  final Future<void> Function(ImageSource source, {String? paymentId}) onAgregarComprobante;
  final Future<void> Function(String pagoId)? onEliminarPago;
  final Future<void> Function(Map<String, dynamic> evidencia)? onEliminarEvidencia;

  const SeccionPagoWidget({
    super.key,
    required this.pedido,
    required this.estadoPago,
    required this.montoPagado,
    required this.pagos,
    required this.evidencias,
    required this.actualizando,
    required this.subiendoEvidencia,
    required this.onCambiarEstadoPago,
    required this.onAgregarComprobante,
    this.onEliminarPago,
    this.onEliminarEvidencia,
  });

  // ── Dialogo registrar pago ────────────────────────────────────────────────

  void _mostrarDialogoRegistrarPago(BuildContext context) {
    final total = (pedido['total'] ?? 0).toDouble();
    final saldoRestante = total - montoPagado;
    final esPrimerPago = montoPagado == 0;
    final controller = TextEditingController(
      text: saldoRestante > 0 ? saldoRestante.toStringAsFixed(2) : total.toStringAsFixed(2),
    );

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(children: [
          Icon(Icons.payments, color: Colors.green.shade600),
          const SizedBox(width: 12),
          Text(esPrimerPago ? 'Registrar Pago' : 'Registrar Abono'),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Column(children: [
                _fila('Total del pedido', total, Colors.grey.shade700),
                if (!esPrimerPago) ...[
                  const SizedBox(height: 4),
                  _fila('Ya pagado', montoPagado, Colors.green.shade600),
                  const Divider(height: 12),
                  _fila('Saldo pendiente', saldoRestante, Colors.red.shade600, bold: true),
                ],
              ]),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              autofocus: true,
              decoration: InputDecoration(
                labelText: esPrimerPago ? 'Monto recibido' : 'Monto del abono',
                prefixText: 'S/ ',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                filled: true,
                fillColor: Colors.grey.shade50,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(spacing: 8, children: [
              if (saldoRestante > 0)
                ActionChip(
                  label: Text('S/ ${saldoRestante.toStringAsFixed(0)} (completo)'),
                  backgroundColor: Colors.green.shade50,
                  onPressed: () => controller.text = saldoRestante.toStringAsFixed(2),
                ),
              if (saldoRestante > 100)
                ActionChip(
                  label: Text('S/ ${(saldoRestante / 2).toStringAsFixed(0)} (mitad)'),
                  onPressed: () => controller.text = (saldoRestante / 2).toStringAsFixed(2),
                ),
            ]),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton.icon(
            onPressed: () {
              final monto = double.tryParse(controller.text) ?? 0;
              if (monto <= 0) return;
              Navigator.pop(ctx);
              final nuevoTotal = montoPagado + monto;
              final nuevoEstado = nuevoTotal >= total
                  ? EstadoPagoHelper.PAGADO
                  : EstadoPagoHelper.PARCIAL;
              onCambiarEstadoPago(nuevoEstado, monto: monto, esNuevoPago: true);
            },
            icon: const Icon(Icons.check),
            label: const Text('Confirmar'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _fila(String label, double valor, Color color, {bool bold = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(color: color, fontSize: 13)),
        Text('S/ ${valor.toStringAsFixed(2)}',
            style: TextStyle(color: color, fontSize: 13,
                fontWeight: bold ? FontWeight.bold : FontWeight.w500)),
      ],
    );
  }

  // ── Picker de fuente de imagen ────────────────────────────────────────────

  void _mostrarPickerComprobante(BuildContext context, {String? paymentId}) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(20),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 40, height: 4,
            decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(height: 20),
          const Text('Agregar comprobante',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 20),
          Row(children: [
            Expanded(child: _pickerOption(ctx, Icons.camera_alt, 'Cámara',
                Colors.blue, ImageSource.camera, paymentId: paymentId)),
            const SizedBox(width: 16),
            Expanded(child: _pickerOption(ctx, Icons.photo_library, 'Galería',
                Colors.purple, ImageSource.gallery, paymentId: paymentId)),
          ]),
          const SizedBox(height: 16),
        ]),
      ),
    );
  }

  Widget _pickerOption(BuildContext ctx, IconData icon, String label,
      MaterialColor color, ImageSource source, {String? paymentId}) {
    return InkWell(
      onTap: () {
        Navigator.pop(ctx);
        onAgregarComprobante(source, paymentId: paymentId);
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        decoration: BoxDecoration(
          color: color.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.shade200),
        ),
        child: Column(children: [
          Icon(icon, size: 40, color: color.shade600),
          const SizedBox(height: 8),
          Text(label, style: TextStyle(fontWeight: FontWeight.w600, color: color.shade600)),
        ]),
      ),
    );
  }

  // ── Vista de imagen completa ──────────────────────────────────────────────

  void _verImagen(BuildContext context, String url) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Align(
              alignment: Alignment.topRight,
              child: IconButton(
                onPressed: () => Navigator.pop(ctx),
                icon: const Icon(Icons.close, color: Colors.white, size: 30),
              ),
            ),
            // Constrain height to avoid overflow on small screens
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.72,
                maxWidth: MediaQuery.of(context).size.width,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: InteractiveViewer(
                  child: Image.network(
                    url,
                    fit: BoxFit.contain,
                    loadingBuilder: (_, child, progress) => progress == null
                        ? child
                        : Container(
                            width: 300, height: 300,
                            color: Colors.grey.shade200,
                            child: const Center(child: CircularProgressIndicator())),
                    errorBuilder: (_, __, ___) => Container(
                        width: 300, height: 300,
                        color: Colors.grey.shade200,
                        child: const Icon(Icons.broken_image, size: 64, color: Colors.grey)),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Thumbnail de comprobante ──────────────────────────────────────────────

  Widget _thumbnail(BuildContext context, Map<String, dynamic> ev) {
    final url        = ev['url']?.toString() ?? '';
    final tipo       = ev['tipo']?.toString() ?? 'APP';
    final fecha      = ev['fecha']?.toString() ?? '';
    final verificado = (ev['verificacion'] as Map<String, dynamic>?)?['estado'] == 'VERIFICADO';
    final canDelete  = onEliminarEvidencia != null && !verificado;
    String fechaStr = '';
    try {
      final dt = DateTime.parse(fecha);
      fechaStr = '${dt.day}/${dt.month}';
    } catch (_) {}

    return GestureDetector(
      onTap: () => _verImagen(context, url),
      onLongPress: canDelete ? () => _confirmarEliminarEvidencia(context, ev) : null,
      child: Container(
        width: 80, height: 80,
        margin: const EdgeInsets.only(right: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: verificado
                ? Colors.green.shade400
                : (tipo == 'WHATSAPP' ? Colors.green.shade300 : Colors.blue.shade300),
            width: 2,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Stack(fit: StackFit.expand, children: [
            Image.network(url, fit: BoxFit.cover,
                loadingBuilder: (_, child, p) => p == null
                    ? child
                    : Container(color: Colors.grey.shade100,
                        child: const Center(child: SizedBox(width: 20, height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2)))),
                errorBuilder: (_, __, ___) => Container(color: Colors.grey.shade100,
                    child: const Icon(Icons.broken_image, color: Colors.grey))),

            // Capa VERIFICADO
            if (verificado)
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.75),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(Icons.verified, color: Colors.white, size: 22),
                    SizedBox(height: 2),
                    Text('BCP', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                  ]),
                ),
              ),

            // Badge tipo
            if (!verificado)
              Positioned(top: 3, right: 3,
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: tipo == 'WHATSAPP' ? Colors.green : Colors.blue,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(tipo == 'WHATSAPP' ? Icons.message : Icons.phone_android,
                      size: 10, color: Colors.white),
                ),
              ),

            // Fecha
            if (fechaStr.isNotEmpty)
              Positioned(bottom: 3, left: 3,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(3)),
                  child: Text(fechaStr, style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w600)),
                ),
              ),

            // Lupa / delete hint
            Positioned(bottom: 3, right: 3,
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(3)),
                child: const Icon(Icons.zoom_in, size: 12, color: Colors.white),
              ),
            ),

            // Botón eliminar (X roja) — solo si no está verificado
            if (canDelete)
              Positioned(top: 0, left: 0,
                child: GestureDetector(
                  onTap: () => _confirmarEliminarEvidencia(context, ev),
                  child: Container(
                    width: 22, height: 22,
                    decoration: BoxDecoration(
                      color: Colors.red.shade600,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(8),
                        bottomRight: Radius.circular(8),
                      ),
                    ),
                    child: const Icon(Icons.close, size: 14, color: Colors.white),
                  ),
                ),
              ),
          ]),
        ),
      ),
    );
  }

  void _confirmarEliminarEvidencia(BuildContext context, Map<String, dynamic> ev) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(children: [
          Icon(Icons.delete_outline, color: Colors.red.shade600),
          const SizedBox(width: 10),
          const Text('Eliminar comprobante', style: TextStyle(fontSize: 15)),
        ]),
        content: const Text('¿Eliminar esta imagen de comprobante? No se puede deshacer.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              onEliminarEvidencia!(ev);
            },
            icon: const Icon(Icons.delete_outline, size: 16),
            label: const Text('Eliminar'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade600,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ],
      ),
    );
  }

  // ── Confirmación eliminar pago ────────────────────────────────────────────

  void _confirmarEliminarPago(BuildContext context, String pagoId, int numero, double monto) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(children: [
          Icon(Icons.warning_amber_rounded, color: Colors.red.shade600),
          const SizedBox(width: 10),
          const Text('Eliminar pago', style: TextStyle(fontSize: 16)),
        ]),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('¿Eliminar el Pago $numero por S/ ${monto.toStringAsFixed(2)}?',
              style: const TextStyle(fontSize: 14)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.red.shade100),
            ),
            child: Row(children: [
              Icon(Icons.info_outline, size: 14, color: Colors.red.shade600),
              const SizedBox(width: 8),
              Expanded(child: Text('Los comprobantes asociados a este pago también se eliminarán.',
                  style: TextStyle(fontSize: 12, color: Colors.red.shade700))),
            ]),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              onEliminarPago!(pagoId);
            },
            icon: const Icon(Icons.delete_outline, size: 18),
            label: const Text('Eliminar'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade600,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ],
      ),
    );
  }

  // ── Card de un pago con sus comprobantes ──────────────────────────────────

  Widget _pagoCard(BuildContext context, Map<String, dynamic> pago, int index) {
    final pagoId = pago['id']?.toString();
    final monto = (pago['monto'] ?? 0).toDouble();
    final fechaStr = pago['fecha']?.toString() ?? '';
    final nota = pago['nota']?.toString() ?? '';

    String fechaFmt = '';
    try {
      // UTC ISO desde Supabase → Lima (UTC-5, sin DST)
      final lima = DateTime.parse(fechaStr).toUtc().subtract(const Duration(hours: 5));
      fechaFmt = DateFormat('dd/MM/yyyy HH:mm').format(lima);
    } catch (_) {
      fechaFmt = fechaStr;
    }

    // Evidencias linked to this payment
    final linked = evidencias
        .where((e) => e['paymentId']?.toString() == pagoId)
        .toList();

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.green.shade100),
        boxShadow: [BoxShadow(color: Colors.green.withValues(alpha: 0.06), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Header del pago
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
          child: Row(children: [
            Container(
              width: 30, height: 30,
              decoration: BoxDecoration(color: Colors.green.shade600, shape: BoxShape.circle),
              child: Center(child: Text('${index + 1}',
                  style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold))),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Pago ${index + 1}${nota.isNotEmpty ? ' · $nota' : ''}',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.grey.shade800)),
              if (fechaFmt.isNotEmpty)
                Text(fechaFmt, style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
            ])),
            Text('S/ ${monto.toStringAsFixed(2)}',
                style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green.shade700, fontSize: 15)),
            if (onEliminarPago != null && pagoId != null) ...[
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => _confirmarEliminarPago(context, pagoId, index + 1, monto),
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.shade100),
                  ),
                  child: Icon(Icons.delete_outline, size: 16, color: Colors.red.shade400),
                ),
              ),
            ],
          ]),
        ),

        // Comprobantes de este pago
        Divider(height: 1, color: Colors.green.shade50),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(Icons.receipt_long, size: 13, color: Colors.grey.shade500),
              const SizedBox(width: 5),
              Text('Comprobantes',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade600)),
              if (linked.isNotEmpty) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: Colors.green.shade100, borderRadius: BorderRadius.circular(8)),
                  child: Text('${linked.length}',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.green.shade700)),
                ),
              ],
            ]),
            const SizedBox(height: 8),

            // Upload in progress
            if (subiendoEvidencia && linked.isEmpty)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(8)),
                child: Row(children: [
                  const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                  const SizedBox(width: 10),
                  Text('Subiendo...', style: TextStyle(fontSize: 12, color: Colors.blue.shade700)),
                ]),
              )
            else
              Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                // Thumbnails
                if (linked.isNotEmpty)
                  ...linked.map((ev) => _thumbnail(context, ev)),

                // Botón agregar
                if (!subiendoEvidencia)
                  GestureDetector(
                    onTap: () => _mostrarPickerComprobante(context, paymentId: pagoId),
                    child: Container(
                      width: 64, height: 64,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.grey.shade300, width: 1.5),
                      ),
                      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Icon(Icons.add_photo_alternate_outlined, size: 22, color: Colors.grey.shade500),
                        const SizedBox(height: 3),
                        Text('Agregar', style: TextStyle(fontSize: 9, color: Colors.grey.shade500)),
                      ]),
                    ),
                  ),
              ]),
          ]),
        ),
      ]),
    );
  }

  // ── Build principal ───────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (estadoPago == EstadoPagoHelper.NO_APLICA) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.blueGrey.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.blueGrey.shade200),
        ),
        child: Row(children: [
          Icon(Icons.block, color: Colors.blueGrey.shade400, size: 28),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('NO APLICA', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: Colors.blueGrey.shade700)),
            Text('Cliente interno — consumo sin cobro', style: TextStyle(fontSize: 12, color: Colors.blueGrey.shade500)),
          ])),
        ]),
      );
    }

    final total = (pedido['total'] ?? 0).toDouble();
    final saldoRestante = total - montoPagado;
    final diasSinPago = EstadoPagoHelper.calcularDiasSinPago(pedido);
    final colorEstado = EstadoPagoHelper.getColorEstadoPago(estadoPago);

    // Evidencias sin paymentId (datos legacy / sheets)
    final pagoIds = pagos.map((p) => p['id']?.toString()).whereType<String>().toSet();
    final orphans = evidencias.where((e) {
      final pid = e['paymentId']?.toString();
      return pid == null || !pagoIds.contains(pid);
    }).toList();

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

      // ── Badge de estado ──────────────────────────────────────────────────
      Row(children: [
        Icon(Icons.payments, size: 20, color: colorEstado),
        const SizedBox(width: 8),
        const Text('Estado de Pago', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: colorEstado.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: colorEstado.withValues(alpha: 0.3)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(EstadoPagoHelper.getIconoEstadoPago(estadoPago), size: 16, color: colorEstado),
            const SizedBox(width: 6),
            Text(
              estadoPago == EstadoPagoHelper.PAGADO ? 'PAGADO'
                  : estadoPago == EstadoPagoHelper.PARCIAL ? 'PARCIAL'
                  : 'PENDIENTE',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: colorEstado),
            ),
          ]),
        ),
      ]),
      const SizedBox(height: 12),

      // ── Alerta días sin pago ─────────────────────────────────────────────
      if (estadoPago != EstadoPagoHelper.PAGADO && diasSinPago > 0)
        Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: EstadoPagoHelper.getColorAlerta(diasSinPago).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: EstadoPagoHelper.getColorAlerta(diasSinPago).withValues(alpha: 0.3)),
          ),
          child: Row(children: [
            Icon(Icons.access_time, color: EstadoPagoHelper.getColorAlerta(diasSinPago)),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${EstadoPagoHelper.getTextoAlerta(diasSinPago)} sin pago',
                  style: TextStyle(fontWeight: FontWeight.w600,
                      color: EstadoPagoHelper.getColorAlerta(diasSinPago))),
              Text('Pendiente: S/ ${saldoRestante.toStringAsFixed(2)}',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
            ])),
          ]),
        ),

      // ── Resumen de montos ────────────────────────────────────────────────
      if (estadoPago == EstadoPagoHelper.PARCIAL || estadoPago == EstadoPagoHelper.PAGADO)
        Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Column(children: [
            _fila('Total', total, Colors.grey.shade700),
            const SizedBox(height: 4),
            _fila('Pagado', montoPagado, Colors.green.shade600),
            if (estadoPago == EstadoPagoHelper.PARCIAL) ...[
              const Divider(height: 12),
              _fila('Pendiente', saldoRestante, Colors.red.shade600, bold: true),
            ],
          ]),
        ),

      // ── Historial de pagos con comprobantes enlazados ────────────────────
      if (pagos.isNotEmpty) ...[
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(children: [
            Icon(Icons.history, size: 16, color: Colors.grey.shade600),
            const SizedBox(width: 6),
            Text('Historial de pagos',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
          ]),
        ),
        ...pagos.asMap().entries.map((e) => _pagoCard(context, e.value, e.key)),
      ],

      // ── Comprobantes sin pago asociado (solo cuando hay pagos registrados) ──
      if (pagos.isNotEmpty && orphans.isNotEmpty) ...[
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(children: [
            Icon(Icons.receipt_long, size: 16, color: Colors.grey.shade500),
            const SizedBox(width: 6),
            Text('Comprobantes sin pago asociado',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.grey.shade600)),
          ]),
        ),
        SizedBox(
          height: 84,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: orphans.length,
            itemBuilder: (_, i) => _thumbnail(context, orphans[i]),
          ),
        ),
        const SizedBox(height: 8),
      ],


      // ── Botón registrar pago / confirmación pagado ───────────────────────
      if (estadoPago != EstadoPagoHelper.PAGADO)
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: actualizando ? null : () => _mostrarDialogoRegistrarPago(context),
            icon: actualizando
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.payments),
            label: Text(estadoPago == EstadoPagoHelper.PARCIAL ? 'Registrar Abono' : 'Registrar Pago'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green.shade600,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),

      if (estadoPago == EstadoPagoHelper.PAGADO)
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.green.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.green.shade200),
          ),
          child: Row(children: [
            Icon(Icons.check_circle, color: Colors.green.shade600, size: 32),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Pago Completado',
                  style: TextStyle(fontWeight: FontWeight.w600, color: Colors.green.shade700)),
              Text('S/ ${total.toStringAsFixed(2)}${pagos.length > 1 ? ' · ${pagos.length} abonos' : ''}',
                  style: TextStyle(fontSize: 12, color: Colors.green.shade600)),
            ])),
            TextButton(
              onPressed: () => onCambiarEstadoPago(EstadoPagoHelper.PENDIENTE_PAGO, monto: 0, esNuevoPago: false),
              child: const Text('Revertir todos los pagos', style: TextStyle(fontSize: 12)),
            ),
          ]),
        ),
    ]);
  }
}
