import 'package:flutter/material.dart';
import '../helpers/producto_parser.dart';

/// Card para mostrar una solicitud B2B enviada por este negocio a un proveedor
class SolicitudEnviadaCard extends StatelessWidget {
  final Map<String, dynamic> pedido;
  final VoidCallback onTap;

  const SolicitudEnviadaCard({
    super.key,
    required this.pedido,
    required this.onTap,
  });

  Color _getEstadoColor(String estado) {
    switch (estado) {
      case 'PENDIENTE':
        return Colors.orange;
      case 'CONFIRMADO':
        return Colors.blue;
      case 'COMPLETADO':
        return Colors.green;
      case 'ENTREGADO':
        return Colors.teal;
      case 'CANCELADO':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  IconData _getEstadoIcon(String estado) {
    switch (estado) {
      case 'PENDIENTE':
        return Icons.hourglass_top_rounded;
      case 'CONFIRMADO':
        return Icons.thumb_up_rounded;
      case 'COMPLETADO':
        return Icons.check_circle_rounded;
      case 'ENTREGADO':
        return Icons.local_shipping_rounded;
      case 'CANCELADO':
        return Icons.cancel_rounded;
      default:
        return Icons.help_outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    final estado =
        (pedido['estado'] ?? 'PENDIENTE').toString().toUpperCase();
    final total = (pedido['total'] ?? 0).toDouble();
    final fecha = pedido['fecha'] ?? '';
    final proveedorNombre =
        (pedido['_proveedorNombre'] ?? pedido['_proveedorId'] ?? 'Proveedor')
            .toString();
    final observaciones = (pedido['observaciones'] ?? '').toString();
    final productos = parseProductos(pedido['productos']);

    final estadoColor = _getEstadoColor(estado);

    // Build product summary string
    String productosSummary = '';
    if (productos.isNotEmpty) {
      productosSummary = productos
          .map((p) {
            final nombre = p['nombre'] ?? 'Producto';
            final cant = p['cantidad'] ?? 1;
            return '$cant× $nombre';
          })
          .take(3)
          .join(', ');
      if (productos.length > 3) productosSummary += '…';
    }

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: estadoColor.withOpacity(0.3)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Status icon
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: estadoColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(21),
                ),
                child: Icon(
                  _getEstadoIcon(estado),
                  color: estadoColor,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),

              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header row: provider name + total
                    Row(
                      children: [
                        Expanded(
                          child: Row(
                            children: [
                              Icon(Icons.send_rounded,
                                  size: 13,
                                  color: Colors.deepPurple.shade400),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  proveedorNombre,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          'S/${total.toStringAsFixed(2)}',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: estadoColor,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),

                    // Products summary
                    if (productosSummary.isNotEmpty)
                      Text(
                        productosSummary,
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade700,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),

                    // Observations
                    if (observaciones.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        observaciones,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade500,
                          fontStyle: FontStyle.italic,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],

                    const SizedBox(height: 6),

                    // Footer: status badge + date
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: estadoColor,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            estado,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.deepPurple.shade50,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.storefront,
                                  size: 11,
                                  color: Colors.deepPurple.shade600),
                              const SizedBox(width: 3),
                              Text(
                                'B2B',
                                style: TextStyle(
                                  color: Colors.deepPurple.shade600,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Spacer(),
                        if (fecha.isNotEmpty)
                          Text(
                            fecha.length > 10 ? fecha.substring(0, 10) : fecha,
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade500,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),

              // Arrow
              const SizedBox(width: 8),
              Icon(Icons.chevron_right_rounded,
                  color: Colors.grey.shade400, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
