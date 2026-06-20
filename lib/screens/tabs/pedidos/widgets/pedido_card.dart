import 'package:flutter/material.dart';
import '../helpers/estado_pago_helper.dart';
import '../helpers/producto_parser.dart';

/// Card para mostrar un pedido en la lista
class PedidoCard extends StatelessWidget {
  final Map<String, dynamic> pedido;
  final VoidCallback onTap;
  final bool mostrarAlertaPago;

  const PedidoCard({
    super.key,
    required this.pedido,
    required this.onTap,
    this.mostrarAlertaPago = false,
  });

  Color _getEstadoColor(String? estado) {
    switch (estado?.toUpperCase()) {
      case 'PENDIENTE': return Colors.orange;
      case 'CONFIRMADO': return Colors.blue;
      case 'COMPLETADO': return Colors.green;
      case 'ENTREGADO': return Colors.teal;
      case 'CANCELADO': return Colors.red;
      default: return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cliente = pedido['cliente'] ?? 'Sin nombre';
    final total = (pedido['total'] ?? 0).toDouble();
    final estado = (pedido['estado'] ?? 'PENDIENTE').toString().toUpperCase();
    final fecha = pedido['fecha'] ?? '';
    final origen = (pedido['origen'] ?? '').toString().toUpperCase();
    final productos = parseProductos(pedido['productos']);
    
    // Estado de pago
    final esTipo     = (pedido['tipo'] ?? '').toString().toUpperCase();
    final esB2B      = esTipo == 'B2B';
    final esPreventa = esTipo == 'PREVENTA';
    final estadoPago = EstadoPagoHelper.determinarEstadoPago(pedido);
    final diasSinPago = EstadoPagoHelper.calcularDiasSinPago(pedido);
    final mostrarAlerta = mostrarAlertaPago &&
                          estado == 'COMPLETADO' &&
                          estadoPago != EstadoPagoHelper.PAGADO;

    // Todos los vouchers verificados por BCP
    final evidencias = (pedido['evidencias'] as List<dynamic>?) ?? [];
    final todosVerificados = evidencias.isNotEmpty &&
        evidencias.every((e) =>
            (e as Map<String, dynamic>)['verificacion']?['estado'] == 'VERIFICADO');
    
    int totalUnidades = 0;
    for (var p in productos) {
      totalUnidades += (p['cantidad'] as num?)?.toInt() ?? 1;
    }

    final estadoColor = _getEstadoColor(estado);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        elevation: 1,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            decoration: mostrarAlerta ? BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: EstadoPagoHelper.getColorAlerta(diasSinPago).withOpacity(0.5),
                width: 2,
              ),
            ) : null,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Stack(
                    children: [
                      Container(
                        width: 56, height: 56,
                        decoration: BoxDecoration(color: estadoColor.withOpacity(0.1), borderRadius: BorderRadius.circular(28)),
                        child: Center(child: Text(cliente.isNotEmpty ? cliente[0].toUpperCase() : '?', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: estadoColor))),
                      ),
                      Positioned(right: 0, bottom: 0, child: Container(width: 16, height: 16, decoration: BoxDecoration(color: estadoColor, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)))),
                    ],
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(child: Text(cliente, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis)),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(color: estadoColor.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
                              child: Text(estado, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: estadoColor)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(children: [Icon(Icons.access_time, size: 14, color: Colors.grey.shade500), const SizedBox(width: 4), Text(fecha, style: TextStyle(fontSize: 13, color: Colors.grey.shade600))]),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(Icons.shopping_bag_outlined, size: 14, color: Colors.grey.shade500),
                            const SizedBox(width: 4),
                            Flexible(child: Text(productos.isEmpty ? 'Sin detalle' : '${productos.length} prod. • $totalUnidades uds', style: TextStyle(fontSize: 13, color: Colors.grey.shade600), overflow: TextOverflow.ellipsis)),
                            if (esPreventa) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                decoration: BoxDecoration(color: const Color(0xFFFFF3E0), borderRadius: BorderRadius.circular(6)),
                                child: Row(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.coffee_rounded, size: 10, color: Color(0xFFE65100)), const SizedBox(width: 2), const Text('PRE-VENTA', style: TextStyle(fontSize: 9, color: Color(0xFFE65100), fontWeight: FontWeight.w700))]),
                              ),
                            ],
                            if (esB2B) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                decoration: BoxDecoration(color: Colors.deepPurple.shade50, borderRadius: BorderRadius.circular(6)),
                                child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.storefront, size: 10, color: Colors.deepPurple.shade600), const SizedBox(width: 2), Text('B2B', style: TextStyle(fontSize: 9, color: Colors.deepPurple.shade600, fontWeight: FontWeight.w600))]),
                              ),
                            ],
                            if (origen == 'TIENDA') ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                decoration: BoxDecoration(color: Colors.purple.shade50, borderRadius: BorderRadius.circular(6)),
                                child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.store, size: 10, color: Colors.purple.shade600), const SizedBox(width: 2), Text('Tienda', style: TextStyle(fontSize: 9, color: Colors.purple.shade600, fontWeight: FontWeight.w600))]),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('S/ ${total.toStringAsFixed(2)}', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.green.shade600)),
                      const SizedBox(height: 4),
                      // Badge de estado de pago
                      if (mostrarAlertaPago && estado == 'COMPLETADO')
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: EstadoPagoHelper.getColorEstadoPago(estadoPago).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                EstadoPagoHelper.getIconoEstadoPago(estadoPago),
                                size: 12,
                                color: EstadoPagoHelper.getColorEstadoPago(estadoPago),
                              ),
                              if (mostrarAlerta) ...[
                                const SizedBox(width: 4),
                                Text(
                                  EstadoPagoHelper.getTextoAlerta(diasSinPago),
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: EstadoPagoHelper.getColorAlerta(diasSinPago),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        )
                      else
                        Icon(Icons.chevron_right, color: Colors.grey.shade400),
                      // Check verde: todos los vouchers verificados
                      if (todosVerificados) ...[
                        const SizedBox(height: 4),
                        Icon(Icons.verified, size: 16, color: Colors.green.shade600),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
