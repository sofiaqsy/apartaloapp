import 'package:flutter/material.dart';
import '../../../../theme/fincas_tokens.dart';
import '../../../../widgets/fincas_widgets.dart';
import '../helpers/estado_pago_helper.dart';
import '../helpers/producto_parser.dart';

/// Card para mostrar un pedido en la lista.
/// Compacta: el cliente y el total son lo principal; fecha y cantidad van en una sola línea;
/// el estado y las etiquetas son badges de texto (el color nunca es el único indicador).
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

  static FincasTone estadoTone(String? estado) {
    switch (estado?.toUpperCase()) {
      case 'PENDIENTE':
        return FincasTone.warning;
      case 'COMPLETADO':
      case 'ENTREGADO':
        return FincasTone.success;
      case 'CANCELADO':
        return FincasTone.error;
      default:
        return FincasTone.neutral; // CONFIRMADO y otros
    }
  }

  static FincasTone _pagoTone(String estadoPago) {
    switch (estadoPago) {
      case EstadoPagoHelper.PAGADO:
        return FincasTone.success;
      case EstadoPagoHelper.PARCIAL:
        return FincasTone.warning;
      case EstadoPagoHelper.PENDIENTE_PAGO:
        return FincasTone.error;
      default:
        return FincasTone.neutral;
    }
  }

  static String _pagoTexto(String estadoPago, bool conDias, int dias) {
    switch (estadoPago) {
      case EstadoPagoHelper.PAGADO:
        return 'Pagado';
      case EstadoPagoHelper.PARCIAL:
        return conDias ? 'Parcial · ${EstadoPagoHelper.getTextoAlerta(dias)}' : 'Parcial';
      case EstadoPagoHelper.PENDIENTE_PAGO:
        return conDias ? 'Por cobrar · ${EstadoPagoHelper.getTextoAlerta(dias)}' : 'Por cobrar';
      default:
        return 'Sin pago';
    }
  }

  @override
  Widget build(BuildContext context) {
    final cliente = (pedido['cliente'] ?? 'Sin nombre').toString();
    final total = (pedido['total'] ?? 0).toDouble();
    final estado = (pedido['estado'] ?? 'PENDIENTE').toString().toUpperCase();
    final fecha = (pedido['fecha'] ?? '').toString();
    final origen = (pedido['origen'] ?? '').toString().toUpperCase();
    final productos = parseProductos(pedido['productos']);

    final tipo = (pedido['tipo'] ?? '').toString().toUpperCase();
    final esB2B = tipo == 'B2B';
    final esPreventa = tipo == 'PREVENTA';
    final estadoPago = EstadoPagoHelper.determinarEstadoPago(pedido);
    final diasSinPago = EstadoPagoHelper.calcularDiasSinPago(pedido);
    final esCompletado = estado == 'COMPLETADO';
    final mostrarPago = mostrarAlertaPago && esCompletado;
    final mostrarAlerta = mostrarPago && estadoPago != EstadoPagoHelper.PAGADO;

    // Todos los vouchers verificados por BCP
    final evidencias = (pedido['evidencias'] as List<dynamic>?) ?? [];
    final todosVerificados = evidencias.isNotEmpty &&
        evidencias.every((e) => (e as Map<String, dynamic>)['verificacion']?['estado'] == 'VERIFICADO');

    int totalUnidades = 0;
    for (var p in productos) {
      totalUnidades += (p['cantidad'] as num?)?.toInt() ?? 1;
    }
    final detalle = productos.isEmpty ? 'Sin detalle' : '${productos.length} prod. · $totalUnidades uds';
    final meta = [if (fecha.isNotEmpty) fecha, detalle].join(' · ');

    final radius = BorderRadius.circular(FincasRadii.large);
    final borde = mostrarAlerta ? EstadoPagoHelper.getColorAlerta(diasSinPago) : FincasColors.border;

    final largeText = MediaQuery.textScalerOf(context).scale(16) / 16 > 1.3;

    // Inicial del cliente sobre arena: neutro, el estado va en el badge.
    final avatar = Container(
      width: 40,
      height: 40,
      decoration: const BoxDecoration(color: FincasColors.sand, shape: BoxShape.circle),
      alignment: Alignment.center,
      child: Text(
        cliente.isNotEmpty ? cliente[0].toUpperCase() : '?',
        style: FincasText.sectionTitle.copyWith(color: FincasColors.espresso),
      ),
    );

    final detalles = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(cliente, maxLines: largeText ? 2 : 1, overflow: TextOverflow.ellipsis, style: FincasText.sectionTitle.copyWith(fontSize: 16)),
        const SizedBox(height: 2),
        Text(meta, maxLines: 2, overflow: TextOverflow.ellipsis, style: FincasText.metadata),
        const SizedBox(height: FincasSpacing.s),
        Wrap(
          spacing: FincasSpacing.xs + 2,
          runSpacing: FincasSpacing.xs,
          children: [
            FincasStatusBadge(estado[0] + estado.substring(1).toLowerCase(), tone: estadoTone(estado)),
            if (esPreventa) const FincasStatusBadge('Pre-venta', tone: FincasTone.warning),
            if (esB2B) const FincasStatusBadge('B2B'),
            if (origen == 'TIENDA') const FincasStatusBadge('Tienda'),
          ],
        ),
      ],
    );

    Widget derecha(CrossAxisAlignment align) => Column(
          crossAxisAlignment: align,
          children: [
            Text('S/ ${total.toStringAsFixed(2)}', style: FincasText.sectionTitle.copyWith(fontSize: 16, fontWeight: FontWeight.w700)),
            if (mostrarPago) ...[
              const SizedBox(height: FincasSpacing.xs + 2),
              FincasStatusBadge(_pagoTexto(estadoPago, mostrarAlerta, diasSinPago), tone: _pagoTone(estadoPago)),
            ],
            if (todosVerificados) ...[
              const SizedBox(height: FincasSpacing.xs + 2),
              const Icon(Icons.verified, size: 16, color: FincasColors.success, semanticLabel: 'Voucher verificado'),
            ],
          ],
        );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: FincasSpacing.l, vertical: FincasSpacing.xs + 1),
      child: Semantics(
        button: true,
        label: 'Pedido de $cliente, ${estado.toLowerCase()}, S/ ${total.toStringAsFixed(2)}',
        excludeSemantics: true,
        child: Material(
          color: FincasColors.surface,
          shape: RoundedRectangleBorder(borderRadius: radius, side: BorderSide(color: borde, width: mostrarAlerta ? 1.5 : 1)),
          child: InkWell(
            onTap: onTap,
            borderRadius: radius,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: FincasSpacing.m + 2, vertical: FincasSpacing.m),
              child: largeText
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [avatar, const SizedBox(width: FincasSpacing.m), Expanded(child: detalles)]),
                        const SizedBox(height: FincasSpacing.s),
                        // Con texto grande el importe pasa debajo, para que el nombre conserve su ancho.
                        Align(alignment: Alignment.centerRight, child: derecha(CrossAxisAlignment.end)),
                      ],
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        avatar,
                        const SizedBox(width: FincasSpacing.m),
                        Expanded(child: detalles),
                        const SizedBox(width: FincasSpacing.s),
                        derecha(CrossAxisAlignment.end),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
