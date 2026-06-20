import 'dart:convert';
import 'package:flutter/material.dart';

/// Widget que muestra la información básica del pedido
/// (ID, última actualización, teléfono, observaciones, historial colapsable)
class InfoBasicaWidget extends StatefulWidget {
  final Map<String, dynamic> pedido;

  const InfoBasicaWidget({super.key, required this.pedido});

  @override
  State<InfoBasicaWidget> createState() => _InfoBasicaWidgetState();
}

class _InfoBasicaWidgetState extends State<InfoBasicaWidget> {
  bool _historialVisible = false;

  static const Map<String, _EstadoMeta> _estadoMeta = {
    'CREADO':         _EstadoMeta(Icons.add_circle_outline,       Color(0xFF607D8B), 'Creado'),
    'CONFIRMADO':     _EstadoMeta(Icons.check_circle_outline,     Color(0xFF2196F3), 'Confirmado'),
    'EN_PREPARACION': _EstadoMeta(Icons.construction,             Color(0xFFFF9800), 'En preparación'),
    'LISTO':          _EstadoMeta(Icons.inventory_2_outlined,     Color(0xFF9C27B0), 'Listo'),
    'ENVIADO':        _EstadoMeta(Icons.local_shipping_outlined,  Color(0xFF00BCD4), 'Enviado'),
    'ENTREGADO':      _EstadoMeta(Icons.done_all,                 Color(0xFF4CAF50), 'Entregado'),
    'COMPLETADO':     _EstadoMeta(Icons.task_alt,                 Color(0xFF4CAF50), 'Completado'),
    'CANCELADO':      _EstadoMeta(Icons.cancel_outlined,          Color(0xFFF44336), 'Cancelado'),
  };

  Map<String, dynamic>? _parseTracking() {
    final raw = widget.pedido['tracking'];
    if (raw == null) return null;
    if (raw is Map<String, dynamic>) return raw;
    if (raw is String && raw.isNotEmpty) {
      try { return jsonDecode(raw) as Map<String, dynamic>; } catch (_) {}
    }
    return null;
  }

  String _fmtIso(String raw) {
    if (raw.isEmpty) return raw;
    try {
      // Timestamps vienen en UTC desde Supabase; Perú = UTC-5, sin DST
      final dt = DateTime.parse(raw).toUtc().subtract(const Duration(hours: 5));
      final h  = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
      final ap = dt.hour < 12 ? 'a. m.' : 'p. m.';
      final m  = dt.minute.toString().padLeft(2, '0');
      return '${dt.day}/${dt.month}/${dt.year}, $h:$m $ap';
    } catch (_) {
      return raw;
    }
  }

  /// Builds the full estados list from tracking.estados (old format)
  /// or from individual timestamp fields (new Supabase format).
  List<Map<String, dynamic>> _buildEstados() {
    final tracking = _parseTracking();

    // Old format: tracking has an 'estados' array
    final fromArray = tracking != null
        ? List<Map<String, dynamic>>.from(tracking['estados'] ?? [])
        : <Map<String, dynamic>>[];

    if (fromArray.isNotEmpty) {
      final tieneCreadoEnTracking = fromArray.any(
        (e) => (e['estado'] ?? '').toString().toUpperCase() == 'CREADO',
      );
      if (!tieneCreadoEnTracking) {
        final fecha = widget.pedido['fecha']?.toString() ?? '';
        final hora  = widget.pedido['hora']?.toString() ?? '';
        final fechaCreacion = tracking?['creadoEn']?.toString() ??
            '$fecha${hora.isNotEmpty ? ', $hora' : ''}';
        fromArray.insert(0, {'estado': 'CREADO', 'fecha': fechaCreacion});
      }
      return fromArray;
    }

    // New format: build timeline from individual timestamp fields
    final entries = <Map<String, dynamic>>[];

    void add(String estado, String? raw) {
      if (raw != null && raw.isNotEmpty) {
        entries.add({'estado': estado, 'fecha': _fmtIso(raw)});
      }
    }

    final creadoEn = tracking?['creadoEn']?.toString() ?? '';
    final fechaFallback = () {
      final f = widget.pedido['fecha']?.toString() ?? '';
      final h = widget.pedido['hora']?.toString() ?? '';
      return '$f${h.isNotEmpty ? ', $h' : ''}';
    }();
    add('CREADO',          creadoEn.isNotEmpty ? creadoEn : fechaFallback);
    add('CONFIRMADO',      tracking?['confirmedAt']?.toString());
    add('EN_PREPARACION',  tracking?['preparingAt']?.toString());
    add('LISTO',           tracking?['readyAt']?.toString());
    add('ENVIADO',         tracking?['shippedAt']?.toString());
    add('COMPLETADO',      tracking?['deliveredAt']?.toString());

    return entries;
  }

