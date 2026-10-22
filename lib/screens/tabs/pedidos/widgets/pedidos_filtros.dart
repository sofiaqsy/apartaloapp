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

/// Filtro principal (Pendientes / Historial): relleno del color de su significado cuando está activo,
/// y su tinte suave cuando no. Pendientes = caramelo, Historial = salvia.
class PedidosFiltroChip extends StatelessWidget {
  const PedidosFiltroChip({
    super.key,
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
    this.tone = FincasTone.neutral,
  });
  final String label;
  final int count;
  final bool selected;
  final FincasTone tone;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? FincasColors.textOnInk : _toneFg(tone);
    return Semantics(
      button: true,
      selected: selected,
      label: count > 0 ? '$label, $count' : label,
      excludeSemantics: true,
      child: Material(
        color: selected ? _toneFg(tone) : _toneBg(tone),
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

/// Resumen del historial: tres celdas con tinte propio (neutro, salvia, terracota), sin gradientes.
class PedidosResumen extends StatelessWidget {
  const PedidosResumen({super.key, required this.vendido, required this.cobrado, required this.porCobrar, this.hayAlerta = false});
  final double vendido;
  final double cobrado;
  final double porCobrar;
  final bool hayAlerta;

  Widget _celda(String label, double valor, FincasTone tone, {bool alerta = false}) {
    final fg = tone == FincasTone.neutral ? FincasColors.textPrimary : _toneFg(tone);
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: FincasSpacing.m - 2, horizontal: FincasSpacing.s),
        decoration: BoxDecoration(color: _toneBg(tone), borderRadius: BorderRadius.circular(FincasRadii.medium)),
        child: Column(
          children: [
            Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: FincasText.caption.copyWith(color: FincasColors.textSecondary)),
            const SizedBox(height: 2),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: Text(
                    _soles(valor),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: FincasText.sectionTitle.copyWith(fontSize: 16, fontWeight: FontWeight.w700, color: fg),
                  ),
                ),
                if (alerta) ...[
                  const SizedBox(width: FincasSpacing.xs),
                  Icon(Icons.warning_amber_rounded, size: 16, color: fg),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Resumen. Vendido ${_soles(vendido)}, cobrado ${_soles(cobrado)}, por cobrar ${_soles(porCobrar)}',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(FincasSpacing.l, FincasSpacing.m, FincasSpacing.l, 0),
        child: Row(
          children: [
            _celda('Vendido', vendido, FincasTone.neutral),
            const SizedBox(width: FincasSpacing.s),
            _celda('Cobrado', cobrado, FincasTone.success),
            const SizedBox(width: FincasSpacing.s),
            _celda('Por cobrar', porCobrar, porCobrar > 0 ? FincasTone.error : FincasTone.neutral, alerta: hayAlerta),
          ],
        ),
      ),
    );
  }
}
