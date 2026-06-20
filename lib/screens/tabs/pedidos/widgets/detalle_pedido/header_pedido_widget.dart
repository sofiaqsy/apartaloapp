import 'package:flutter/material.dart';
import '../../helpers/estado_pago_helper.dart';

/// Widget que muestra el header del pedido con avatar, nombre, estado y origen
class HeaderPedidoWidget extends StatelessWidget {
  final Map<String, dynamic> pedido;
  final String estadoPago;
  final VoidCallback onClose;
  final VoidCallback? onMenuTap;
  final VoidCallback? onPdfTap;

  const HeaderPedidoWidget({
    super.key,
    required this.pedido,
    required this.estadoPago,
    required this.onClose,
    this.onMenuTap,
    this.onPdfTap,
  });

  Color _getEstadoColor(String? estado) {
    switch (estado?.toUpperCase()) {
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

  @override
  Widget build(BuildContext context) {
    final cliente = pedido['cliente'] ?? 'Sin nombre';
    final estado = (pedido['estado'] ?? 'PENDIENTE').toString().toUpperCase();
    final origen = (pedido['origen'] ?? '').toString().toUpperCase();
    final esTipo     = (pedido['tipo'] ?? '').toString().toUpperCase();
    final esB2B      = esTipo == 'B2B';
    final esPreventa = esTipo == 'PREVENTA';
    final negocioSolicitante = pedido['negocioSolicitante'] ?? '';
    final estadoColor = _getEstadoColor(estado);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: estadoColor.withOpacity(0.05),
      ),
      child: Row(
        children: [
          // Avatar del cliente
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: estadoColor.withOpacity(0.15),
              borderRadius: BorderRadius.circular(28),
            ),
            child: Center(
              child: Text(
                cliente.isNotEmpty ? cliente[0].toUpperCase() : '?',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: estadoColor,
                ),
              ),
            ),
          ),
          
          const SizedBox(width: 16),
          
          // Información del cliente y badges
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  cliente,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    // Badge de estado del pedido
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: estadoColor,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        estado,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    
                    // Badge PRE-VENTA
                    if (esPreventa)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF3E0),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFE65100), width: 1),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.coffee_rounded, size: 12, color: Color(0xFFE65100)),
                            SizedBox(width: 4),
                            Text('PRE-VENTA', style: TextStyle(color: Color(0xFFE65100), fontSize: 12, fontWeight: FontWeight.w700)),
                          ],
                        ),
                      ),

                    // Badge B2B
                    if (esB2B)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.deepPurple.shade100,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.storefront, size: 12, color: Colors.deepPurple.shade700),
                            const SizedBox(width: 4),
                            Text('B2B', style: TextStyle(color: Colors.deepPurple.shade700, fontSize: 12, fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),

                    // Badge de origen (Tienda)
                    if (origen == 'TIENDA')
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.purple.shade100,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.store,
                              size: 12,
                              color: Colors.purple.shade700,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Tienda',
                              style: TextStyle(
                                color: Colors.purple.shade700,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),

                    // Badge de estado de pago (solo para completados)
                    if (estado == 'COMPLETADO')
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: EstadoPagoHelper.getColorEstadoPago(estadoPago).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          EstadoPagoHelper.getIconoEstadoPago(estadoPago),
                          size: 14,
                          color: EstadoPagoHelper.getColorEstadoPago(estadoPago),
                        ),
                      ),
                  ],
                ),
                // B2B requester info — inside Column children
                if (esB2B && negocioSolicitante.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(Icons.business, size: 13, color: Colors.deepPurple.shade400),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          'Solicitado por: $negocioSolicitante',
                          style: TextStyle(fontSize: 12, color: Colors.deepPurple.shade600, fontWeight: FontWeight.w500),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),

          // Botones de acción
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Botón PDF
              if (onPdfTap != null)
                IconButton(
                  onPressed: onPdfTap,
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  tooltip: 'Descargar PDF',
                  color: const Color(0xFF5C3317),
                ),
              // Botón de menú de opciones
              if (onMenuTap != null)
                IconButton(
                  onPressed: onMenuTap,
                  icon: const Icon(Icons.more_vert),
                  tooltip: 'Opciones',
                ),
              // Botón de cerrar
              IconButton(
                onPressed: onClose,
                icon: const Icon(Icons.close),
                tooltip: 'Cerrar',
              ),
            ],
          ),
        ],
      ),
    );
  }
}