  @override
  Widget build(BuildContext context) {
    final pedidoId           = widget.pedido['id'] ?? '';
    final whatsapp           = widget.pedido['whatsapp'] ?? '';
    final observaciones      = widget.pedido['observaciones'] ?? '';
    final fechaActualizacion = widget.pedido['fechaActualizacion']?.toString() ?? '';
    final estados            = _buildEstados();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildInfoRow(Icons.receipt_long, 'Pedido', pedidoId),
        if (fechaActualizacion.isNotEmpty)
          _buildInfoRow(Icons.update, 'Última actualización', fechaActualizacion),
        if (whatsapp.isNotEmpty && whatsapp != '000000000')
          _buildInfoRow(Icons.phone, 'WhatsApp', whatsapp),
        if (observaciones.isNotEmpty)
          _buildInfoRow(Icons.notes, 'Observaciones', observaciones),

        // ── Historial colapsable ─────────────────────────────────
        if (estados.isNotEmpty) ...[
          const SizedBox(height: 8),
          GestureDetector(
            onTap: () => setState(() => _historialVisible = !_historialVisible),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.timeline, size: 15, color: Colors.grey.shade600),
                  const SizedBox(width: 6),
                  Text(
                    'Historial de estados',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade700,
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    _historialVisible ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                    size: 18,
                    color: Colors.grey.shade500,
                  ),
                ],
              ),
            ),
          ),
          if (_historialVisible) ...[
            const SizedBox(height: 12),
            _buildTimeline(estados),
          ],
        ],
      ],
    );
  }

  Widget _buildTimeline(List<Map<String, dynamic>> estados) {
    return Column(
      children: List.generate(estados.length, (i) {
        final e      = estados[i];
        final key    = (e['estado'] ?? '').toString().toUpperCase();
        final fecha  = e['fecha']?.toString() ?? '';
        final meta   = _estadoMeta[key] ?? const _EstadoMeta(Icons.circle, Color(0xFF9E9E9E), '');
        final label  = meta.label.isNotEmpty ? meta.label : key;
        final isLast = i == estados.length - 1;

        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 28,
                child: Column(
                  children: [
                    Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: meta.color.withOpacity(0.12),
                        shape: BoxShape.circle,
                        border: Border.all(color: meta.color, width: 1.5),
                      ),
                      child: Icon(meta.icon, size: 12, color: meta.color),
                    ),
                    if (!isLast)
                      Expanded(
                        child: Container(
                          width: 1.5,
                          color: Colors.grey.shade200,
                          margin: const EdgeInsets.symmetric(vertical: 2),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(bottom: isLast ? 0 : 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: meta.color)),
                      if (fecha.isNotEmpty)
                        Text(fecha, style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      }),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: Colors.grey.shade600),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                const SizedBox(height: 2),
                Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EstadoMeta {
  final IconData icon;
  final Color color;
  final String label;
  const _EstadoMeta(this.icon, this.color, this.label);
}
