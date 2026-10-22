import 'package:flutter/material.dart';
import '../../../../theme/fincas_tokens.dart';
import '../../../../widgets/fincas_widgets.dart';

enum NuevoPedidoTipo { pedido, preventa }

/// Qué se va a crear. Es la única acción de creación de la pestaña; elegir aquí evita dos botones flotantes.
Future<NuevoPedidoTipo?> showNuevoPedidoSheet(BuildContext context) {
  return showModalBottomSheet<NuevoPedidoTipo>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(FincasSpacing.screenH, 0, FincasSpacing.screenH, FincasSpacing.l),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const FincasSectionHeader('¿Qué quieres crear?'),
            _Opcion(
              titulo: 'Pedido',
              descripcion: 'Una venta a un cliente.',
              tone: FincasTone.warning,
              onTap: () => Navigator.pop(ctx, NuevoPedidoTipo.pedido),
            ),
            const SizedBox(height: FincasSpacing.s),
            _Opcion(
              titulo: 'Pre-venta',
              descripcion: 'Una venta por adelantado.',
              tone: FincasTone.success,
              onTap: () => Navigator.pop(ctx, NuevoPedidoTipo.preventa),
            ),
          ],
        ),
      ),
    ),
  );
}

class _Opcion extends StatelessWidget {
  const _Opcion({required this.titulo, required this.descripcion, required this.tone, required this.onTap});
  final String titulo;
  final String descripcion;
  final FincasTone tone;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = tone == FincasTone.success ? FincasColors.success : FincasColors.warning;
    return Semantics(
      button: true,
      label: '$titulo. $descripcion',
      excludeSemantics: true,
      child: FincasCard(
        onTap: onTap,
        child: Row(
          children: [
            Container(width: 4, height: 40, decoration: BoxDecoration(color: fg, borderRadius: BorderRadius.circular(2))),
            const SizedBox(width: FincasSpacing.m),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(titulo, style: FincasText.sectionTitle),
                  const SizedBox(height: 2),
                  Text(descripcion, style: FincasText.metadata),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: fg),
          ],
        ),
      ),
    );
  }
}
