import 'dart:convert';

/// Parsea productos desde diferentes formatos (JSON, String, List)
List<Map<String, dynamic>> parseProductos(dynamic productosRaw) {
  if (productosRaw == null || productosRaw == '') return [];
  
  if (productosRaw is List) {
    return productosRaw.map((p) {
      if (p is Map) {
        final mapa = Map<String, dynamic>.from(p);
        final cantidad = (mapa['cantidad'] as num?)?.toInt() ?? 1;
        final precio = (mapa['precio'] as num?)?.toDouble() ?? 0.0;
        final subtotal = (mapa['subtotal'] as num?)?.toDouble() ?? (precio * cantidad);
        return <String, dynamic>{...mapa, 'cantidad': cantidad, 'precio': precio, 'subtotal': subtotal};
      }
      return <String, dynamic>{};
    }).where((p) => p.isNotEmpty).toList();
  }
  
  if (productosRaw is String) {
    final trimmed = productosRaw.trim();
    
    if (trimmed.startsWith('[') || trimmed.startsWith('{')) {
      try {
        final parsed = jsonDecode(trimmed);
        if (parsed is List) {
          return parsed.map((p) {
            if (p is Map) {
              final mapa = Map<String, dynamic>.from(p);
              final cantidad = (mapa['cantidad'] as num?)?.toInt() ?? 1;
              final precio = (mapa['precio'] as num?)?.toDouble() ?? 0.0;
              final subtotal = (mapa['subtotal'] as num?)?.toDouble() ?? (precio * cantidad);
              return <String, dynamic>{...mapa, 'cantidad': cantidad, 'precio': precio, 'subtotal': subtotal};
            }
            return <String, dynamic>{};
          }).where((p) => p.isNotEmpty).toList();
        }
      } catch (_) {}
    }
    
    final List<Map<String, dynamic>> productos = [];
    final normalizado = trimmed.replaceAll(RegExp(r'\r?\n'), '|||');
    final partes = normalizado.split(RegExp(r'\|\|\||,\s+(?=\d+x\s)'));
    
    for (final parte in partes) {
      final item = parte.trim();
      if (item.isEmpty) continue;
      
      final cantidadMatch = RegExp(r'^(\d+)x\s+(.+)').firstMatch(item);
      int cantidad = 1;
      String resto = item;
      
      if (cantidadMatch != null) {
        cantidad = int.tryParse(cantidadMatch.group(1) ?? '1') ?? 1;
        resto = cantidadMatch.group(2) ?? item;
      }
      
      double subtotal = 0.0;
      String nombre = resto;
      
      final idx = resto.lastIndexOf(RegExp(r'\s*[-–]\s*S'));
      if (idx > 0) {
        final posiblePrecio = resto.substring(idx);
        final match = RegExp(r'S[/.]?\s*(\d+(?:[.,]\d+)?)').firstMatch(posiblePrecio);
        if (match != null) {
          final precioStr = (match.group(1) ?? '0').replaceAll(',', '.');
          subtotal = double.tryParse(precioStr) ?? 0.0;
          nombre = resto.substring(0, idx).trim();
        }
      }
      
      final precioUnitario = cantidad > 0 ? subtotal / cantidad : 0.0;
      
      if (nombre.isNotEmpty) {
        productos.add(<String, dynamic>{
          'nombre': nombre,
          'cantidad': cantidad,
          'precio': precioUnitario,
          'subtotal': subtotal,
        });
      }
    }
    
    if (productos.isNotEmpty) return productos;
    
    if (trimmed.isNotEmpty) {
      return [<String, dynamic>{'nombre': trimmed, 'cantidad': 1, 'precio': 0.0, 'subtotal': 0.0}];
    }
  }
  
  return [];
}

/// Agrupa productos con el mismo nombre+presentación+grind sumando cantidad y subtotal.
/// Elimina la separación stock/pre-venta para mostrar como un único ítem.
List<Map<String, dynamic>> agruparProductos(List<Map<String, dynamic>> productos) {
  final Map<String, Map<String, dynamic>> grupos = {};
  for (final p in productos) {
    final nombre = (p['nombre'] ?? '').toString();
    final grind  = (p['grind']  ?? '').toString();
    final presId = (p['presentacionId'] ?? '').toString();
    final key    = '$nombre|$presId|$grind';

    if (grupos.containsKey(key)) {
      final g = grupos[key]!;
      final cantExtra = (p['cantidad'] as num?)?.toInt() ?? 1;
      final subExtra  = (p['subtotal'] as num?)?.toDouble() ?? 0.0;
      g['cantidad'] = ((g['cantidad'] as num).toInt()) + cantExtra;
      g['subtotal'] = ((g['subtotal'] as num).toDouble()) + subExtra;
      // Para grupos mixtos, la fecha del evento pre-venta tiene precedencia
      final esPreventa = p['source_event_id'] != null &&
          p['source_event_id'].toString().isNotEmpty;
      if (esPreventa) {
        final preRoastedAt = p['roastedAt']?.toString() ?? '';
        if (preRoastedAt.isNotEmpty) g['roastedAt'] = preRoastedAt;
      }
    } else {
      grupos[key] = Map<String, dynamic>.from(p);
    }
  }
  return grupos.values.toList();
}
