import 'package:flutter/material.dart';
import '../services/api_service.dart';

class CrearPedidoScreen extends StatefulWidget {
  final Map<String, dynamic>? cliente;

  const CrearPedidoScreen({super.key, this.cliente});

  @override
  State<CrearPedidoScreen> createState() => _CrearPedidoScreenState();
}

class _CrearPedidoScreenState extends State<CrearPedidoScreen> with SingleTickerProviderStateMixin {
  bool _isLoading = false;
  bool _loadingProductos = true;
  List<Map<String, dynamic>> _productos = [];
  List<_LineaProducto> _lineas = [];
  final List<_ItemCarrito> _carrito = [];
  final Map<String, bool> _tieneProximoTostado = {};
  final Map<String, double> _proximoKg = {};      // nextEventKg por producto
  final Map<String, String?> _proximoEventId = {}; // nextEventId por producto
  final Set<String> _consultandoStock = {};

  // Cliente seleccionado de la lista
  Map<String, dynamic>? _clienteSeleccionado;
  List<Map<String, dynamic>> _clientes = [];
  bool _loadingClientes = false;

  // Datos del cliente
  late TextEditingController _clienteController;
  late TextEditingController _whatsappController;
  late TextEditingController _direccionController;
  late TextEditingController _observacionesController;

  bool _notificarCliente = false;
  String? _busqueda;

  // Delivery
  double _costoDelivery = 0;
  late TextEditingController _deliveryController;

  // Tab controller para móvil
  late TabController _tabController;

