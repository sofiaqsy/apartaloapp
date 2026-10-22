import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../theme/fincas_tokens.dart';
import 'fincas_widgets.dart';

/// La presentación que se muestra con su formulario abierto al entrar: la primera de la lista.
String? primeraPresentacionAbierta(List<Presentacion> presentaciones) => presentaciones.isEmpty ? null : presentaciones.first.id;

/// Una presentación del producto: contenido, precios, molienda y stock, con sus acciones.
/// Cerrada muestra el resumen; abierta muestra su formulario ([formulario]) dentro de la misma tarjeta.
/// El estado (predeterminada, oculta en tienda) se dice con texto, no solo con color.
class PresentacionTile extends StatelessWidget {
  const PresentacionTile({
    super.key,
    required this.presentacion,
    required this.onAlternar,
    required this.onEliminar,
    this.abierta = false,
    this.formulario,
    this.simboloMoneda = 'S/',
    this.stockManual = false,
  });

  final Presentacion presentacion;

  /// Abre o cierra el formulario de esta presentación.
  final VoidCallback onAlternar;
  final VoidCallback onEliminar;
  final bool abierta;
  final Widget? formulario;
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
      abierta ? 'Editando' : (stockManual ? 'Stock manual: ${p.stock}' : 'Stock: ${p.stock}'),
      style: FincasText.metadata.copyWith(fontWeight: FontWeight.w600),
    );
    final acciones = <Widget>[
      if (!abierta) TextButton(onPressed: onAlternar, child: const Text('Editar')),
      TextButton(
        onPressed: onEliminar,
        style: TextButton.styleFrom(foregroundColor: FincasColors.error),
        child: const Text('Eliminar'),
      ),
      if (abierta) TextButton(onPressed: onAlternar, child: const Text('Cerrar')),
    ];

    // Material (no una caja con color): los interruptores del formulario abierto pintan su tinta sobre él.
    return Padding(
      padding: const EdgeInsets.only(bottom: FincasSpacing.s),
      child: Material(
      color: FincasColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(FincasRadii.large), side: const BorderSide(color: FincasColors.border)),
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
                      if (!abierta) ...[
                        const SizedBox(height: FincasSpacing.xs),
                        Text('$simboloMoneda ${p.precio.toStringAsFixed(2)}',
                            style: FincasText.body.copyWith(fontWeight: FontWeight.w700)),
                        if (detalles.isNotEmpty) Text(detalles.join(' · '), style: FincasText.metadata),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (abierta && formulario != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(FincasSpacing.l, 0, FincasSpacing.l, FincasSpacing.m),
              child: formulario,
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
      ),
    );
  }
}

/// Tarjeta de una presentación nueva: está en la misma lista que las demás, abierta y con su formulario.
/// [onCancelar] la quita sin guardar nada.
class PresentacionNuevaCard extends StatelessWidget {
  const PresentacionNuevaCard({super.key, required this.formulario});
  final Widget formulario;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: FincasSpacing.s),
      child: Material(
        color: FincasColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(FincasRadii.large), side: const BorderSide(color: FincasColors.accent)),
        child: Padding(
          padding: const EdgeInsets.all(FincasSpacing.l),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(header: true, child: const Text('Nueva presentación', style: FincasText.sectionTitle)),
              const SizedBox(height: FincasSpacing.m),
              formulario,
            ],
          ),
        ),
      ),
    );
  }
}

