import 'package:flutter/material.dart';
import '../../../../theme/fincas_tokens.dart';
import '../../../../widgets/fincas_widgets.dart';

String _soles(double v) => 'S/${v.toStringAsFixed(0)}';

Color _toneFg(FincasTone t) => switch (t) {
      FincasTone.success => FincasColors.success,
      FincasTone.error => FincasColors.error,
      FincasTone.warning => FincasColors.warning,
      FincasTone.neutral => FincasColors.ink,
    };

Color _toneBg(FincasTone t) => switch (t) {
      FincasTone.success => FincasColors.successBg,
      FincasTone.error => FincasColors.errorBg,
      FincasTone.warning => FincasColors.warningBg,
      FincasTone.neutral => FincasColors.sand,
    };

/// Filtro principal (Pendientes / Historial): relleno sólido cuando está activo y tinte suave cuando no.
/// Pendientes usa un espresso suave (de la misma familia que "Nuevo pedido"); Historial es neutro (tinta y arena).
class PedidosFiltroChip extends StatelessWidget {
  const PedidosFiltroChip({
    super.key,
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
    this.tone = FincasTone.neutral,
    this.mutedAccent = false,
  });
  final String label;
  final int count;
  final bool selected;
  final FincasTone tone;

  /// Uses a softer espresso (same family as the Nuevo pedido button) instead of a status tone.
  final bool mutedAccent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final solid = mutedAccent ? FincasColors.accentMuted : _toneFg(tone);
    final soft = mutedAccent ? FincasColors.accentBg : _toneBg(tone);
    final fg = selected ? FincasColors.textOnInk : solid;
    return Semantics(
      button: true,
      selected: selected,
      label: count > 0 ? '$label, $count' : label,
      excludeSemantics: true,
      child: Material(
        color: selected ? solid : soft,
        borderRadius: BorderRadius.circular(FincasRadii.medium),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(FincasRadii.medium),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: FincasSpacing.minTouch),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: FincasSpacing.m, vertical: FincasSpacing.s),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Flexible(
                    child: Text(label,
                        overflow: TextOverflow.ellipsis,
                        style: FincasText.label.copyWith(color: fg, fontWeight: selected ? FontWeight.w700 : FontWeight.w600, fontSize: 15)),
                  ),
                  if (count > 0) ...[
                    const SizedBox(width: FincasSpacing.s),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: selected ? FincasColors.textOnInk.withValues(alpha: 0.22) : FincasColors.surface,
                        borderRadius: BorderRadius.circular(FincasRadii.small + 4),
                      ),
                      child: Text('$count', style: FincasText.caption.copyWith(color: fg, fontWeight: FontWeight.w700)),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Subfiltro del historial: píldora con borde; el tono marca el significado (pagado, por cobrar).
class PedidosSubFiltroChip extends StatelessWidget {
  const PedidosSubFiltroChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.count = 0,
    this.tone = FincasTone.neutral,
  });
  final String label;
  final int count;
  final bool selected;
  final FincasTone tone;
  final VoidCallback onTap;

  Color get _fg => switch (tone) {
        FincasTone.success => FincasColors.success,
        FincasTone.error => FincasColors.error,
        FincasTone.warning => FincasColors.warning,
        FincasTone.neutral => FincasColors.espresso,
      };
  Color get _bg => switch (tone) {
        FincasTone.success => FincasColors.successBg,
        FincasTone.error => FincasColors.errorBg,
        FincasTone.warning => FincasColors.warningBg,
        FincasTone.neutral => FincasColors.sand,
      };

  @override
  Widget build(BuildContext context) {
    final text = count > 0 ? '$label ($count)' : label;
    return Semantics(
      button: true,
      selected: selected,
      label: text,
      excludeSemantics: true,
      child: Material(
        color: selected ? _bg : Colors.transparent,
        shape: StadiumBorder(side: BorderSide(color: selected ? _fg : FincasColors.border)),
        child: InkWell(
          onTap: onTap,
          customBorder: const StadiumBorder(),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: FincasSpacing.l),
              child: Center(
                widthFactor: 1,
                child: Text(text,
                    style: FincasText.label.copyWith(
                        color: selected ? _fg : FincasColors.textSecondary, fontWeight: selected ? FontWeight.w600 : FontWeight.w500)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Resumen del historial: vendido, cobrado y por cobrar en una sola franja, sin gradientes.
class PedidosResumen extends StatelessWidget {
  const PedidosResumen({super.key, required this.vendido, required this.cobrado, required this.porCobrar, this.hayAlerta = false});
  final double vendido;
  final double cobrado;
  final double porCobrar;
  final bool hayAlerta;

  Widget _stat(String label, double valor, Color color, {bool alerta = false}) {
    return Expanded(
      child: Column(
        children: [
          Text(label, style: FincasText.caption),
          const SizedBox(height: 2),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  _soles(valor),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: FincasText.sectionTitle.copyWith(fontSize: 16, fontWeight: FontWeight.w700, color: color),
                ),
              ),
              if (alerta) ...[
                const SizedBox(width: FincasSpacing.xs),
                Icon(Icons.warning_amber_rounded, size: 16, color: color),
              ],
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const divider = SizedBox(height: 32, child: VerticalDivider(width: 1, color: FincasColors.divider));
    return Semantics(
      label: 'Resumen. Vendido ${_soles(vendido)}, cobrado ${_soles(cobrado)}, por cobrar ${_soles(porCobrar)}',
      excludeSemantics: true,
      child: Container(
        margin: const EdgeInsets.fromLTRB(FincasSpacing.l, FincasSpacing.s, FincasSpacing.l, 0),
        padding: const EdgeInsets.symmetric(vertical: FincasSpacing.m),
        decoration: BoxDecoration(
          color: FincasColors.surface,
          borderRadius: BorderRadius.circular(FincasRadii.large),
          border: Border.all(color: FincasColors.border),
        ),
        child: Row(
          children: [
            _stat('Vendido', vendido, FincasColors.textPrimary),
            divider,
            _stat('Cobrado', cobrado, FincasColors.success),
            divider,
            _stat('Por cobrar', porCobrar, FincasColors.error, alerta: hayAlerta),
          ],
        ),
      ),
    );
  }
}

/// Acciones de creación de la pestaña: "Nuevo pedido" es la principal (caramelo) y "Pre-venta" es secundaria
/// (arena, más ligera). Las dos están siempre visibles; se acomodan en dos filas si el texto es grande.
class PedidosCrearBotones extends StatelessWidget {
  const PedidosCrearBotones({super.key, required this.onNuevo, required this.onPreventa});
  final VoidCallback onNuevo;
  final VoidCallback onPreventa;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.end,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: FincasSpacing.s,
      runSpacing: FincasSpacing.s,
      children: [
        Semantics(
          button: true,
          label: 'Pre-venta',
          excludeSemantics: true,
          child: Material(
            color: FincasColors.sand,
            shape: const StadiumBorder(),
            child: InkWell(
              onTap: onPreventa,
              customBorder: const StadiumBorder(),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: FincasSpacing.minTouch),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: FincasSpacing.xl - 2),
                  child: Center(widthFactor: 1, child: Text('Pre-venta', style: FincasText.button.copyWith(color: FincasColors.textPrimary))),
                ),
              ),
            ),
          ),
        ),
        FloatingActionButton.extended(
          heroTag: 'fab_pedidos',
          onPressed: onNuevo,
          shape: const StadiumBorder(),
          label: const Text('Nuevo pedido'),
        ),
      ],
    );
  }
}