  // Precios personalizados del cliente
  Map<String, double> _preciosCliente = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _deliveryController = TextEditingController(text: '0');
    _initDatosCliente();
    _cargarDatos();
  }

  Future<void> _cargarDatos() async {
    final clienteId = widget.cliente?['id'] as String?;

    // Productos es lo más crítico para el usuario — lo lanzamos primero
    // Clientes y precios en paralelo sin bloquear UI
    await Future.wait([
      _cargarProductos(),
      _cargarClientes(),
      if (clienteId != null && clienteId.isNotEmpty)
        _cargarPreciosCliente(clienteId),
    ]);
  }

  Future<void> _cargarClientes() async {
    setState(() => _loadingClientes = true);
    final result = await ApiService.getClientes();
    if (mounted) {
      setState(() {
        _clientes = result.isSuccess ? (result.data ?? []) : [];
        _loadingClientes = false;
      });
    }
  }

  Future<void> _cargarPreciosCliente(String clienteId) async {
    final result = await ApiService.getPreciosCliente(clienteId: clienteId);
    if (result.isSuccess && result.data != null) {
      setState(() => _preciosCliente = result.data!);
    }
  }

  void _initDatosCliente() {
    if (widget.cliente != null) _clienteSeleccionado = widget.cliente;
    final c = widget.cliente ?? {};
    
    // Nombre del cliente: prioridad nombreNegocio > nombreResponsable > nombre
    String nombreCliente = '';
    if ((c['nombreNegocio'] ?? '').toString().isNotEmpty) {
      nombreCliente = c['nombreNegocio'];
    } else if ((c['nombreResponsable'] ?? '').toString().isNotEmpty) {
      nombreCliente = c['nombreResponsable'];
    } else if ((c['nombre'] ?? '').toString().isNotEmpty) {
      nombreCliente = c['nombre'];
    } else if ((c['whatsapp'] ?? '').toString().isNotEmpty) {
      nombreCliente = c['whatsapp'];
    } else if ((c['telefono'] ?? '').toString().isNotEmpty) {
      nombreCliente = c['telefono'];
    }
    
    // Dirección de envío: construir dirección completa
    String direccionCompleta = _construirDireccionEnvio(c);
    
    _clienteController = TextEditingController(text: nombreCliente)
      ..addListener(() => setState(() {}));
    _whatsappController = TextEditingController(text: c['whatsapp'] ?? '');
    _direccionController = TextEditingController(text: direccionCompleta);
    _observacionesController = TextEditingController();
    
    // Si hay datos de envío, agregarlos a observaciones
    _autocompletarObservaciones(c);
  }
  
  /// Construye la dirección de envío completa del cliente según su tipoEnvio
  String _construirDireccionEnvio(Map<String, dynamic> cliente) {
    final tipoEnvio = (cliente['tipoEnvio'] ?? '').toString().trim().toUpperCase();

    // ── SEDE: usar sólo el punto de recojo (guardado en localEnvio, col R) ──
    if (tipoEnvio == 'SEDE') {
      return (cliente['localEnvio'] ?? cliente['sedeEnvio'] ?? '').toString().trim();
    }

    // ── NACIONAL: prioridad a datos de courier ──
    // ── LOCAL: prioridad a dirección de ubicación ──
    final List<String> partes = [];

    final direccionEnvio = (cliente['direccionEnvio'] ?? '').toString().trim();
    final direccion = (cliente['direccion'] ?? '').toString().trim();

    if (tipoEnvio == 'NACIONAL' && direccionEnvio.isNotEmpty) {
      partes.add(direccionEnvio);
    } else if (direccion.isNotEmpty) {
      partes.add(direccion);
    } else if (direccionEnvio.isNotEmpty) {
      partes.add(direccionEnvio);
    }

    // Distrito
    final distritoEnvio = (cliente['distritoEnvio'] ?? '').toString().trim();
    final distrito = (cliente['distrito'] ?? cliente['ciudad'] ?? '').toString().trim();

    if (tipoEnvio == 'NACIONAL' && distritoEnvio.isNotEmpty) {
      partes.add(distritoEnvio);
    } else if (distrito.isNotEmpty) {
      partes.add(distrito);
    } else if (distritoEnvio.isNotEmpty) {
      partes.add(distritoEnvio);
    }

    // Departamento
    final departamentoEnvio = (cliente['departamentoEnvio'] ?? '').toString().trim();
    final departamento = (cliente['departamento'] ?? '').toString().trim();

    if (tipoEnvio == 'NACIONAL' && departamentoEnvio.isNotEmpty) {
      partes.add(departamentoEnvio);
    } else if (departamento.isNotEmpty) {
      partes.add(departamento);
    } else if (departamentoEnvio.isNotEmpty) {
      partes.add(departamentoEnvio);
    }

    final resultado = partes.join(', ');

    // Si no se construyó nada, intentar con cualquier campo de dirección disponible
    if (resultado.isEmpty) {
      for (final key in ['localEnvio', 'direccionEnvio', 'direccion', 'distrito', 'ciudad', 'departamento']) {
        final val = (cliente[key] ?? '').toString().trim();
        if (val.isNotEmpty) return val;
      }
    }

    return resultado;
  }

  /// Autocompleta observaciones — solo notas del cliente.
  /// Los datos de envío (tipoEnvio, empresa, dirección) se guardan
  /// en sus propias columnas del spreadsheet, no en Observaciones.
  void _autocompletarObservaciones(Map<String, dynamic> cliente) {
    final List<String> notas = [];

    // Solo las notas libres del cliente
    final notasCliente = (cliente['notas'] ?? '').toString().trim();
    if (notasCliente.isNotEmpty) {
      notas.add(notasCliente);
    }

    if (notas.isNotEmpty) {
      _observacionesController.text = notas.join(' | ');
    }
  }

  void _cambiarGrindEnCarrito(int index) {
    final item = _carrito[index];
    if (item.presentacionId == null) return;
    final linea = _lineas.firstWhere(
      (l) => l.presentacion?.id == item.presentacionId,
      orElse: () => _lineas.first,
    );
    final molienda = linea.presentacion?.molienda ?? [];
    if (molienda.length <= 1) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.symmetric(vertical: 10),
              width: 36, height: 4,
              decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2)),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              child: Text('Tipo de molienda',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            ),
            ...molienda.map((raw) {
              final label = _grindLabel(raw);
              final selected = item.grind == raw;
              return ListTile(
                leading: Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                    color: selected ? Colors.brown.shade100 : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.coffee_rounded,
                      color: selected ? Colors.brown.shade700 : Colors.grey.shade500,
                      size: 18),
                ),
                title: Text(label,
                    style: TextStyle(
                        fontWeight: selected ? FontWeight.w700 : FontWeight.normal,
                        color: selected ? Colors.brown.shade700 : null)),
                trailing: selected ? Icon(Icons.check_circle, color: Colors.brown.shade600) : null,
                onTap: () {
                  Navigator.pop(ctx);
                  setState(() => _carrito[index].grind = raw);
                },
              );
            }),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // Convierte contenido+unidad a kg (ej: 250g → 0.25, 1kg → 1.0)
  static double _toKg(num contenido, String unidad) {
    final v = contenido.toDouble();
    return unidad == 'g' ? v / 1000.0 : v;
  }

  // Total kg que el carrito ya tiene para un producto (todas sus presentaciones/grinds)
  double _kgEnCarrito(String codigo) => _carrito
      .where((i) => i.codigo == codigo)
      .fold(0.0, (sum, i) => sum + i.cantidad * i.packSizeKg);

  // Stock total en kg del lote actual para un producto (independiente de presentación)
  double _stockKgForCodigo(String codigo) {
    for (final linea in _lineas) {
      if ((linea.producto['codigo'] as String?) == codigo && linea.presentacion != null) {
        final pres = linea.presentacion!;
        return pres.stock * _toKg(pres.contenido, pres.unidad);
      }
    }
    return double.infinity;
  }

  // Unidades restantes disponibles para una presentación concreta
  // stockKg = stockInicial en kg del lote para este producto
  int _restanteUnidades(String codigo, Presentacion pres) {
    final packKg = _toKg(pres.contenido, pres.unidad);
    final stockKg = pres.stock * packKg;
    final consumidoKg = _kgEnCarrito(codigo);
    final disponibleKg = stockKg - consumidoKg;
    return (disponibleKg / packKg).floor().clamp(-pres.stock, pres.stock);
  }

  void _verificarProximoTostado(String codigo) {
    if (_tieneProximoTostado.containsKey(codigo)) return;
    if (_consultandoStock.contains(codigo)) return;
    _consultandoStock.add(codigo);
    ApiService.getPresentaciones(codigo).then((r) {
      if (!mounted) return;
      final nextKg = r.isSuccess ? (r.data?.nextEventKg ?? 0) : 0.0;
      setState(() {
        _tieneProximoTostado[codigo] = nextKg > 0 && r.data?.nextEventStatus != null;
        _proximoKg[codigo] = nextKg;
        _proximoEventId[codigo] = r.data?.nextEventId;
        _consultandoStock.remove(codigo);
      });
    });
  }

  Future<void> _cargarProductos() async {
    final result = await ApiService.getProductos(limite: 100, estado: 'ACTIVO');
    if (!result.isSuccess) {
      if (mounted) setState(() => _loadingProductos = false);
      return;
    }
    final productos = result.data!.productos;

    // Las presentaciones ya vienen embebidas en cada producto — sin llamadas extra
    final lineas = <_LineaProducto>[];
    for (final producto in productos) {
      final presRaw = producto['presentaciones'] as List<dynamic>? ?? [];
      final presentaciones = presRaw
          .map((pp) => Presentacion.fromMap(pp as Map<String, dynamic>))
          .where((p) => p.id.isNotEmpty)
          .toList();

      if (presentaciones.isEmpty) {
        lineas.add(_LineaProducto(producto: producto, presentacion: null));
      } else {
        for (final p in presentaciones) {
          if (p.molienda.length > 1) {
            // Una fila por tipo de molienda
            for (final g in p.molienda) {
              lineas.add(_LineaProducto(producto: producto, presentacion: p, grind: g));
            }
          } else {
            lineas.add(_LineaProducto(
              producto: producto, presentacion: p,
              grind: p.molienda.isNotEmpty ? p.molienda.first : null,
            ));
          }
        }
      }
    }

    if (mounted) {
      setState(() {
        _productos = productos;
        _lineas = lineas;
        _loadingProductos = false;
      });
    }
  }

  double get _subtotal => _carrito.fold(0, (sum, item) => sum + item.subtotal);
  double get _total => _subtotal + _costoDelivery;

  /// Abre un diálogo para ingresar cantidad directamente.
  /// Si [indexEnCarrito] >= 0 edita ese item; si no, agrega nuevo.
  /// [maxCantidad] limita el valor cuando no hay próximo tostado.
  void _mostrarDialogoCantidad(Map<String, dynamic> producto, {int indexEnCarrito = -1, int? maxCantidad}) {
    final codigo = producto['codigo'] as String;
    final cantidadActual = indexEnCarrito >= 0 ? _carrito[indexEnCarrito].cantidad : 1;
    final ctrl = TextEditingController(text: '$cantidadActual')
      ..selection = TextSelection(baseOffset: 0, extentOffset: '$cantidadActual'.length);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          producto['nombre'] ?? '',
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          decoration: InputDecoration(
            hintText: 'Cantidad',
            filled: true,
            fillColor: Colors.grey.shade100,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
          ),
          onSubmitted: (_) => Navigator.pop(ctx, int.tryParse(ctrl.text)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, int.tryParse(ctrl.text)),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue.shade600, foregroundColor: Colors.white),
            child: const Text('OK'),
          ),
        ],
      ),
    ).then((cantidad) {
      if (cantidad == null || cantidad <= 0) return;
      final cantidadFinal = maxCantidad != null ? cantidad.clamp(1, maxCantidad) : cantidad;
      setState(() {
        if (indexEnCarrito >= 0) {
          _carrito[indexEnCarrito].cantidad = cantidadFinal;
        } else {
          final existente = _carrito.indexWhere((i) => i.codigo == codigo);
          if (existente >= 0) {
            _carrito[existente].cantidad = cantidad;
          } else {
            _carrito.add(_ItemCarrito(
              codigo: codigo,
              nombre: producto['nombre'],
              precioBase: (producto['precio'] ?? 0).toDouble(),
              precioMayor: (producto['precioMayor'] ?? 0).toDouble(),
              cantidadMayor: (producto['cantidadMayor'] ?? 0) as int,
              precioPreferencial: _preciosCliente[producto['presentacionId']?.toString() ?? ''],
              presentacionId: producto['presentacionId'] as String?,
              presentacionLabel: producto['presentacionLabel'] as String?,
              cantidad: cantidadFinal,
            ));
          }
        }
      });
    });
  }

  void _agregarAlCarrito(Map<String, dynamic> producto, {String? presentacionId, String? presentacionLabel, double? precioPresentacion, String? grind, Presentacion? pres}) {
    FocusScope.of(context).unfocus();
    final codigo = producto['codigo'] as String;
    final precioBase = precioPresentacion ?? (producto['precio'] ?? 0).toDouble();
    final precioPreferencial = presentacionId != null ? _preciosCliente[presentacionId] : null;
    final precioMayor = (producto['precioMayor'] ?? 0).toDouble();
    final cantidadMayor = (producto['cantidadMayor'] ?? 0) as int;

    // packSizeKg para calcular stock compartido entre presentaciones del mismo lote
    final presObj = pres ?? _lineas.where((l) => l.presentacion?.id == presentacionId).map((l) => l.presentacion).whereType<Presentacion>().firstOrNull;
    final packKg = presObj != null ? _toKg(presObj.contenido, presObj.unidad) : 1.0;

    final key = presentacionId != null ? '$codigo|$presentacionId|${grind ?? ''}' : codigo;
    final existente = _carrito.indexWhere((i) => i.key == key);
    setState(() {
      if (existente >= 0) {
        _carrito[existente].cantidad++;
      } else {
        _carrito.add(_ItemCarrito(
          codigo: codigo,
          nombre: producto['nombre'],
          precioBase: precioBase,
          precioMayor: precioMayor,
          cantidadMayor: cantidadMayor,
          precioPreferencial: precioPreferencial,
          presentacionId: presentacionId,
          presentacionLabel: presentacionLabel,
          grind: grind,
          cantidad: 1,
          packSizeKg: packKg,
        ));
      }
    });
  }

  void _mostrarSelectorPresentacion(Map<String, dynamic> producto) {
    FocusScope.of(context).unfocus();
    final codigo = producto['codigo'] as String;

    // Presentaciones ya en memoria — sin llamada HTTP
    final presentaciones = _lineas
        .where((l) => l.producto['codigo'] == codigo && l.presentacion != null)
        .map((l) => l.presentacion!)
        .toList();

    if (presentaciones.isEmpty) {
      _agregarAlCarrito(producto);
      return;
    }
    if (presentaciones.length == 1) {
      final p = presentaciones.first;
      final esB2b = _clienteSeleccionado?['esInterno'] == true || _clienteSeleccionado?['esInterno'] == 'true';
      final precio = (esB2b && p.precioB2b != null) ? p.precioB2b! : p.precio;
      if (p.molienda.length > 1) {
        _mostrarSelectorGrind(producto: producto, presentacion: p, precio: precio);
      } else {
        final grind = p.molienda.isNotEmpty ? p.molienda.first : null;
        _agregarAlCarrito(producto, presentacionId: p.id, presentacionLabel: p.etiqueta, precioPresentacion: precio, grind: grind);
      }
      return;
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.symmetric(vertical: 10),
              width: 40, height: 4,
              decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      producto['nombre'] ?? '',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
                ],
              ),
            ),
            const Divider(height: 1),
            ...presentaciones.map((p) {
              final esB2b = _clienteSeleccionado?['esInterno'] == true || _clienteSeleccionado?['esInterno'] == 'true';
              final precio = (esB2b && p.precioB2b != null) ? p.precioB2b! : p.precio;
              final sinStock = p.stock <= 0;
              return Opacity(
                opacity: sinStock ? 0.45 : 1.0,
                child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                leading: p.imageUrl != null && p.imageUrl!.isNotEmpty
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(
                          p.imageUrl!,
                          width: 44, height: 44,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const SizedBox(width: 44),
                        ),
                      )
                    : null,
                title: Text(p.etiqueta, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                subtitle: sinStock
                    ? Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: _Chip(label: 'Sin stock', fg: Colors.red.shade700, bg: Colors.red.shade50),
                      )
                    : null,
                trailing: sinStock
                    ? Icon(Icons.block, color: Colors.red.shade300, size: 22)
                    : Text(
                        'S/ ${precio.toStringAsFixed(2)}',
                        style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green.shade700, fontSize: 15),
                      ),
                onTap: sinStock ? null : () {
                  Navigator.pop(ctx);
                  if (p.molienda.length > 1) {
                    _mostrarSelectorGrind(producto: producto, presentacion: p, precio: precio);
                  } else {
                    final grind = p.molienda.isNotEmpty ? p.molienda.first : null;
                    _agregarAlCarrito(producto, presentacionId: p.id, presentacionLabel: p.etiqueta, precioPresentacion: precio, grind: grind);
                  }
                },
              ),
              );
            }),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  String _grindLabel(String raw) => switch (raw) {
    'ground' => 'Molido',
    'whole'  => 'Grano',
    'green'  => 'Verde',
    _        => raw,
  };

  void _mostrarSelectorGrind({
    required Map<String, dynamic> producto,
    required Presentacion presentacion,
    required double precio,
  }) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.symmetric(vertical: 10),
              width: 40, height: 4,
              decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(
                children: [
                  const Icon(Icons.coffee, color: Colors.brown),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${producto['nombre']} – ${presentacion.etiqueta}',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text('¿Cómo lo quieres?', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                      ],
                    ),
                  ),
                  IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
                ],
              ),
            ),
            const Divider(height: 1),
            ...presentacion.molienda.map((raw) {
              final label = _grindLabel(raw);
              return ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                leading: Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(color: Colors.brown.shade50, borderRadius: BorderRadius.circular(8)),
                  child: Center(child: Icon(Icons.grain, color: Colors.brown.shade400)),
                ),
                title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                onTap: () {
                  Navigator.pop(ctx);
                  _agregarAlCarrito(
                    producto,
                    presentacionId: presentacion.id,
                    presentacionLabel: presentacion.etiqueta,
                    precioPresentacion: precio,
                    grind: raw,
                  );
                },
              );
            }),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  void _quitarDelCarrito(int index) {
    setState(() {
      if (_carrito[index].cantidad > 1) {
        _carrito[index].cantidad--;
      } else {
        _carrito.removeAt(index);
      }
    });
  }

  void _eliminarDelCarrito(int index) {
    setState(() => _carrito.removeAt(index));
  }

  Future<void> _crearPedido() async {
    if (_carrito.isEmpty) {
      _showSnack('Agrega al menos un producto', Colors.orange);
      return;
    }
    if (_whatsappController.text.trim().isEmpty) {
      _showSnack('Ingresa el número de WhatsApp', Colors.orange);
      return;
    }

    setState(() => _isLoading = true);

    // Split items: si hay pre-venta, crear línea regular + línea pre-venta separada
    final Map<String, double> stockKgRestante = {};
    for (final item in _carrito) {
      stockKgRestante.putIfAbsent(item.codigo, () => _stockKgForCodigo(item.codigo));
    }

    final List<Map<String, dynamic>> productos = [];
    for (final item in _carrito) {
      final baseName = item.presentacionLabel != null
          ? '${item.nombre} – ${item.presentacionLabel}'
          : item.nombre;
      final baseMap = {
        'codigo': item.codigo,
        'nombre': baseName,
        'unidad': item.presentacionLabel ?? 'unidad',
        'presentacionId': item.presentacionId,
        if (item.grind != null) 'grind': item.grind,
        'precio': item.precio,
        'packSize': item.packSizeKg,
      };

      final stockKg = stockKgRestante[item.codigo] ?? double.infinity;
      final itemKgTotal = item.cantidad * item.packSizeKg;
      final regularKg = stockKg < itemKgTotal ? stockKg : itemKgTotal;
      // Actualizar stock restante para el próximo item del mismo producto
      stockKgRestante[item.codigo] = (stockKg - regularKg).clamp(0.0, double.infinity);

      final regularUnits = item.packSizeKg > 0 ? (regularKg / item.packSizeKg).floor() : item.cantidad;
      final preVentaUnits = item.cantidad - regularUnits;

      if (regularUnits > 0) {
        productos.add({
          ...baseMap,
          'cantidad': regularUnits,
          'subtotal': item.precio * regularUnits,
        });
      }
      if (preVentaUnits > 0) {
        final eventId = _proximoEventId[item.codigo];
        productos.add({
          ...baseMap,
          'cantidad': preVentaUnits,
          'subtotal': item.precio * preVentaUnits,
          if (eventId != null) 'sourceEventId': eventId,
        });
      }
    }

    // Debug: verificar split de items
    for (final p in productos) {
      debugPrint('📦 item pedido: ${p['nombre']} x${p['cantidad']} sourceEventId=${p['sourceEventId']}');
    }

    final c = _clienteSeleccionado ?? widget.cliente ?? {};
    String _s(dynamic v) => (v ?? '').toString().trim();
    final tipoEnvio = _s(c['tipoEnvio']).toUpperCase();
    final telefono  = _s(c['telefono']);

    // Ciudad y departamento según tipo de envío
    String departamento;
    String ciudad;
    if (tipoEnvio == 'NACIONAL') {
      departamento = _s(c['departamentoEnvio']).isNotEmpty ? _s(c['departamentoEnvio']) : _s(c['departamento']);
      ciudad       = _s(c['distritoEnvio']).isNotEmpty    ? _s(c['distritoEnvio'])      : (_s(c['distrito']).isNotEmpty ? _s(c['distrito']) : _s(c['ciudad']));
    } else {
      // LOCAL y SEDE usan los datos de ubicación estándar del cliente
      departamento = _s(c['departamento']);
      ciudad       = _s(c['distrito']).isNotEmpty ? _s(c['distrito']) : _s(c['ciudad']);
    }

    // Empresa courier → col N del spreadsheet (empresaEnvio)
    final empresaEnvio = tipoEnvio == 'NACIONAL' ? _s(c['empresaEnvio']) : null;

    final esInterno = c['esInterno'] == true || c['esInterno'] == 'true';

    final result = await ApiService.crearPedido(
      whatsapp: _whatsappController.text.trim(),
      cliente: _clienteController.text.trim(),
      telefono: telefono.isNotEmpty ? telefono : null,
      direccion: _direccionController.text.trim(),
      ciudad: ciudad.isNotEmpty ? ciudad : null,
      departamento: departamento.isNotEmpty ? departamento : null,
      productos: productos,
      total: _total,
      costoEnvio: _costoDelivery,
      observaciones: _observacionesController.text.trim(),
      tipoEnvio: tipoEnvio.isNotEmpty ? tipoEnvio : null,
      empresaEnvio: (empresaEnvio != null && empresaEnvio.isNotEmpty) ? empresaEnvio : null,
      estadoPago: esInterno ? 'NO_APLICA' : null,
      notificarCliente: _notificarCliente,
    );

    setState(() => _isLoading = false);

    if (result.isSuccess && mounted) {
      final nuevoPedido = result.data?['pedido'] as Map<String, dynamic>?;
      // Volver al tab de pedidos — el padre abre el detalle con _mostrarDetallePedido
      Navigator.pop(context, nuevoPedido);
    } else {
      _showSnack('Error: ${result.error}', Colors.red);
    }
  }

  void _showSnack(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: color),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isWideScreen = screenWidth > 600; // Tablet o pantalla grande

    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: const Text('Nuevo Pedido'),
        backgroundColor: Colors.blue.shade600,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.add_box_outlined),
            tooltip: 'Crear producto',
            onPressed: _mostrarDialogoCrearProducto,
          ),
        ],
        bottom: !isWideScreen ? TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: [
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Icon(Icons.inventory_2, size: 18),
                  SizedBox(width: 5),
                  Text('Productos', style: TextStyle(fontSize: 12)),
                ],
              ),
            ),
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Badge(
                    label: Text('${_carrito.length}'),
                    isLabelVisible: _carrito.isNotEmpty,
                    child: const Icon(Icons.shopping_cart, size: 18),
                  ),
                  const SizedBox(width: 5),
                  const Text('Carrito', style: TextStyle(fontSize: 12)),
                ],
              ),
            ),
          ],
        ) : null,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : isWideScreen
              ? _buildWideLayout()
              : _buildMobileLayout(),
    );
  }

  /// Layout para tablets y pantallas grandes (lado a lado)
  Widget _buildWideLayout() {
    return Column(
      children: [
        _buildDatosCliente(),
        Expanded(
          child: Row(
            children: [
              Expanded(flex: 3, child: _buildListaProductos()),
              Expanded(flex: 2, child: _buildCarrito()),
            ],
          ),
        ),
      ],
    );
  }

  /// Layout para móviles (con tabs)
  Widget _buildMobileLayout() {
    return Column(
      children: [
        _buildDatosCliente(),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildListaProductos(),
              _buildCarritoMobile(),
            ],
          ),
        ),
        // Barra inferior con total y botón (siempre visible en móvil)
        _buildBottomBar(),
      ],
    );
  }

  Widget _buildDatosCliente() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      color: Colors.white,
      child: Column(
        children: [
          _buildClienteField(),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(child: _buildWhatsappField()),
              const SizedBox(width: 6),
              Expanded(child: _buildDireccionField()),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildClienteField() {
    final nombre = _clienteController.text.isNotEmpty
        ? _clienteController.text
        : (_clienteSeleccionado != null
            ? (_clienteSeleccionado!['nombreNegocio'] ?? _clienteSeleccionado!['nombreResponsable'] ?? _clienteSeleccionado!['nombre'] ?? '').toString()
            : '');
    return GestureDetector(
      onTap: _abrirSelectorCliente,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(Icons.person, size: 20, color: Colors.grey.shade600),
            const SizedBox(width: 8),
            Expanded(
              child: nombre.isNotEmpty
                  ? Text(nombre, style: const TextStyle(fontSize: 14))
                  : Text('Seleccionar cliente', style: TextStyle(color: Colors.grey.shade400, fontSize: 14)),
            ),
            Icon(Icons.arrow_drop_down, color: Colors.grey.shade600),
          ],
        ),
      ),
    );
  }

  void _abrirSelectorCliente() {
    String busqueda = '';
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            final filtrados = busqueda.isEmpty
                ? _clientes
                : _clientes.where((c) {
                    final q = busqueda.toLowerCase();
                    return (c['nombreNegocio'] ?? '').toString().toLowerCase().contains(q) ||
                           (c['nombreResponsable'] ?? '').toString().toLowerCase().contains(q) ||
                           (c['nombre'] ?? '').toString().toLowerCase().contains(q) ||
                           (c['whatsapp'] ?? '').toString().contains(q);
                  }).toList();

            return DraggableScrollableSheet(
              initialChildSize: 0.75,
              maxChildSize: 0.95,
              minChildSize: 0.4,
              expand: false,
              builder: (_, scrollCtrl) => Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                ),
                child: Column(
                  children: [
                    Container(
                      margin: const EdgeInsets.symmetric(vertical: 10),
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          const Text('Seleccionar cliente', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          const Spacer(),
                          IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: TextField(
                        autofocus: true,
                        onChanged: (v) => setModalState(() => busqueda = v),
                        decoration: InputDecoration(
                          hintText: 'Buscar cliente...',
                          prefixIcon: const Icon(Icons.search),
                          filled: true,
                          fillColor: Colors.grey.shade100,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        ),
                      ),
                    ),
                    Expanded(
                      child: _loadingClientes
                          ? const Center(child: CircularProgressIndicator())
                          : filtrados.isEmpty
                              ? Center(child: Text('Sin resultados', style: TextStyle(color: Colors.grey.shade500)))
                              : ListView.builder(
                                  controller: scrollCtrl,
                                  itemCount: filtrados.length,
                                  itemBuilder: (_, i) {
                                    final c = filtrados[i];
                                    final nombre = (c['nombreNegocio']?.toString().isNotEmpty == true
                                        ? c['nombreNegocio']
                                        : c['nombreResponsable']?.toString().isNotEmpty == true
                                            ? c['nombreResponsable']
                                            : c['nombre']?.toString().isNotEmpty == true
                                                ? c['nombre']
                                                : c['whatsapp']?.toString().isNotEmpty == true
                                                    ? c['whatsapp']
                                                    : c['telefono'] ?? '').toString();
                                    final ws = (c['whatsapp'] ?? '').toString();
                                    final telefono = (c['telefono'] ?? '').toString();
                                    final direccion = _construirDireccionEnvio(c);
                                    final tipoEnvio = (c['tipoEnvio'] ?? '').toString().toUpperCase();
                                    return ListTile(
                                      leading: CircleAvatar(
                                        backgroundColor: Colors.blue.shade50,
                                        child: Text(
                                          nombre.isNotEmpty ? nombre[0].toUpperCase() : '?',
                                          style: TextStyle(color: Colors.blue.shade700, fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                      title: Text(nombre, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                                      subtitle: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          if (ws.isNotEmpty || telefono.isNotEmpty)
                                            Text(
                                              ws.isNotEmpty ? ws : telefono,
                                              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                                            ),
                                          if (direccion.isNotEmpty)
                                            Text(
                                              direccion,
                                              style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                        ],
                                      ),
                                      isThreeLine: direccion.isNotEmpty,
                                      trailing: tipoEnvio.isNotEmpty
                                          ? Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: Colors.blue.shade50,
                                                borderRadius: BorderRadius.circular(6),
                                              ),
                                              child: Text(tipoEnvio, style: TextStyle(fontSize: 10, color: Colors.blue.shade700)),
                                            )
                                          : null,
                                      onTap: () {
                                        Navigator.pop(ctx);
                                        _seleccionarCliente(c);
                                      },
                                    );
                                  },
                                ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _seleccionarCliente(Map<String, dynamic> cliente) {
    setState(() {
      _clienteSeleccionado = cliente;
    });
    // Auto-rellenar campos
    final nombre = (cliente['nombreNegocio']?.toString().isNotEmpty == true
        ? cliente['nombreNegocio']
        : cliente['nombreResponsable']?.toString().isNotEmpty == true
            ? cliente['nombreResponsable']
            : cliente['nombre']?.toString().isNotEmpty == true
                ? cliente['nombre']
                : cliente['whatsapp']?.toString().isNotEmpty == true
                    ? cliente['whatsapp']
                    : cliente['telefono'] ?? '').toString();
    _clienteController.text = nombre;
    _whatsappController.text = (cliente['whatsapp'] ?? '').toString();
    _direccionController.text = _construirDireccionEnvio(cliente);
    _autocompletarObservaciones(cliente);
    // Cargar precios personalizados si tiene id
    final clienteId = (cliente['id'] ?? '').toString();
    if (clienteId.isNotEmpty) {
      _cargarPreciosCliente(clienteId);
    }
  }

  Widget _buildWhatsappField() {
    return TextField(
      controller: _whatsappController,
      keyboardType: TextInputType.phone,
      style: const TextStyle(fontSize: 13),
      decoration: InputDecoration(
        hintText: 'WhatsApp',
        hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
        prefixIcon: const Icon(Icons.phone, size: 18),
        filled: true,
        fillColor: Colors.grey.shade50,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
        isDense: true,
      ),
    );
  }

  Widget _buildDireccionField() {
    return TextField(
      controller: _direccionController,
      style: const TextStyle(fontSize: 13),
      decoration: InputDecoration(
        hintText: 'Dirección',
        hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
        prefixIcon: const Icon(Icons.location_on, size: 18),
        filled: true,
        fillColor: Colors.grey.shade50,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
        isDense: true,
      ),
    );
  }

  Future<void> _mostrarDialogoCrearProducto() async {
    final ctrl = TextEditingController();
    final nombre = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nuevo producto', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            hintText: 'Nombre del producto',
            filled: true,
            fillColor: Colors.grey.shade100,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue.shade600, foregroundColor: Colors.white),
            child: const Text('Crear'),
          ),
        ],
      ),
    );

    if (nombre == null || nombre.isEmpty) return;

    final result = await ApiService.crearProducto(nombre: nombre);
    if (!mounted) return;

    if (result.isSuccess) {
      _showSnack('Producto "$nombre" creado', Colors.green);
      await _cargarProductos();
    } else {
      _showSnack('Error: ${result.error}', Colors.red);
    }
  }

  Widget _buildListaProductos() {
    final q = (_busqueda ?? '').toLowerCase();
    final lineasFiltradas = q.isEmpty
        ? _lineas
        : _lineas.where((l) =>
            (l.producto['nombre'] ?? '').toLowerCase().contains(q) ||
            (l.producto['codigo'] ?? '').toLowerCase().contains(q) ||
            (l.presentacion?.etiqueta ?? '').toLowerCase().contains(q),
          ).toList();

    return Container(
      margin: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          // Lista de líneas (una por presentación)
          Expanded(
            child: _loadingProductos
                ? const Center(child: CircularProgressIndicator())
                : lineasFiltradas.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.inventory_2_outlined, size: 48, color: Colors.grey.shade300),
                            const SizedBox(height: 8),
                            Text('No hay productos', style: TextStyle(color: Colors.grey.shade500)),
                          ],
                        ),
                      )
                    : GestureDetector(
                        onTap: () => FocusScope.of(context).unfocus(),
                        behavior: HitTestBehavior.translucent,
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          itemCount: lineasFiltradas.length,
                          itemBuilder: (context, index) {
                            final linea = lineasFiltradas[index];
                            final p = linea.producto;
                            final pres = linea.presentacion;
                            final grindLinea = linea.grind;
                            final codigo = p['codigo'] as String;
                            // Key única por presentación + grind
                            final lineaKey = pres != null
                                ? '$codigo|${pres.id}|${grindLinea ?? ''}'
                                : codigo;

                            final esB2b = _clienteSeleccionado?['esInterno'] == true ||
                                _clienteSeleccionado?['esInterno'] == 'true';
                            final precioPreferencial = pres != null ? _preciosCliente[pres.id] : null;
                            final precio = precioPreferencial ??
                                (pres != null
                                    ? (esB2b && pres.precioB2b != null ? pres.precioB2b! : pres.precio)
                                    : (p['precio'] ?? 0).toDouble());
                            final tienePreferencial = precioPreferencial != null;

                            final cantidadEnLinea = _carrito
                                .where((i) => i.key == lineaKey)
                                .fold(0, (sum, i) => sum + i.cantidad);
                            final idxEnCarrito = _carrito.indexWhere((i) => i.key == lineaKey);

                            // Out-of-stock check — stock compartido entre presentaciones del mismo lote
                            final sinStock = pres != null && pres.stock <= 0;
                            final restanteActual = pres != null ? _restanteUnidades(codigo, pres) : 0;
                            final bloqueadoPorStock = !sinStock &&
                                pres != null && pres.stock > 0 &&
                                restanteActual < 0 &&
                                (_consultandoStock.contains(codigo) ||
                                 _tieneProximoTostado[codigo] == false);


                            return Opacity(
                              opacity: sinStock ? 0.45 : 1.0,
                              child: Card(
                              margin: const EdgeInsets.only(bottom: 6),
                              child: ListTile(
                                dense: true,
                                leading: Builder(builder: (context) {
                                  // Only use the presentation-specific image; never fall back to product cover
                                  final imgUrl = pres?.imageUrl?.isNotEmpty == true ? pres!.imageUrl! : null;
                                  return Container(
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(
                                      color: Colors.blue.shade50,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: imgUrl != null
                                        ? ClipRRect(
                                            borderRadius: BorderRadius.circular(8),
                                            child: Image.network(
                                              imgUrl,
                                              fit: BoxFit.cover,
                                              errorBuilder: (_, __, ___) =>
                                                  Icon(Icons.inventory_2, color: Colors.blue.shade300),
                                            ),
                                          )
                                        : Icon(Icons.inventory_2, color: Colors.blue.shade300),
                                  );
                                }),
                                title: Text(
                                  p['nombre'] ?? '',
                                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Wrap(
                                    spacing: 4,
                                    runSpacing: 4,
                                    crossAxisAlignment: WrapCrossAlignment.center,
                                    children: [
                                      if (pres != null)
                                        _Chip(label: pres.etiqueta, fg: Colors.blue.shade700, bg: Colors.blue.shade50),
                                      if (grindLinea != null)
                                        _Chip(label: _grindLabel(grindLinea), fg: Colors.brown.shade700, bg: Colors.brown.shade50),
                                      _Chip(
                                        label: tienePreferencial
                                            ? 'S/ ${precio.toStringAsFixed(2)} ★'
                                            : 'S/ ${precio.toStringAsFixed(2)}',
                                        fg: tienePreferencial ? Colors.purple.shade700 : Colors.green.shade700,
                                        bg: tienePreferencial ? Colors.purple.shade50 : Colors.green.shade50,
                                      ),
                                      if (!sinStock && pres != null && pres.stock > 0)
                                        Builder(builder: (_) {
                                          final restante = restanteActual;
                                          if (restante >= 0) {
                                            return _Chip(
                                              label: '$restante disp.',
                                              fg: Colors.grey.shade600,
                                              bg: Colors.grey.shade100,
                                            );
                                          }
                                          _verificarProximoTostado(codigo); // solo se llama cuando restante < 0
                                          if (_consultandoStock.contains(codigo)) {
                                            return Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                SizedBox(
                                                  width: 10, height: 10,
                                                  child: CircularProgressIndicator(
                                                    strokeWidth: 1.5,
                                                    color: Colors.orange.shade400,
                                                  ),
                                                ),
                                                const SizedBox(width: 4),
                                                Text('pre-venta...',
                                                    style: TextStyle(fontSize: 11, color: Colors.orange.shade400)),
                                              ],
                                            );
                                          }
                                          final tieneProximo = _tieneProximoTostado[codigo] == true;
                                          if (!tieneProximo) return const SizedBox.shrink();
                                          final nextKg = _proximoKg[codigo] ?? 0;
                                          final packKg = pres != null ? _toKg(pres.contenido, pres.unidad) : 1.0;
                                          // Cuánto kg del carrito ya excede el stock actual (está en pre-venta)
                                          final stockKg = (pres?.stock ?? 0) * packKg;
                                          final totalCarritoKg = _kgEnCarrito(codigo);
                                          final kgEnPreventa = (totalCarritoKg - stockKg).clamp(0, double.infinity);
                                          final disponibleNextKg = (nextKg - kgEnPreventa).clamp(0, nextKg);
                                          final libresNextEvent = (disponibleNextKg / packKg).floor();
                                          final pLabel = libresNextEvent > 0 ? '$libresNextEvent disp.' : 'agotado';
                                          return _Chip(
                                            label: 'pre-venta · $pLabel',
                                            fg: libresNextEvent > 0 ? Colors.orange.shade700 : Colors.red.shade700,
                                            bg: libresNextEvent > 0 ? Colors.orange.shade50 : Colors.red.shade50,
                                          );
                                        }),
                                      if (sinStock)
                                        _Chip(label: 'Sin stock', fg: Colors.red.shade700, bg: Colors.red.shade50),
                                    ],
                                  ),
                                ),
                                trailing: sinStock
                                    ? Icon(Icons.block, color: Colors.red.shade300, size: 26)
                                    : cantidadEnLinea > 0
                                    ? Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          InkWell(
                                            onTap: () {
                                              if (idxEnCarrito >= 0) _quitarDelCarrito(idxEnCarrito);
                                            },
                                            borderRadius: BorderRadius.circular(20),
                                            child: Padding(
                                              padding: const EdgeInsets.all(4),
                                              child: Icon(Icons.remove_circle, color: Colors.red.shade400, size: 28),
                                            ),
                                          ),
                                          GestureDetector(
                                            onTap: () => _mostrarDialogoCantidad(
                                              p,
                                              indexEnCarrito: idxEnCarrito,
                                            ),
                                            child: Container(
                                              constraints: const BoxConstraints(minWidth: 32),
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                              decoration: BoxDecoration(
                                                color: Colors.blue.shade100,
                                                borderRadius: BorderRadius.circular(8),
                                              ),
                                              child: Text(
                                                '$cantidadEnLinea',
                                                textAlign: TextAlign.center,
                                                style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue.shade700, fontSize: 14),
                                              ),
                                            ),
                                          ),
                                          InkWell(
                                            onTap: bloqueadoPorStock ? null : () => _agregarAlCarrito(p,
                                                presentacionId: pres?.id,
                                                presentacionLabel: pres?.etiqueta,
                                                precioPresentacion: precio,
                                                grind: grindLinea),
                                            borderRadius: BorderRadius.circular(20),
                                            child: Padding(
                                              padding: const EdgeInsets.all(4),
                                              child: Icon(Icons.add_circle,
                                                  color: bloqueadoPorStock ? Colors.grey.shade300 : Colors.blue.shade600,
                                                  size: 28),
                                            ),
                                          ),
                                        ],
                                      )
                                    : IconButton(
                                        icon: Icon(Icons.add_circle,
                                            color: bloqueadoPorStock ? Colors.grey.shade300 : Colors.blue.shade600,
                                            size: 28),
                                        onPressed: bloqueadoPorStock ? null : () => _agregarAlCarrito(p,
                                            presentacionId: pres?.id,
                                            presentacionLabel: pres?.etiqueta,
                                            precioPresentacion: precio,
                                            grind: grindLinea),
                                      ),
                              ),
                            ), // Card
                            ); // Opacity
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  /// Carrito para pantallas grandes (con todo incluido)
  Widget _buildCarrito() {
    return Container(
      margin: const EdgeInsets.fromLTRB(0, 8, 8, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          // Header
          _buildCarritoHeader(),
          // Items
          Expanded(child: _buildCarritoItems()),
          // Delivery
          _buildDeliveryRow(),
          // Observaciones
          _buildObservaciones(),
          // Total y botón
          _buildCarritoFooter(),
        ],
      ),
    );
  }

  /// Carrito para móviles (ocupa toda la pantalla)
  Widget _buildCarritoMobile() {
    return Container(
      margin: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Expanded(child: _buildCarritoItems()),
          _buildDeliveryRow(),
          _buildObservaciones(),
        ],
      ),
    );
  }

  Widget _buildCarritoHeader() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
      ),
      child: Row(
        children: [
          Icon(Icons.shopping_cart, color: Colors.blue.shade700),
          const SizedBox(width: 8),
          Text(
            'Carrito (${_carrito.length})',
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue.shade700),
          ),
          const Spacer(),
          if (_carrito.isNotEmpty)
            TextButton(
              onPressed: () {
                setState(() => _carrito.clear());
              },
              child: Text('Limpiar', style: TextStyle(color: Colors.red.shade400, fontSize: 12)),
            ),
        ],
      ),
    );
  }

  Widget _buildCarritoItems() {
    if (_carrito.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.shopping_cart_outlined, size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            Text('Carrito vacío', style: TextStyle(color: Colors.grey.shade500, fontSize: 16)),
            const SizedBox(height: 4),
            Text('Agrega productos desde la lista', style: TextStyle(color: Colors.grey.shade400, fontSize: 12)),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: _carrito.length,
      itemBuilder: (context, index) {
        final item = _carrito[index];

        // Buscar presentación para saber stock y molienda disponibles
        final lineaPres = _lineas.where(
          (l) => l.presentacion?.id == item.presentacionId,
        ).map((l) => l.presentacion).whereType<Presentacion>().firstOrNull;
        final stockMax = lineaPres?.stock ?? double.infinity;
        final tieneProximo = _tieneProximoTostado[item.codigo] == true;
        final puedeSumar = item.cantidad < stockMax || tieneProximo;
        final grindMostrar = item.grind;

        return Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Nombre + etiquetas
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.nombre,
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Wrap(
                          spacing: 4,
                          runSpacing: 2,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            if (item.presentacionLabel != null)
                              Text(
                                item.presentacionLabel!,
                                style: TextStyle(fontSize: 12, color: Colors.blue.shade600, fontWeight: FontWeight.w500),
                              ),
                            if (grindMostrar != null)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                decoration: BoxDecoration(
                                  color: Colors.brown.shade50,
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: Colors.brown.shade200),
                                ),
                                child: Text(
                                  _grindLabel(grindMostrar),
                                  style: TextStyle(fontSize: 11, color: Colors.brown.shade700, fontWeight: FontWeight.w500),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.delete_outline, size: 20, color: Colors.red.shade400),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () => _eliminarDelCarrito(index),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  Text(
                    'S/ ${item.precio.toStringAsFixed(2)} c/u',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                  if (item.aplicaPrecioMayor) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: Colors.orange.shade100, borderRadius: BorderRadius.circular(4)),
                      child: Text('Por mayor', style: TextStyle(fontSize: 10, color: Colors.orange.shade800, fontWeight: FontWeight.w600)),
                    ),
                  ],
                  if (item.precioPreferencial != null) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: Colors.purple.shade50, borderRadius: BorderRadius.circular(4)),
                      child: Text('Preferencial', style: TextStyle(fontSize: 10, color: Colors.purple.shade700, fontWeight: FontWeight.w600)),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 6),
              // Controles de cantidad y subtotal
              Row(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.remove, size: 18),
                          padding: const EdgeInsets.all(4),
                          constraints: const BoxConstraints(),
                          onPressed: () => _quitarDelCarrito(index),
                        ),
                        GestureDetector(
                          onTap: () {
                            final prod = {
                              'codigo': item.codigo,
                              'nombre': item.nombre,
                              'precio': item.precio,
                            };
                            _mostrarDialogoCantidad(prod,
                                indexEnCarrito: index,
                                maxCantidad: tieneProximo ? null : stockMax.isFinite ? stockMax.toInt() : null);
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.blue.shade50,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '${item.cantidad}',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.blue.shade700),
                            ),
                          ),
                        ),
                        IconButton(
                          icon: Icon(Icons.add, size: 18,
                              color: puedeSumar ? null : Colors.grey.shade300),
                          padding: const EdgeInsets.all(4),
                          constraints: const BoxConstraints(),
                          onPressed: puedeSumar ? () => setState(() => item.cantidad++) : null,
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  Text(
                    'S/ ${item.subtotal.toStringAsFixed(2)}',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.green.shade700),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDeliveryRow() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.blue.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.blue.shade100),
        ),
        child: Row(
          children: [
            Icon(Icons.local_shipping_outlined, size: 18, color: Colors.blue.shade600),
            const SizedBox(width: 8),
            Text('Delivery',
                style: TextStyle(fontSize: 13, color: Colors.blue.shade700, fontWeight: FontWeight.w500)),
            const Spacer(),
            Text('S/ ', style: TextStyle(fontSize: 13, color: Colors.blue.shade700, fontWeight: FontWeight.w500)),
            SizedBox(
              width: 72,
              child: TextField(
                controller: _deliveryController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                textAlign: TextAlign.right,
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.blue.shade700),
                decoration: InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  hintText: '0.00',
                  hintStyle: TextStyle(color: Colors.blue.shade300),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                ),
                onChanged: (v) => setState(() => _costoDelivery = double.tryParse(v) ?? 0),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildObservaciones() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 2, 8, 4),
      child: TextField(
        controller: _observacionesController,
        minLines: 1,
        maxLines: 2,
        decoration: InputDecoration(
          hintText: 'Observaciones...',
          hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 12),
          filled: true,
          fillColor: Colors.grey.shade50,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          isDense: true,
        ),
      ),
    );
  }

  /// Footer del carrito para pantallas grandes
  Widget _buildCarritoFooter() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('TOTAL:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              Text(
                'S/ ${_total.toStringAsFixed(2)}',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: Colors.green.shade700),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              SizedBox(
                width: 24,
                height: 24,
                child: Checkbox(
                  value: _notificarCliente,
                  onChanged: (v) => setState(() => _notificarCliente = v ?? true),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
              const SizedBox(width: 8),
              const Expanded(child: Text('Notificar por WhatsApp', style: TextStyle(fontSize: 12))),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _carrito.isEmpty ? null : _crearPedido,
              icon: const Icon(Icons.check),
              label: const Text('Crear Pedido'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green.shade600,
                foregroundColor: Colors.white,
                disabledBackgroundColor: Colors.grey.shade300,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Barra inferior para móviles (siempre visible)
  Widget _buildBottomBar() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: Checkbox(
                    value: _notificarCliente,
                    onChanged: (v) => setState(() => _notificarCliente = v ?? true),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
                const SizedBox(width: 8),
                const Text('Notificar por WhatsApp', style: TextStyle(fontSize: 12)),
                const Spacer(),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('Total:', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                    Text(
                      'S/ ${_total.toStringAsFixed(2)}',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: Colors.green.shade700),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _carrito.isEmpty ? null : _crearPedido,
                icon: const Icon(Icons.check_circle),
                label: Text(_carrito.isEmpty ? 'Agrega productos' : 'Crear Pedido (${_carrito.length})'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green.shade600,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.grey.shade300,
                  disabledForegroundColor: Colors.grey.shade500,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    _clienteController.dispose();
    _whatsappController.dispose();
    _direccionController.dispose();
    _observacionesController.dispose();
    _deliveryController.dispose();
    super.dispose();
  }
}

class _ItemCarrito {
  final String codigo;
  final String nombre;
  final double precioBase;
  final double precioMayor;
  final int cantidadMayor;
  final double? precioPreferencial;
  final String? presentacionId;
  final String? presentacionLabel;
  String? grind;
  int cantidad;
  final double packSizeKg; // tamaño del pack en kg para calcular stock compartido

  _ItemCarrito({
    required this.codigo,
    required this.nombre,
    required this.precioBase,
    this.precioMayor = 0,
    this.cantidadMayor = 0,
    this.precioPreferencial,
    this.presentacionId,
    this.presentacionLabel,
    this.grind,
    required this.cantidad,
    this.packSizeKg = 1.0,
  });

  String get key => presentacionId != null ? '$codigo|$presentacionId|${grind ?? ''}' : codigo;

  double get precio {
    if (precioPreferencial != null) return precioPreferencial!;
    if (precioMayor > 0 && cantidadMayor > 0 && cantidad >= cantidadMayor) return precioMayor;
    return precioBase;
  }

  bool get aplicaPrecioMayor =>
      precioPreferencial == null && precioMayor > 0 && cantidadMayor > 0 && cantidad >= cantidadMayor;

  double get subtotal => precio * cantidad;
}

class _LineaProducto {
  final Map<String, dynamic> producto;
  final Presentacion? presentacion;
  final String? grind;

  const _LineaProducto({required this.producto, required this.presentacion, this.grind});
}

class _Chip extends StatelessWidget {
  final String label;
  final Color fg;
  final Color bg;
  const _Chip({required this.label, required this.fg, required this.bg});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(4)),
      child: Text(label, style: TextStyle(fontSize: 11, color: fg, fontWeight: FontWeight.w600)),
    );
  }
}
