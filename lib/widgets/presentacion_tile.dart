import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../theme/fincas_tokens.dart';
import 'fincas_widgets.dart';

/// Una presentación del producto: contenido, precios, molienda y stock, con sus acciones.
/// El estado (predeterminada, oculta en tienda) se dice con texto, no solo con color.
class PresentacionTile extends StatelessWidget {
  const PresentacionTile({
    super.key,
    required this.presentacion,
    required this.onEditar,
    required this.onEliminar,
    this.simboloMoneda = 'S/',
    this.stockManual = false,
  });

  final Presentacion presentacion;
  final VoidCallback onEditar;
  final VoidCallback onEliminar;
  final String simboloMoneda;
  final bool stockManual;

  static const _molienda = {'ground': 'Molido', 'whole': 'Grano', 'green': 'Verde'};

  @override
  Widget build(BuildContext context) {
    final p = presentacion;
    final molienda = p.molienda.map((m) => _molienda[m] ?? m).join(', ');
    final imagen = p.imageUrl;
    final detalles = <String>[
      if (p.precioB2b != null) 'B2B $simboloMoneda ${p.precioB2b!.toStringAsFixed(2)}',
      if (p.pedidoMinimo > 1) 'Pedido mínimo ${p.pedidoMinimo}',
      if (molienda.isNotEmpty) molienda,
    ];

    final largeText = MediaQuery.textScalerOf(context).scale(16) / 16 > 1.3;
    final stock = Text(
      stockManual ? 'Stock manual: ${p.stock}' : 'Stock: ${p.stock}',
      style: FincasText.metadata.copyWith(fontWeight: FontWeight.w600),
    );
    final acciones = <Widget>[
      TextButton(onPressed: onEditar, child: const Text('Editar')),
      TextButton(
        onPressed: onEliminar,
        style: TextButton.styleFrom(foregroundColor: FincasColors.error),
        child: const Text('Eliminar'),
      ),
    ];

    return Container(
      margin: const EdgeInsets.only(bottom: FincasSpacing.s),
      decoration: BoxDecoration(
        color: FincasColors.surface,
        borderRadius: BorderRadius.circular(FincasRadii.large),
        border: Border.all(color: FincasColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(FincasSpacing.l, FincasSpacing.m, FincasSpacing.l, FincasSpacing.s),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (imagen != null && imagen.isNotEmpty) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(FincasRadii.small),
                    child: Image.network(imagen, width: 48, height: 48, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox(width: 48, height: 48)),
                  ),
                  const SizedBox(width: FincasSpacing.m),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: FincasSpacing.s,
                        runSpacing: FincasSpacing.xs,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(p.etiqueta, style: FincasText.sectionTitle),
                          if (p.predeterminada) const FincasStatusBadge('Predeterminada', tone: FincasTone.success),
                          if (!p.visible) const FincasStatusBadge('Oculta en tienda', tone: FincasTone.warning),
                        ],
                      ),
                      const SizedBox(height: FincasSpacing.xs),
                      Text('$simboloMoneda ${p.precio.toStringAsFixed(2)}',
                          style: FincasText.body.copyWith(fontWeight: FontWeight.w700)),
                      if (detalles.isNotEmpty) Text(detalles.join(' · '), style: FincasText.metadata),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: FincasSpacing.s),
            child: largeText
                // Con texto grande el stock y los botones van en dos filas para que nada se corte.
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(padding: const EdgeInsets.fromLTRB(FincasSpacing.s, FincasSpacing.s, 0, 0), child: stock),
                      Wrap(alignment: WrapAlignment.end, children: acciones),
                    ],
                  )
                : Row(children: [const SizedBox(width: FincasSpacing.s), Expanded(child: stock), ...acciones]),
          ),
        ],
      ),
    );
  }
}
