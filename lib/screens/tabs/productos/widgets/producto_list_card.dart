import 'package:flutter/material.dart';

/// Etiqueta legible de una presentación: 250g, 1kg, 500ml...
String etiquetaPresentacion(num contenido, String unidad) {
  if (unidad == 'g' && contenido >= 1000) {
    final kg = contenido.toDouble() / 1000;
    return '${kg % 1 == 0 ? kg.toInt() : kg}kg';
  }
  return '${contenido % 1 == 0 ? contenido.toInt() : contenido}$unidad';
}

/// Producto en la lista: imagen y nombre arriba, una fila por presentación debajo (diseño anterior).
class ProductoListCard extends StatelessWidget {
  final Map<String, dynamic> producto;
  final VoidCallback onTap;

  const ProductoListCard({super.key, required this.producto, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final nombre = producto['nombre'] ?? 'Sin nombre';
    final rawPresentaciones = producto['presentaciones'] as List?;
    final presentaciones = rawPresentaciones
            ?.map((p) => Map<String, dynamic>.from(p as Map))
            .toList() ??
        [];

    // Use first presentation image, then product cover, then nothing
    String? imagenUrl;
    if (presentaciones.isNotEmpty) {
      imagenUrl = presentaciones.first['imageUrl'] as String?;
    }
    if (imagenUrl == null || imagenUrl.isEmpty) {
      imagenUrl = producto['imagenUrl'] as String?;
    }

    final pendingTueste = producto['pendingTueste'] == true;

    return Stack(
      clipBehavior: Clip.none,
      children: [
      Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        elevation: 1,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Fila de cabecera: imagen + nombre
                Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: imagenUrl != null && imagenUrl.isNotEmpty
                          ? Image.network(
                              imagenUrl,
                              width: 48, height: 48,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => _placeholderImagen(),
                            )
                          : _placeholderImagen(),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        nombre,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Icon(Icons.chevron_right, color: Colors.grey.shade400),
                  ],
                ),

                // Presentaciones
                if (presentaciones.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  const Divider(height: 1),
                  const SizedBox(height: 8),
                  ...presentaciones.map((pp) => _PresentacionRow(pp: pp)),
                ] else ...[
                  const SizedBox(height: 8),
                  Text(
                    'Sin presentaciones — toca para agregar',
                    style: TextStyle(fontSize: 12, color: Colors.orange.shade600, fontStyle: FontStyle.italic),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    ),
    if (pendingTueste)
      Positioned(
        top: 2,
        right: 12,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: Colors.red.shade600,
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.local_fire_department_rounded, size: 12, color: Colors.white),
              SizedBox(width: 4),
              Text(
                'Tueste pendiente',
                style: TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ),
    ],
    );
  }

  Widget _placeholderImagen() {
    return Container(
      width: 48, height: 48,
      decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(10)),
      child: Icon(Icons.inventory_2_rounded, color: Colors.blue.shade300, size: 24),
    );
  }
}

class _PresentacionRow extends StatelessWidget {
  final Map<String, dynamic> pp;
  const _PresentacionRow({required this.pp});

  @override
  Widget build(BuildContext context) {
    final contenido = (pp['contenido'] as num?) ?? 0;
    final unidad = pp['unidad']?.toString() ?? '';
    final precio = (pp['precio'] as num?)?.toDouble() ?? 0;
    final stock = (pp['stock'] as num?)?.toInt() ?? 0;
    final predeterminada = pp['predeterminada'] == true;
    final stockBajo = stock < 5;

    // Friendly label
    String etiqueta;
    if (unidad == 'g' && contenido >= 1000) {
      final kg = contenido.toDouble() / 1000;
      etiqueta = '${kg % 1 == 0 ? kg.toInt() : kg}kg';
    } else {
      etiqueta = '${contenido % 1 == 0 ? contenido.toInt() : contenido}$unidad';
    }

    final imageUrl = pp['imageUrl'] as String?;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          if (imageUrl != null && imageUrl.isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.network(
                imageUrl,
                width: 32, height: 32,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox(width: 32),
              ),
            )
          else
            const SizedBox(width: 0),
          if (imageUrl != null && imageUrl.isNotEmpty) const SizedBox(width: 8),
          // Etiqueta y precio pasan a otra línea si el texto es grande, para no desbordar.
          Expanded(
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 2,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (predeterminada)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: Icon(Icons.star, size: 12, color: Colors.amber.shade600),
                      ),
                    Text(etiqueta, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  ],
                ),
                Text('S/ ${precio.toStringAsFixed(2)}',
                    style: TextStyle(fontSize: 13, color: Colors.green.shade700, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: stockBajo ? Colors.red.shade50 : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (stockBajo)
                  Padding(
                    padding: const EdgeInsets.only(right: 3),
                    child: Icon(Icons.warning_rounded, size: 12, color: Colors.red.shade400),
                  ),
                Text('$stock',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: stockBajo ? Colors.red.shade600 : Colors.grey.shade700,
                    )),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

