import 'package:flutter/material.dart';
import '../../../../theme/fincas_tokens.dart';
import '../../../../widgets/fincas_widgets.dart';

/// Etiqueta legible de una presentación: 250g, 1kg, 500ml...
String etiquetaPresentacion(num contenido, String unidad) {
  if (unidad == 'g' && contenido >= 1000) {
    final kg = contenido.toDouble() / 1000;
    return '${kg % 1 == 0 ? kg.toInt() : kg}kg';
  }
  return '${contenido % 1 == 0 ? contenido.toInt() : contenido}$unidad';
}

/// Producto en la lista: imagen y nombre arriba, una fila por presentación debajo.
/// Superficie con borde (sin sombra); el stock bajo y el tueste pendiente se dicen con texto.
class ProductoListCard extends StatelessWidget {
  const ProductoListCard({super.key, required this.producto, required this.onTap});
  final Map<String, dynamic> producto;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final nombre = (producto['nombre'] ?? 'Sin nombre').toString();
    final presentaciones = (producto['presentaciones'] as List?)?.map((p) => Map<String, dynamic>.from(p as Map)).toList() ?? [];

    // Imagen de la primera presentación, luego la portada del producto, luego nada.
    String? imagenUrl = presentaciones.isNotEmpty ? presentaciones.first['imageUrl'] as String? : null;
    if (imagenUrl == null || imagenUrl.isEmpty) imagenUrl = producto['imagenUrl'] as String?;
    final pendingTueste = producto['pendingTueste'] == true;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: FincasSpacing.l, vertical: FincasSpacing.xs + 1),
      child: Semantics(
        button: true,
        label: '$nombre${pendingTueste ? ', tueste pendiente' : ''}, ${presentaciones.length} presentaciones',
        excludeSemantics: true,
        child: FincasCard(
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(FincasRadii.medium - 2),
                    child: imagenUrl != null && imagenUrl.isNotEmpty
                        ? Image.network(imagenUrl, width: 48, height: 48, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _Inicial(nombre))
                        : _Inicial(nombre),
                  ),
                  const SizedBox(width: FincasSpacing.m),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(nombre, maxLines: 2, overflow: TextOverflow.ellipsis, style: FincasText.sectionTitle.copyWith(fontSize: 16)),
                        if (pendingTueste) ...[
                          const SizedBox(height: FincasSpacing.xs),
                          const FincasStatusBadge('Tueste pendiente', tone: FincasTone.warning),
                        ],
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right, color: FincasColors.textMuted),
                ],
              ),
              if (presentaciones.isNotEmpty) ...[
                const SizedBox(height: FincasSpacing.m),
                const Divider(),
                const SizedBox(height: FincasSpacing.s),
                ...presentaciones.map((pp) => PresentacionRow(pp: pp)),
              ] else ...[
                const SizedBox(height: FincasSpacing.s),
                Text('Sin presentaciones. Toca para agregar.', style: FincasText.metadata.copyWith(color: FincasColors.warning)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Inicial del producto sobre arena cuando no hay imagen.
class _Inicial extends StatelessWidget {
  const _Inicial(this.nombre);
  final String nombre;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 48,
      height: 48,
      color: FincasColors.sand,
      alignment: Alignment.center,
      child: Text(nombre.isNotEmpty ? nombre[0].toUpperCase() : '?', style: FincasText.sectionTitle.copyWith(color: FincasColors.espresso)),
    );
  }
}

/// Una presentación: etiqueta, precio y stock (en texto, el color nunca es la única señal).
class PresentacionRow extends StatelessWidget {
  const PresentacionRow({super.key, required this.pp});
  final Map<String, dynamic> pp;

  @override
  Widget build(BuildContext context) {
    final contenido = (pp['contenido'] as num?) ?? 0;
    final unidad = pp['unidad']?.toString() ?? '';
    final precio = (pp['precio'] as num?)?.toDouble() ?? 0;
    final stock = (pp['stock'] as num?)?.toInt() ?? 0;
    final predeterminada = pp['predeterminada'] == true;
    final stockBajo = stock < 5;
    final imageUrl = pp['imageUrl'] as String?;

    final largeText = MediaQuery.textScalerOf(context).scale(16) / 16 > 1.3;

    final datos = Wrap(
      spacing: FincasSpacing.s,
      runSpacing: FincasSpacing.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (predeterminada) const Icon(Icons.star, size: 14, color: FincasColors.espresso, semanticLabel: 'Presentación predeterminada'),
        Text(etiquetaPresentacion(contenido, unidad), style: FincasText.label.copyWith(fontSize: 14, fontWeight: FontWeight.w600)),
        Text('S/ ${precio.toStringAsFixed(2)}',
            style: FincasText.bodySecondary.copyWith(fontWeight: FontWeight.w600, color: FincasColors.textPrimary)),
      ],
    );
    final stockBadge = FincasStatusBadge(stockBajo ? 'Stock bajo · $stock' : 'Stock $stock', tone: stockBajo ? FincasTone.error : FincasTone.neutral);
    final miniatura = (imageUrl != null && imageUrl.isNotEmpty)
        ? Padding(
            padding: const EdgeInsets.only(right: FincasSpacing.s),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.network(imageUrl, width: 32, height: 32, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox(width: 32, height: 32)),
            ),
          )
        : const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: FincasSpacing.s - 2),
      // Con texto grande el stock pasa debajo, para que etiqueta y precio conserven su ancho.
      child: largeText
          ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              miniatura,
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [datos, const SizedBox(height: FincasSpacing.xs), stockBadge])),
            ])
          : Row(children: [miniatura, Expanded(child: datos), const SizedBox(width: FincasSpacing.s), stockBadge]),
    );
  }
}
