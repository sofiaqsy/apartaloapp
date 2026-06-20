import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

class ListaProductosWidget extends StatelessWidget {
  final List<Map<String, dynamic>> productos;
  final bool editable;
  final void Function(Map<String, dynamic> producto)? onEditTap;

  const ListaProductosWidget({
    super.key,
    required this.productos,
    this.editable = false,
    this.onEditTap,
  });

  // Agrupa items con el mismo producto+presentación+grind, sumando cantidades
  // y separando las unidades de pre-venta.
  List<_GrupoProducto> _agrupar() {
    final Map<String, _GrupoProducto> grupos = {};
    for (final p in productos) {
      final nombre = (p['nombre'] ?? '').toString();
      final grind  = (p['grind']  ?? '').toString();
      final presId = (p['presentacionId'] ?? '').toString();
      final key    = '$nombre|$presId|$grind';

      final cantidad    = (p['cantidad']  as num?)?.toInt() ?? 1;
      final precio      = (p['precio']    as num?)?.toDouble() ?? 0.0;
      final subtotal    = (p['subtotal']  as num?)?.toDouble() ?? 0.0;
      final esPreventa  = p['source_event_id'] != null &&
          p['source_event_id'].toString().isNotEmpty;

      if (grupos.containsKey(key)) {
        grupos[key]!.cantidad += cantidad;
        grupos[key]!.subtotal += subtotal;
        if (esPreventa) {
          grupos[key]!.cantidadPreventa += cantidad;
          // Para grupos mixtos, la fecha de tueste relevante es la del evento pre-venta
          final preRoastedAt = p['roastedAt']?.toString() ?? '';
          if (preRoastedAt.isNotEmpty) {
            grupos[key]!.data['roastedAt'] = preRoastedAt;
          }
        }
      } else {
        grupos[key] = _GrupoProducto(
          data:              Map<String, dynamic>.from(p),
          cantidad:          cantidad,
          subtotal:          subtotal,
          precio:            precio,
          cantidadPreventa:  esPreventa ? cantidad : 0,
        );
      }
    }
    return grupos.values.toList();
  }

  @override
  Widget build(BuildContext context) {
    final grupos = _agrupar();
    // Contar productos únicos (no líneas)
    final total = grupos.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('Productos',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const Spacer(),
            Text('$total item${total != 1 ? 's' : ''}',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
          ],
        ),
        const SizedBox(height: 12),
        if (grupos.isEmpty)
          _buildEmptyState()
        else
          ...grupos.map((g) => _buildGrupoItem(g)),
      ],
    );
  }

  Widget _buildCantidadBadge(int cantidad) => Container(
        decoration: BoxDecoration(
          color: Colors.blue.shade100,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Center(
          child: Text('$cantidad',
              style: TextStyle(
                  fontWeight: FontWeight.bold, color: Colors.blue.shade700)),
        ),
      );

  Widget _chip(String label, MaterialColor color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: color.shade50,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.shade100),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w600, color: color.shade700)),
      );

  Widget _buildEmptyState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          Icon(Icons.inventory_2_outlined, size: 40, color: Colors.grey.shade400),
          const SizedBox(height: 8),
          Text('Sin detalle de productos',
              style: TextStyle(color: Colors.grey.shade500)),
        ],
      ),
    );
  }

  Widget _buildGrupoItem(_GrupoProducto grupo) {
    final p          = grupo.data;
    final nombre     = (p['nombre'] ?? '').toString();
    final precio     = grupo.precio;
    final cantidad   = grupo.cantidad;
    final subtotal   = grupo.subtotal;
    final preventa   = grupo.cantidadPreventa;
    final tienePrev  = preventa > 0;
    final unit       = (p['unit'] ?? '').toString().trim();
    final showUnit   = unit.isNotEmpty && unit != 'unidad';
    final roastedAt  = p['roastedAt']?.toString() ?? '';

    String? grindLabel;
    final grindRaw = p['grind'];
    if (grindRaw != null && grindRaw.toString().isNotEmpty) {
      grindLabel = switch (grindRaw.toString()) {
        'ground' => 'Molido',
        'whole'  => 'Grano',
        'green'  => 'Verde',
        _        => grindRaw.toString(),
      };
    }

    final moliendaRaw = p['molienda'];
    final molienda = (grindLabel == null && moliendaRaw is List)
        ? moliendaRaw.map((e) {
            return switch (e.toString()) {
              'ground' => 'Molido',
              'whole'  => 'Grano',
              'green'  => 'Verde',
              _        => e.toString(),
            };
          }).where((e) => e.isNotEmpty).toList()
        : <String>[];

    final imageUrl = p['imageUrl']?.toString() ?? '';

    return GestureDetector(
      onTap: editable && onEditTap != null ? () => onEditTap!(p) : null,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: editable ? Colors.blue.shade100 : Colors.grey.shade200,
          ),
        ),
        child: Row(
          children: [
            // Imagen / badge de cantidad
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 44,
                height: 44,
                child: imageUrl.isNotEmpty
                    ? Stack(
                        fit: StackFit.expand,
                        children: [
                          CachedNetworkImage(
                            imageUrl: imageUrl,
                            fit: BoxFit.cover,
                            memCacheWidth: 88,
                            placeholder: (_, __) => Container(
                              color: Colors.grey.shade200,
                              child: Center(
                                child: SizedBox(
                                  width: 16, height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 1.5,
                                    color: Colors.grey.shade400,
                                  ),
                                ),
                              ),
                            ),
                            errorWidget: (_, __, ___) => _buildCantidadBadge(cantidad),
                          ),
                          Positioned(
                            right: 0,
                            bottom: 0,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.blue.shade700.withValues(alpha: 0.85),
                                borderRadius: const BorderRadius.only(
                                  topLeft: Radius.circular(6),
                                ),
                              ),
                              child: Text('×$cantidad',
                                  style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white)),
                            ),
                          ),
                        ],
                      )
                    : _buildCantidadBadge(cantidad),
              ),
            ),
            const SizedBox(width: 10),

            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(nombre,
                      style: const TextStyle(fontWeight: FontWeight.w500)),
                  const SizedBox(height: 3),
                  Wrap(
                    spacing: 5,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (showUnit) _chip(unit, Colors.deepOrange),
                      if (grindLabel != null)
                        _chip(grindLabel, Colors.brown)
                      else
                        ...molienda.map((g) => _chip(g, Colors.brown)),
                      Text('S/ ${precio.toStringAsFixed(2)} c/u',
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                    ],
                  ),
                  // Badge de pre-venta si aplica
                  if (tienePrev) ...[
                    const SizedBox(height: 5),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.orange.shade200),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.schedule_outlined,
                              size: 11, color: Colors.orange.shade700),
                          const SizedBox(width: 4),
                          Text(
                            '$preventa ${preventa == 1 ? 'unidad' : 'unidades'} en pre-venta',
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Colors.orange.shade700),
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (roastedAt.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.local_fire_department_outlined,
                            size: 12, color: Colors.brown.shade400),
                        const SizedBox(width: 3),
                        Text('Tueste: $roastedAt',
                            style: TextStyle(
                                fontSize: 11, color: Colors.brown.shade400)),
                      ],
                    ),
                  ],
                ],
              ),
            ),

            // Subtotal + editar
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('S/ ${subtotal.toStringAsFixed(2)}',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                if (editable)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Icon(Icons.edit_outlined,
                        size: 14, color: Colors.blue.shade300),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _GrupoProducto {
  final Map<String, dynamic> data;
  int cantidad;
  double subtotal;
  final double precio;
  int cantidadPreventa;

  _GrupoProducto({
    required this.data,
    required this.cantidad,
    required this.subtotal,
    required this.precio,
    required this.cantidadPreventa,
  });
}
