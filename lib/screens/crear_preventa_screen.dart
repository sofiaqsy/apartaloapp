import 'package:flutter/material.dart';
import '../services/api_service.dart';

class CrearPreventaScreen extends StatefulWidget {
  final Map<String, dynamic>? cliente;
  const CrearPreventaScreen({super.key, this.cliente});

  @override
  State<CrearPreventaScreen> createState() => _CrearPreventaScreenState();
}

class _CrearPreventaScreenState extends State<CrearPreventaScreen>
    with SingleTickerProviderStateMixin {

  // ── Estado general ─────────────────────────────────────────────────────────
  bool _isLoading = false;
  bool _loadingProductos = true;
  bool _loadingEventos = true;
  List<_LineaProducto> _lineasCatalogo = [];
  List<_LineaProducto> _lineasEvento = [];
  final List<_ItemCarrito> _carrito = [];

  // ── Cliente ────────────────────────────────────────────────────────────────
  Map<String, dynamic>? _clienteSeleccionado;
  List<Map<String, dynamic>> _clientes = [];
  bool _loadingClientes = false;
  late TextEditingController _clienteController;
  late TextEditingController _whatsappController;
  late TextEditingController _direccionController;
  late TextEditingController _observacionesController;
  bool _notificarCliente = false;

  // ── Delivery ───────────────────────────────────────────────────────────────
  double _costoDelivery = 0;
  late TextEditingController _deliveryController;

  // ── Tabs ───────────────────────────────────────────────────────────────────
  late TabController _tabController;

  // ── Precios personalizados ─────────────────────────────────────────────────
  Map<String, double> _preciosCliente = {};

  // ── Eventos ────────────────────────────────────────────────────────────────
  List<Map<String, dynamic>> _eventos = [];
  Map<String, dynamic>? _eventoSeleccionado;

  // ── Computed ───────────────────────────────────────────────────────────────
  List<_LineaProducto> get _lineas =>
      _eventoSeleccionado != null ? _lineasEvento : _lineasCatalogo;

  // ── Totales ────────────────────────────────────────────────────────────────
  double get _subtotal => _carrito.fold(0, (sum, item) => sum + item.subtotal);
  double get _total    => _subtotal + _costoDelivery;

  // ══════════════════════════════════════════════════════════════════════════
  // Lifecycle
  // ══════════════════════════════════════════════════════════════════════════

  @override
  void initState() {
    super.initState();
    _tabController      = TabController(length: 2, vsync: this);
    _deliveryController = TextEditingController(text: '0');
    _initDatosCliente();
    _cargarDatos();
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

  // ══════════════════════════════════════════════════════════════════════════
  // Carga de datos
  // ══════════════════════════════════════════════════════════════════════════

  Future<void> _cargarDatos() async {
    final clienteId = widget.cliente?['id'] as String?;
    await Future.wait([
      _cargarProductos(),
      _cargarClientes(),
      _cargarEventos(),
      if (clienteId != null && clienteId.isNotEmpty)
        _cargarPreciosCliente(clienteId),
    ]);
    // Auto-seleccionar el próximo tueste al cargar
    if (mounted && _eventos.isNotEmpty) {
      final proximo = _proximoEvento();
      if (proximo != null && _eventoSeleccionado == null) {
        setState(() {
          _eventoSeleccionado = proximo;
          _reconstruirLineasEvento();
        });
      }
    }
  }

  Future<void> _cargarClientes() async {
    setState(() => _loadingClientes = true);
    final result = await ApiService.getClientes();
    if (mounted) {
      setState(() {
        _clientes        = result.isSuccess ? (result.data ?? []) : [];
        _loadingClientes = false;
      });
    }
  }

  Future<void> _cargarPreciosCliente(String clienteId) async {
    final result = await ApiService.getPreciosCliente(clienteId: clienteId);
    if (result.isSuccess && result.data != null) {
      setState(() {
        _preciosCliente = result.data!;
        // Actualizar items ya en carrito con el precio personalizado del cliente
        for (int i = 0; i < _carrito.length; i++) {
          final item = _carrito[i];
          final nuevoPrecio = item.presentacionId != null
              ? _preciosCliente[item.presentacionId]
              : null;
          if (nuevoPrecio != item.precioPreferencial) {
            _carrito[i] = _ItemCarrito(
              codigo:             item.codigo,
              nombre:             item.nombre,
              precioBase:         item.precioBase,
              precioMayor:        item.precioMayor,
              cantidadMayor:      item.cantidadMayor,
              precioPreferencial: nuevoPrecio,
              presentacionId:     item.presentacionId,
              presentacionLabel:  item.presentacionLabel,
              grind:              item.grind,
              imageUrl:           item.imageUrl,
              cantidad:           item.cantidad,
            );
          }
        }
        if (_eventoSeleccionado != null) _reconstruirLineasEvento();
      });
    }
  }

  Future<void> _cargarProductos() async {
    final result = await ApiService.getProductos(limite: 100, estado: 'ACTIVO');
    if (!result.isSuccess) {
      if (mounted) setState(() => _loadingProductos = false);
      return;
    }
    final productos = result.data!.productos;
    final lineas    = <_LineaProducto>[];
    for (final producto in productos) {
      final presRaw       = producto['presentaciones'] as List<dynamic>? ?? [];
      final presentaciones = presRaw
          .map((pp) => Presentacion.fromMap(pp as Map<String, dynamic>))
          .where((p) => p.id.isNotEmpty)
          .toList();
      if (presentaciones.isEmpty) {
        lineas.add(_LineaProducto(producto: producto, presentacion: null));
      } else {
        for (final p in presentaciones) {
          if (p.molienda.length > 1) {
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
        _lineasCatalogo  = lineas;
        _loadingProductos = false;
      });
    }
  }

  Future<void> _cargarEventos() async {
    final res = await ApiService.getEventosPreventas();
    if (!mounted) return;
    setState(() {
      _loadingEventos = false;
      if (res.isSuccess) _eventos = res.data ?? [];
    });
  }

  // ══════════════════════════════════════════════════════════════════════════
  // Lógica de eventos
  // ══════════════════════════════════════════════════════════════════════════

  /// Devuelve el evento más próximo con fecha futura, o el último si no hay.
  Map<String, dynamic>? _proximoEvento() {
    if (_eventos.isEmpty) return null;
    final now    = DateTime.now();
    final sorted = [..._eventos]..sort((a, b) {
        final da = DateTime.tryParse(a['roasted_at']?.toString() ?? '') ?? DateTime(2100);
        final db = DateTime.tryParse(b['roasted_at']?.toString() ?? '') ?? DateTime(2100);
        return da.compareTo(db);
      });
    return sorted.firstWhere(
      (ev) {
        final dt = DateTime.tryParse(ev['roasted_at']?.toString() ?? '');
        return dt != null && dt.isAfter(now);
      },
      orElse: () => sorted.last,
    );
  }

  /// Construye _lineasEvento desde el evento seleccionado.
  void _reconstruirLineasEvento() {
    if (_eventoSeleccionado == null) { _lineasEvento = []; return; }

    final lineas = <_LineaProducto>[];
    final offers = List<Map<String, dynamic>>.from(
        _eventoSeleccionado!['event_offers'] ?? []);

    for (final offer in offers) {
      final product = offer['product'] as Map<String, dynamic>?;
      if (product == null) continue;

      final productMap = <String, dynamic>{
        'id':            product['id'],
        'codigo':        product['id']?.toString() ?? '',
        'nombre':        product['name'] ?? '',
        'precio':        0.0,
        'precioMayor':   0.0,
        'cantidadMayor': 0,
      };

      final rawPres = List<Map<String, dynamic>>.from(
          product['product_presentations'] ?? []);
      rawPres.sort((a, b) => (a['sort_order'] ?? 0).compareTo(b['sort_order'] ?? 0));
      final visibles = rawPres.where((p) => p['is_visible'] != false).toList();

      if (visibles.isEmpty) {
        lineas.add(_LineaProducto(producto: productMap, presentacion: null));
      } else {
        for (final pp in visibles) {
          final pres = _presFromSupabase(pp);
          if (pres.id.isEmpty) continue;
          if (pres.molienda.length > 1) {
            for (final g in pres.molienda) {
              lineas.add(_LineaProducto(producto: productMap, presentacion: pres, grind: g));
            }
          } else {
            lineas.add(_LineaProducto(
              producto: productMap, presentacion: pres,
              grind: pres.molienda.isNotEmpty ? pres.molienda.first : null,
            ));
          }
        }
      }
    }

    _lineasEvento = lineas;
  }

  /// Mapea campos Supabase → Presentacion (para event_offers).
  Presentacion _presFromSupabase(Map<String, dynamic> pp) {
    final packSize  = double.tryParse(pp['pack_size']?.toString() ?? '1') ?? 1.0;
    final cents     = int.tryParse(pp['price_cents']?.toString() ?? '0') ?? 0;
    final grind     = pp['grind'];
    final molienda  = grind is List
        ? grind.map((e) => e.toString()).toList()
        : (grind?.toString().isNotEmpty == true
            ? [grind.toString()]
            : <String>[]);
    return Presentacion(
      id:             pp['id']?.toString() ?? '',
      contenido:      packSize,
      unidad:         pp['unit']?.toString() ?? 'und',
      precio:         cents / 100.0,
      stock:          (pp['stock'] as num?)?.toInt() ?? 999,
      pedidoMinimo:   (pp['min_order_qty'] as num?)?.toInt() ?? 1,
      orden:          (pp['sort_order'] as num?)?.toInt() ?? 0,
      predeterminada: pp['is_default'] == true,
      molienda:       molienda,
      imageUrl:       pp['image_url'] as String?,
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // Helpers de cliente (igual que pedido)
  // ══════════════════════════════════════════════════════════════════════════

  void _initDatosCliente() {
    if (widget.cliente != null) _clienteSeleccionado = widget.cliente;
    final c = widget.cliente ?? {};
    String nombre = '';
    for (final k in ['nombreNegocio', 'nombreResponsable', 'nombre', 'whatsapp', 'telefono']) {
      final v = (c[k] ?? '').toString().trim();
      if (v.isNotEmpty) { nombre = v; break; }
    }
    _clienteController       = TextEditingController(text: nombre)
      ..addListener(() => setState(() {}));
    _whatsappController      = TextEditingController(text: c['whatsapp'] ?? '');
    _direccionController     = TextEditingController(text: _construirDireccionEnvio(c));
    _observacionesController = TextEditingController();
    _autocompletarObservaciones(c);
  }

  String _construirDireccionEnvio(Map<String, dynamic> c) {
    final tipo = (c['tipoEnvio'] ?? '').toString().trim().toUpperCase();
    if (tipo == 'SEDE') {
      return (c['localEnvio'] ?? c['sedeEnvio'] ?? '').toString().trim();
    }
    final partes = <String>[];
    final dirEnvio = (c['direccionEnvio'] ?? '').toString().trim();
    final dir      = (c['direccion']     ?? '').toString().trim();
    if (tipo == 'NACIONAL' && dirEnvio.isNotEmpty) {
      partes.add(dirEnvio);
    } else if (dir.isNotEmpty) {
      partes.add(dir);
    } else if (dirEnvio.isNotEmpty) {
      partes.add(dirEnvio);
    }
    final disEnvio = (c['distritoEnvio'] ?? '').toString().trim();
    final dis      = (c['distrito'] ?? c['ciudad'] ?? '').toString().trim();
    if (tipo == 'NACIONAL' && disEnvio.isNotEmpty) {
      partes.add(disEnvio);
    } else if (dis.isNotEmpty) {
      partes.add(dis);
    } else if (disEnvio.isNotEmpty) {
      partes.add(disEnvio);
    }
    final depEnvio = (c['departamentoEnvio'] ?? '').toString().trim();
    final dep      = (c['departamento']     ?? '').toString().trim();
    if (tipo == 'NACIONAL' && depEnvio.isNotEmpty) {
      partes.add(depEnvio);
    } else if (dep.isNotEmpty) {
      partes.add(dep);
    } else if (depEnvio.isNotEmpty) {
      partes.add(depEnvio);
    }
    if (partes.isEmpty) {
      for (final k in ['localEnvio', 'direccionEnvio', 'direccion', 'distrito', 'ciudad', 'departamento']) {
        final v = (c[k] ?? '').toString().trim();
        if (v.isNotEmpty) return v;
      }
    }
    return partes.join(', ');
  }

  void _autocompletarObservaciones(Map<String, dynamic> c) {
    final nota = (c['notas'] ?? '').toString().trim();
    if (nota.isNotEmpty) _observacionesController.text = nota;
  }

  void _seleccionarCliente(Map<String, dynamic> c) {
    String nombre = '';
    for (final k in ['nombreNegocio', 'nombreResponsable', 'nombre', 'whatsapp', 'telefono']) {
      final v = (c[k] ?? '').toString().trim();
      if (v.isNotEmpty) { nombre = v; break; }
    }
    setState(() => _clienteSeleccionado = c);
    _clienteController.text   = nombre;
    _whatsappController.text  = (c['whatsapp'] ?? '').toString();
    _direccionController.text = _construirDireccionEnvio(c);
    _autocompletarObservaciones(c);
    final id = (c['id'] ?? '').toString();
    if (id.isNotEmpty) _cargarPreciosCliente(id);
    // Auto-seleccionar próximo tueste al seleccionar cliente
    if (_eventos.isNotEmpty && _eventoSeleccionado == null) {
      final proximo = _proximoEvento();
      if (proximo != null) {
        setState(() {
          _eventoSeleccionado = proximo;
          _reconstruirLineasEvento();
        });
      }
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // Helpers de evento
  // ══════════════════════════════════════════════════════════════════════════

  String _eventoLabel(Map<String, dynamic> ev) {
    final raw = ev['roasted_at']?.toString() ?? '';
    if (raw.isEmpty) return '—';
    try {
      final dt = DateTime.parse(raw).toLocal();
      const months = ['', 'ene', 'feb', 'mar', 'abr', 'may', 'jun',
                      'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];
      return '${dt.day} ${months[dt.month]} ${dt.year}';
    } catch (_) { return raw; }
  }

  /// Etiqueta compacta de kg para el banner: usa estimated_kg_out si existe,
  /// si no usa green_in_kg con prefijo "verde".
  String _eventoKgLabel(Map<String, dynamic> ev) {
    final est = double.tryParse(ev['estimated_kg_out']?.toString() ?? '');
    if (est != null) {
      final s = est == est.truncateToDouble()
          ? '${est.toInt()} kg'
          : '${est.toStringAsFixed(1)} kg';
      return '~$s tostado';
    }
    final verde = double.tryParse(ev['green_in_kg']?.toString() ?? '');
    if (verde != null) {
      final s = verde == verde.truncateToDouble()
          ? '${verde.toInt()} kg'
          : '${verde.toStringAsFixed(1)} kg';
      return '$s verde';
    }
    return '';
  }

  String _eventoProductosNombre(Map<String, dynamic> ev) {
    final offers = List<Map<String, dynamic>>.from(ev['event_offers'] ?? []);
    return offers
        .map((o) => (o['product']?['name'] ?? '').toString())
        .where((n) => n.isNotEmpty)
        .toSet()
        .join(', ');
  }

  // ══════════════════════════════════════════════════════════════════════════
  // Disponibilidad de kg por presentación
  // ══════════════════════════════════════════════════════════════════════════

  /// Kg totales disponibles del evento seleccionado.
  /// Usa kg_offered - kg_reserved de las offers; si no hay offers, usa estimated_kg_out.
  double get _eventoKgDisponibleTotal {
    if (_eventoSeleccionado == null) return 0;
    final offers = List<Map<String, dynamic>>.from(
        _eventoSeleccionado!['event_offers'] ?? []);
    double ofrecido = 0, reservado = 0;
    for (final o in offers) {
      ofrecido  += double.tryParse(o['kg_offered']?.toString()  ?? '0') ?? 0;
      reservado += double.tryParse(o['kg_reserved']?.toString() ?? '0') ?? 0;
    }
    if (ofrecido > 0) return ofrecido - reservado;
    // Fallback: usar kg estimados del tueste
    return double.tryParse(
        _eventoSeleccionado!['estimated_kg_out']?.toString() ?? '0') ?? 0;
  }

  /// Kg ya comprometidos en el carrito actual.
  double get _kgEnCarrito {
    double total = 0;
    for (final item in _carrito) {
      if (item.presentacionId != null) {
        total += _packSizeKg(item.presentacionId!) * item.cantidad;
      }
    }
    return total;
  }

  /// Convierte pack_size + unit de una presentación a kg.
  double _packSizeKg(String presentacionId) {
    for (final linea in _lineas) {
      if (linea.presentacion?.id == presentacionId) {
        return _presPackKg(linea.presentacion!);
      }
    }
    return 0;
  }

  double _presPackKg(Presentacion pres) {
    final size = pres.contenido.toDouble();
    switch (pres.unidad.toLowerCase()) {
      case 'kg': return size;
      case 'g':  return size / 1000;
      case 'lb': return size * 0.453592;
      default:   return 0; // und u otras sin peso → no aplica limitación
    }
  }

  /// Unidades disponibles de una presentación dado lo que ya hay en el carrito.
  /// Devuelve -1 si la presentación no tiene unidad de peso (sin límite de kg).
  int _unidadesDisponibles(Presentacion pres) {
    final packKg = _presPackKg(pres);
    if (packKg <= 0) return -1; // sin restricción de kg
    final kgRestante = _eventoKgDisponibleTotal - _kgEnCarrito;
    return (kgRestante / packKg).floor().clamp(0, 9999);
  }

  // ══════════════════════════════════════════════════════════════════════════
  // Carrito
  // ══════════════════════════════════════════════════════════════════════════

  void _agregarAlCarrito(
    Map<String, dynamic> producto, {
    String? presentacionId,
    String? presentacionLabel,
    double? precioPresentacion,
    String? grind,
    String? imageUrl,
  }) {
    FocusScope.of(context).unfocus();
    final codigo          = (producto['codigo'] ?? producto['id'] ?? '').toString();
    final precioBase      = precioPresentacion ?? (producto['precio'] ?? 0).toDouble();
    final precioPreferencial = presentacionId != null ? _preciosCliente[presentacionId] : null;
    final key = presentacionId != null ? '$codigo|$presentacionId|${grind ?? ''}' : codigo;
    final existente = _carrito.indexWhere((i) => i.key == key);
    setState(() {
      if (existente >= 0) {
        _carrito[existente].cantidad++;
      } else {
        _carrito.add(_ItemCarrito(
          codigo:             codigo,
          nombre:             (producto['nombre'] ?? '').toString(),
          precioBase:         precioBase,
          precioMayor:        (producto['precioMayor'] ?? 0).toDouble(),
          cantidadMayor:      (producto['cantidadMayor'] ?? 0) as int,
          precioPreferencial: precioPreferencial,
          presentacionId:     presentacionId,
          presentacionLabel:  presentacionLabel,
          grind:              grind,
          imageUrl:           imageUrl,
          cantidad:           1,
        ));
      }
    });
  }

  void _handleAgregar(Map<String, dynamic> p, Presentacion? pres, double precio, String? grind) {
    _agregarAlCarrito(p,
        presentacionId:     pres?.id,
        presentacionLabel:  pres?.etiqueta,
        precioPresentacion: precio,
        grind:              grind,
        imageUrl:           pres?.imageUrl);
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

  void _mostrarDialogoCantidad(Map<String, dynamic> producto, {int indexEnCarrito = -1}) {
    final codigo         = (producto['codigo'] ?? producto['id'] ?? '').toString();
    final cantidadActual = indexEnCarrito >= 0 ? _carrito[indexEnCarrito].cantidad : 1;

    // Calcular máximo permitido por kg disponibles para este item
    int maxPermitido = 9999;
    if (indexEnCarrito >= 0 && _eventoSeleccionado != null) {
      final item    = _carrito[indexEnCarrito];
      final packKg  = item.presentacionId != null ? _packSizeKg(item.presentacionId!) : 0.0;
      if (packKg > 0) {
        // kg libres = total disponible - lo que hay en carrito + lo que ya tiene este item
        final kgLibres = _eventoKgDisponibleTotal - _kgEnCarrito + (packKg * item.cantidad);
        maxPermitido   = (kgLibres / packKg).floor().clamp(1, 9999);
      }
    }

    final ctrl = TextEditingController(text: '$cantidadActual')
      ..selection = TextSelection(baseOffset: 0, extentOffset: '$cantidadActual'.length);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          (producto['nombre'] ?? '').toString(),
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          maxLines: 2, overflow: TextOverflow.ellipsis,
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: ctrl,
              autofocus: true,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              decoration: InputDecoration(
                hintText: 'Cantidad',
                filled: true, fillColor: Colors.grey.shade100,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
              ),
              onSubmitted: (_) => Navigator.pop(ctx, int.tryParse(ctrl.text)),
            ),
            if (maxPermitido < 9999) ...[
              const SizedBox(height: 8),
              Text(
                'Máximo disponible: $maxPermitido',
                style: TextStyle(fontSize: 12, color: Colors.orange.shade700),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, int.tryParse(ctrl.text)),
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE65100), foregroundColor: Colors.white),
            child: const Text('OK'),
          ),
        ],
      ),
    ).then((cantidad) {
      if (cantidad == null || cantidad <= 0) return;
      // Recortar al máximo permitido
      final cantidadFinal = cantidad.clamp(1, maxPermitido);
      if (cantidadFinal < cantidad) {
        _showSnack('Limitado a $cantidadFinal (máx. disponible)', Colors.orange);
      }
      setState(() {
        if (indexEnCarrito >= 0) {
          _carrito[indexEnCarrito].cantidad = cantidadFinal;
        } else {
          final existente = _carrito.indexWhere((i) => i.codigo == codigo);
          if (existente >= 0) {
            _carrito[existente].cantidad = cantidadFinal;
          }
        }
      });
    });
  }

  String _grindLabel(String raw) => switch (raw) {
    'ground' => 'Molido',
    'whole'  => 'Grano',
    'green'  => 'Verde',
    _        => raw,
  };

  Widget _imagePlaceholder() => Container(
    width: 54, height: 54,
    decoration: BoxDecoration(
      color: Colors.brown.shade50,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Icon(Icons.coffee_rounded, color: Colors.brown.shade300, size: 26),
  );

  // ══════════════════════════════════════════════════════════════════════════
  // Crear pre-venta
  // ══════════════════════════════════════════════════════════════════════════

  Future<void> _crearPreventa() async {
    if (_carrito.isEmpty) {
      _showSnack('Agrega al menos un producto', Colors.orange); return;
    }
    if (_whatsappController.text.trim().isEmpty) {
      _showSnack('Ingresa el número de WhatsApp', Colors.orange); return;
    }
    if (_eventoSeleccionado == null) {
      _showSnack('Selecciona un tueste programado', Colors.orange); return;
    }

    setState(() => _isLoading = true);

    final productos = _carrito.map((item) => {
      'codigo':          item.codigo,
      'nombre':          item.presentacionLabel != null
                             ? '${item.nombre} – ${item.presentacionLabel}'
                             : item.nombre,
      'unidad':          item.presentacionLabel ?? 'unidad',
      'presentacionId':  item.presentacionId,
      if (item.grind != null) 'grind': item.grind,
      'cantidad':        item.cantidad,
      'precio':          item.precio,
      'subtotal':        item.subtotal,
    }).toList();

    final c          = _clienteSeleccionado ?? widget.cliente ?? {};
    String s(dynamic v) => (v ?? '').toString().trim();
    final tipoEnvio  = s(c['tipoEnvio']).toUpperCase();
    final telefono   = s(c['telefono']);

    String departamento, ciudad;
    if (tipoEnvio == 'NACIONAL') {
      departamento = s(c['departamentoEnvio']).isNotEmpty
          ? s(c['departamentoEnvio']) : s(c['departamento']);
      ciudad = s(c['distritoEnvio']).isNotEmpty
          ? s(c['distritoEnvio'])
          : (s(c['distrito']).isNotEmpty ? s(c['distrito']) : s(c['ciudad']));
    } else {
      departamento = s(c['departamento']);
      ciudad       = s(c['distrito']).isNotEmpty ? s(c['distrito']) : s(c['ciudad']);
    }
    final empresaEnvio = tipoEnvio == 'NACIONAL' ? s(c['empresaEnvio']) : null;

    final result = await ApiService.crearPreventaPedido(
      whatsapp:      _whatsappController.text.trim(),
      sourceEventId: _eventoSeleccionado!['id']?.toString() ?? '',
      cliente:       _clienteController.text.trim(),
      telefono:      telefono.isNotEmpty ? telefono : null,
      direccion:     _direccionController.text.trim(),
      ciudad:        ciudad.isNotEmpty ? ciudad : null,
      departamento:  departamento.isNotEmpty ? departamento : null,
      productos:     productos,
      total:         _total,
      costoEnvio:    _costoDelivery,
      observaciones: _observacionesController.text.trim(),
      tipoEnvio:     tipoEnvio.isNotEmpty ? tipoEnvio : null,
      empresaEnvio:  (empresaEnvio != null && empresaEnvio.isNotEmpty) ? empresaEnvio : null,
      notificarCliente: _notificarCliente,
    );

    setState(() => _isLoading = false);

    if (result.isSuccess && mounted) {
      Navigator.pop(context, result.data?['pedido']);
    } else {
      _showSnack('Error: ${result.error}', Colors.red);
    }
  }

  void _showSnack(String msg, Color color) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg), backgroundColor: color));
  }

  // ══════════════════════════════════════════════════════════════════════════
  // Selector de cliente
  // ══════════════════════════════════════════════════════════════════════════

  void _abrirSelectorCliente() {
    String busqueda = '';
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) {
          final filtrados = busqueda.isEmpty
              ? _clientes
              : _clientes.where((c) {
                  final q = busqueda.toLowerCase();
                  return (c['nombreNegocio']    ?? '').toString().toLowerCase().contains(q) ||
                         (c['nombreResponsable'] ?? '').toString().toLowerCase().contains(q) ||
                         (c['nombre']            ?? '').toString().toLowerCase().contains(q) ||
                         (c['whatsapp']          ?? '').toString().contains(q);
                }).toList();

          return DraggableScrollableSheet(
            initialChildSize: 0.75, maxChildSize: 0.95, minChildSize: 0.4,
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
                    width: 40, height: 4,
                    decoration: BoxDecoration(
                        color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(children: [
                      const Text('Seleccionar cliente',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      const Spacer(),
                      IconButton(
                          icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
                    ]),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: TextField(
                      autofocus: true,
                      onChanged: (v) => setModal(() => busqueda = v),
                      decoration: InputDecoration(
                        hintText: 'Buscar cliente...',
                        prefixIcon: const Icon(Icons.search),
                        filled: true, fillColor: Colors.grey.shade100,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide.none),
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                    ),
                  ),
                  Expanded(
                    child: _loadingClientes
                        ? const Center(child: CircularProgressIndicator())
                        : filtrados.isEmpty
                            ? Center(child: Text('Sin resultados',
                                style: TextStyle(color: Colors.grey.shade500)))
                            : ListView.builder(
                                controller: scrollCtrl,
                                itemCount: filtrados.length,
                                itemBuilder: (_, i) {
                                  final c      = filtrados[i];
                                  String nombre = '';
                                  for (final k in ['nombreNegocio', 'nombreResponsable', 'nombre', 'whatsapp', 'telefono']) {
                                    final v = (c[k] ?? '').toString();
                                    if (v.isNotEmpty) { nombre = v; break; }
                                  }
                                  final ws        = (c['whatsapp']  ?? '').toString();
                                  final telefono  = (c['telefono']  ?? '').toString();
                                  final direccion = _construirDireccionEnvio(c);
                                  final tipoEnvio = (c['tipoEnvio'] ?? '').toString().toUpperCase();
                                  return ListTile(
                                    leading: CircleAvatar(
                                      backgroundColor: const Color(0xFFE65100).withOpacity(0.1),
                                      child: Text(
                                        nombre.isNotEmpty ? nombre[0].toUpperCase() : '?',
                                        style: const TextStyle(
                                            color: Color(0xFFE65100), fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                    title: Text(nombre,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w600, fontSize: 14)),
                                    subtitle: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        if (ws.isNotEmpty || telefono.isNotEmpty)
                                          Text(ws.isNotEmpty ? ws : telefono,
                                              style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                                        if (direccion.isNotEmpty)
                                          Text(direccion,
                                              style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                                              maxLines: 1, overflow: TextOverflow.ellipsis),
                                      ],
                                    ),
                                    isThreeLine: direccion.isNotEmpty,
                                    trailing: tipoEnvio.isNotEmpty
                                        ? Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFE65100).withOpacity(0.08),
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: Text(tipoEnvio,
                                                style: const TextStyle(
                                                    fontSize: 10, color: Color(0xFFE65100))),
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
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // Selector de evento
  // ══════════════════════════════════════════════════════════════════════════

  void _abrirSelectorEvento() {
    if (_eventos.isEmpty) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.5, maxChildSize: 0.85, minChildSize: 0.3,
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
                width: 40, height: 4,
                decoration: BoxDecoration(
                    color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(children: [
                  const Icon(Icons.local_fire_department, color: Color(0xFFE65100), size: 20),
                  const SizedBox(width: 8),
                  const Text('Seleccionar tueste',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const Spacer(),
                  IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
                ]),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView.builder(
                  controller: scrollCtrl,
                  padding: const EdgeInsets.all(12),
                  itemCount: _eventos.length,
                  itemBuilder: (_, i) {
                    final ev  = _eventos[i];
                    final sel = _eventoSeleccionado?['id'] == ev['id'];
                    final productos = _eventoProductosNombre(ev);
                    return GestureDetector(
                      onTap: () {
                        Navigator.pop(ctx);
                        setState(() {
                          _eventoSeleccionado = ev;
                          _carrito.clear();
                          _reconstruirLineasEvento();
                        });
                      },
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: sel ? const Color(0xFFE65100) : Colors.grey.shade200,
                            width: sel ? 2 : 1,
                          ),
                          borderRadius: BorderRadius.circular(10),
                          color: sel ? const Color(0xFFFFF3E0) : Colors.white,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              sel ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                              size: 18,
                              color: sel ? const Color(0xFFE65100) : Colors.grey.shade400,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(_eventoLabel(ev),
                                      style: TextStyle(
                                        fontSize: 14, fontWeight: FontWeight.w600,
                                        color: sel ? const Color(0xFFE65100) : Colors.black87,
                                      )),
                                  if (productos.isNotEmpty) ...[
                                    const SizedBox(height: 2),
                                    Text(productos,
                                        style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey.shade600,
                                            fontStyle: FontStyle.italic)),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // Build
  // ══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final isWideScreen = MediaQuery.of(context).size.width > 600;
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: const Text('Nueva Pre-venta'),
        backgroundColor: const Color(0xFFE65100),
        foregroundColor: Colors.white,
        bottom: !isWideScreen
            ? TabBar(
                controller: _tabController,
                indicatorColor: Colors.white,
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white70,
                tabs: [
                  Tab(child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(Icons.inventory_2, size: 18),
                      SizedBox(width: 5),
                      Text('Productos', style: TextStyle(fontSize: 12)),
                    ],
                  )),
                  Tab(child: Row(
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
                  )),
                ],
              )
            : null,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : isWideScreen
              ? _buildWideLayout()
              : _buildMobileLayout(),
    );
  }

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
        _buildBottomBar(),
      ],
    );
  }

  // ── Datos cliente + evento ─────────────────────────────────────────────────
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
          const SizedBox(height: 6),
          _buildEventoBanner(),
        ],
      ),
    );
  }

  Widget _buildClienteField() {
    final nombre = _clienteController.text.isNotEmpty
        ? _clienteController.text
        : (_clienteSeleccionado != null
            ? (_clienteSeleccionado!['nombreNegocio'] ??
                _clienteSeleccionado!['nombreResponsable'] ??
                _clienteSeleccionado!['nombre'] ?? '').toString()
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
                  : Text('Seleccionar cliente',
                      style: TextStyle(color: Colors.grey.shade400, fontSize: 14)),
            ),
            Icon(Icons.arrow_drop_down, color: Colors.grey.shade600),
          ],
        ),
      ),
    );
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
        filled: true, fillColor: Colors.grey.shade50,
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
        filled: true, fillColor: Colors.grey.shade50,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
        isDense: true,
      ),
    );
  }

  Widget _buildEventoBanner() {
    if (_loadingEventos) {
      return Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.grey.shade50, borderRadius: BorderRadius.circular(8)),
        child: const LinearProgressIndicator(),
      );
    }
    if (_eventos.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.orange.shade50, borderRadius: BorderRadius.circular(8)),
        child: Row(children: [
          Icon(Icons.warning_outlined, size: 15, color: Colors.orange.shade700),
          const SizedBox(width: 6),
          Text('No hay tuestes programados',
              style: TextStyle(fontSize: 12, color: Colors.orange.shade700)),
        ]),
      );
    }

    final ev = _eventoSeleccionado;
    return GestureDetector(
      onTap: _abrirSelectorEvento,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: ev != null ? const Color(0xFFFFF3E0) : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: ev != null
                ? const Color(0xFFE65100).withOpacity(0.3)
                : Colors.grey.shade200,
          ),
        ),
        child: Row(
          children: [
            const Icon(Icons.local_fire_department, size: 16, color: Color(0xFFE65100)),
            const SizedBox(width: 6),
            Expanded(
              child: ev != null
                  ? RichText(
                      text: TextSpan(
                        style: const TextStyle(color: Colors.black87),
                        children: [
                          TextSpan(
                            text: 'Tueste: ${_eventoLabel(ev)}',
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                          ),
                          if (_eventoKgLabel(ev).isNotEmpty)
                            TextSpan(
                              text: '  •  ${_eventoKgLabel(ev)}',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey.shade600,
                                  fontStyle: FontStyle.italic),
                            ),
                        ],
                      ),
                    )
                  : Text('Seleccionar tueste programado',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
            ),
            Icon(Icons.swap_horiz, size: 16, color: const Color(0xFFE65100).withOpacity(0.7)),
          ],
        ),
      ),
    );
  }

  // ── Lista de productos ─────────────────────────────────────────────────────
  Widget _buildListaProductos() {
    final lineasFiltradas = _lineas;

    final loading = _eventoSeleccionado != null ? false : _loadingProductos;

    return Container(
      margin: const EdgeInsets.all(8),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
      child: Column(
        children: [
          Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator())
                : lineasFiltradas.isEmpty
                    ? Center(child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.inventory_2_outlined, size: 48, color: Colors.grey.shade300),
                          const SizedBox(height: 8),
                          Text(
                            _eventoSeleccionado != null
                                ? 'No hay productos en este tueste'
                                : 'No hay productos',
                            style: TextStyle(color: Colors.grey.shade500)),
                        ],
                      ))
                    : GestureDetector(
                        onTap: () => FocusScope.of(context).unfocus(),
                        behavior: HitTestBehavior.translucent,
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          itemCount: lineasFiltradas.length,
                          itemBuilder: (context, index) {
                            final linea    = lineasFiltradas[index];
                            final p        = linea.producto;
                            final pres     = linea.presentacion;
                            final grindLinea = linea.grind;
                            final codigo   = (p['codigo'] ?? p['id'] ?? '').toString();
                            final lineaKey = pres != null
                                ? '$codigo|${pres.id}|${grindLinea ?? ''}'
                                : codigo;

                            final precioPreferencial  = pres != null ? _preciosCliente[pres.id] : null;
                            final precio = precioPreferencial ??
                                (pres != null ? pres.precio : (p['precio'] ?? 0).toDouble());
                            final tienePreferencial = precioPreferencial != null;

                            final cantidadEnLinea = _carrito
                                .where((i) => i.key == lineaKey)
                                .fold(0, (sum, i) => sum + i.cantidad);
                            final idxEnCarrito = _carrito.indexWhere(
                                (i) => i.key == lineaKey);

                            // En pre-venta con evento seleccionado, el stock del catálogo
                            // es irrelevante — la disponibilidad viene de kg_offered - kg_reserved.
                            final sinStock  = _eventoSeleccionado == null &&
                                              pres != null && pres.stock <= 0;
                            // Disponibilidad por kg del tueste
                            final dispUnits = pres != null ? _unidadesDisponibles(pres) : -1;
                            // -1 = sin restricción (und sin peso), 0 = agotado, >0 = disponible
                            final sinKg     = dispUnits == 0;
                            final bloqueado = sinStock || sinKg;

                            final moliendaChips = grindLinea != null
                                ? [switch (grindLinea) {
                                    'ground' => ('Molido', Colors.brown.shade600, Colors.brown.shade50),
                                    'whole'  => ('Grano',  Colors.orange.shade700, Colors.orange.shade50),
                                    'green'  => ('Verde',  Colors.green.shade700,  Colors.green.shade50),
                                    _        => (grindLinea, Colors.grey.shade600, Colors.grey.shade100),
                                  }]
                                : <(String, Color, Color)>[];

                            // Chip de disponibilidad (solo si hay evento y la pres tiene unidad de peso)
                            Widget? dispChip;
                            if (_eventoSeleccionado != null && pres != null && dispUnits >= 0) {
                              final Color dispFg, dispBg;
                              final String dispLabel;
                              if (dispUnits == 0) {
                                dispFg  = Colors.red.shade700;
                                dispBg  = Colors.red.shade50;
                                dispLabel = 'Sin disponibilidad';
                              } else if (dispUnits <= 5) {
                                dispFg  = Colors.orange.shade800;
                                dispBg  = Colors.orange.shade50;
                                dispLabel = '$dispUnits disp.';
                              } else {
                                dispFg  = Colors.teal.shade700;
                                dispBg  = Colors.teal.shade50;
                                dispLabel = '$dispUnits disp.';
                              }
                              dispChip = _Chip(label: dispLabel, fg: dispFg, bg: dispBg);
                            }

                            return Opacity(
                              opacity: bloqueado ? 0.45 : 1.0,
                              child: Card(
                                margin: const EdgeInsets.only(bottom: 6),
                                child: ListTile(
                                  dense: true,
                                  leading: Container(
                                    width: 40, height: 40,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFE65100).withOpacity(0.08),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: pres?.imageUrl?.isNotEmpty == true
                                        ? ClipRRect(
                                            borderRadius: BorderRadius.circular(8),
                                            child: Image.network(pres!.imageUrl!, fit: BoxFit.cover,
                                                errorBuilder: (_, __, ___) =>
                                                    const Icon(Icons.coffee, color: Color(0xFFE65100))),
                                          )
                                        : const Icon(Icons.coffee, color: Color(0xFFE65100)),
                                  ),
                                  title: Text(
                                    (p['nombre'] ?? '').toString(),
                                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                                    maxLines: 1, overflow: TextOverflow.ellipsis,
                                  ),
                                  subtitle: Padding(
                                    padding: const EdgeInsets.only(top: 2),
                                    child: Wrap(
                                      spacing: 4, runSpacing: 4,
                                      crossAxisAlignment: WrapCrossAlignment.center,
                                      children: [
                                        if (pres != null)
                                          _Chip(label: pres.etiqueta,
                                              fg: const Color(0xFFE65100).withOpacity(0.9),
                                              bg: const Color(0xFFFFF3E0)),
                                        _Chip(
                                          label: tienePreferencial
                                              ? 'S/ ${precio.toStringAsFixed(2)} ★'
                                              : 'S/ ${precio.toStringAsFixed(2)}',
                                          fg: tienePreferencial
                                              ? Colors.purple.shade700
                                              : Colors.green.shade700,
                                          bg: tienePreferencial
                                              ? Colors.purple.shade50
                                              : Colors.green.shade50,
                                        ),
                                        ...moliendaChips.map((c) =>
                                            _Chip(label: c.$1, fg: c.$2, bg: c.$3)),
                                        if (dispChip != null) dispChip,
                                        // Solo mostrar "Sin stock" si NO hay evento (modo catálogo)
                                        if (sinStock && _eventoSeleccionado == null)
                                          _Chip(label: 'Sin stock',
                                              fg: Colors.red.shade700, bg: Colors.red.shade50),
                                      ],
                                    ),
                                  ),
                                  trailing: cantidadEnLinea > 0
                                      // Siempre mostrar stepper si hay items en carrito,
                                      // solo deshabilitar el + cuando no hay kg disponibles
                                      ? Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            InkWell(
                                              onTap: () {
                                                if (idxEnCarrito >= 0)
                                                  _quitarDelCarrito(idxEnCarrito);
                                              },
                                              borderRadius: BorderRadius.circular(20),
                                              child: Padding(
                                                padding: const EdgeInsets.all(4),
                                                child: Icon(Icons.remove_circle,
                                                    color: Colors.red.shade400, size: 28),
                                              ),
                                            ),
                                            GestureDetector(
                                              onTap: () => _mostrarDialogoCantidad(
                                                  p, indexEnCarrito: idxEnCarrito),
                                              child: Container(
                                                constraints:
                                                    const BoxConstraints(minWidth: 32),
                                                padding: const EdgeInsets.symmetric(
                                                    horizontal: 8, vertical: 4),
                                                decoration: BoxDecoration(
                                                  color: const Color(0xFFE65100).withOpacity(0.12),
                                                  borderRadius: BorderRadius.circular(8),
                                                ),
                                                child: Text(
                                                  '$cantidadEnLinea',
                                                  textAlign: TextAlign.center,
                                                  style: const TextStyle(
                                                      fontWeight: FontWeight.bold,
                                                      color: Color(0xFFE65100),
                                                      fontSize: 14),
                                                ),
                                              ),
                                            ),
                                            InkWell(
                                              onTap: bloqueado
                                                  ? null
                                                  : () => _handleAgregar(p, pres, precio, grindLinea),
                                              borderRadius: BorderRadius.circular(20),
                                              child: Padding(
                                                padding: const EdgeInsets.all(4),
                                                child: Icon(Icons.add_circle,
                                                    color: bloqueado
                                                        ? Colors.grey.shade300
                                                        : const Color(0xFFE65100),
                                                    size: 28),
                                              ),
                                            ),
                                          ],
                                        )
                                      // Sin items en carrito: mostrar bloqueo o botón agregar
                                      : bloqueado
                                          ? Icon(Icons.block, color: Colors.red.shade300, size: 26)
                                          : IconButton(
                                              icon: Icon(Icons.add_circle,
                                                  color: const Color(0xFFE65100), size: 28),
                                              onPressed: () => _handleAgregar(p, pres, precio, grindLinea),
                                            ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  // ── Carrito wide ───────────────────────────────────────────────────────────
  Widget _buildCarrito() {
    return Container(
      margin: const EdgeInsets.fromLTRB(0, 8, 8, 8),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
      child: Column(
        children: [
          _buildCarritoHeader(),
          Expanded(child: _buildCarritoItems()),
          _buildDeliveryRow(),
          _buildObservaciones(),
          _buildCarritoFooter(),
        ],
      ),
    );
  }

  Widget _buildCarritoMobile() {
    return Container(
      margin: const EdgeInsets.all(8),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
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
        color: const Color(0xFFFFF3E0),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
      ),
      child: Row(
        children: [
          const Icon(Icons.shopping_cart, color: Color(0xFFE65100)),
          const SizedBox(width: 8),
          Text('Carrito (${_carrito.length})',
              style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFE65100))),
          const Spacer(),
          if (_carrito.isNotEmpty)
            TextButton(
              onPressed: () => setState(() => _carrito.clear()),
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
            Text('Agrega productos desde la lista',
                style: TextStyle(color: Colors.grey.shade400, fontSize: 12)),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: _carrito.length,
      itemBuilder: (context, index) {
        final item = _carrito[index];
        // Calcular si el botón + debe estar habilitado
        bool puedeAgregar = true;
        if (_eventoSeleccionado != null && item.presentacionId != null) {
          final packKg = _packSizeKg(item.presentacionId!);
          if (packKg > 0) {
            final kgLibres = _eventoKgDisponibleTotal - _kgEnCarrito;
            puedeAgregar = kgLibres >= packKg;
          }
        }

        return Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
              color: Colors.grey.shade50, borderRadius: BorderRadius.circular(10)),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // ── Imagen de la presentación ──────────────────────────────
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: item.imageUrl?.isNotEmpty == true
                    ? Image.network(
                        item.imageUrl!,
                        width: 54, height: 54, fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _imagePlaceholder(),
                      )
                    : _imagePlaceholder(),
              ),
              const SizedBox(width: 10),
              // ── Nombre + precio + controles ────────────────────────────
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(item.nombre,
                                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                                  maxLines: 1, overflow: TextOverflow.ellipsis),
                              if (item.presentacionLabel != null || item.grind != null)
                                Wrap(
                                  spacing: 4,
                                  children: [
                                    if (item.presentacionLabel != null)
                                      Text(item.presentacionLabel!,
                                          style: const TextStyle(
                                              fontSize: 12,
                                              color: Color(0xFFE65100),
                                              fontWeight: FontWeight.w500)),
                                    if (item.grind != null)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                        decoration: BoxDecoration(
                                          color: Colors.brown.shade50,
                                          borderRadius: BorderRadius.circular(4),
                                          border: Border.all(color: Colors.brown.shade200),
                                        ),
                                        child: Text(_grindLabel(item.grind!),
                                            style: TextStyle(
                                                fontSize: 11,
                                                color: Colors.brown.shade700,
                                                fontWeight: FontWeight.w500)),
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
                        Text('S/ ${item.precio.toStringAsFixed(2)} c/u',
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                        if (item.precioPreferencial != null) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                                color: Colors.purple.shade50,
                                borderRadius: BorderRadius.circular(4)),
                            child: Text('Preferencial',
                                style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.purple.shade700,
                                    fontWeight: FontWeight.w600)),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Container(
                          decoration: BoxDecoration(
                              border: Border.all(color: Colors.grey.shade300),
                              borderRadius: BorderRadius.circular(8)),
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
                                  final prod = {'codigo': item.codigo, 'nombre': item.nombre, 'precio': item.precio};
                                  _mostrarDialogoCantidad(prod, indexEnCarrito: index);
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFE65100).withOpacity(0.08),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text('${item.cantidad}',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                          color: Color(0xFFE65100))),
                                ),
                              ),
                              IconButton(
                                icon: Icon(Icons.add, size: 18,
                                    color: puedeAgregar ? null : Colors.grey.shade400),
                                padding: const EdgeInsets.all(4),
                                constraints: const BoxConstraints(),
                                onPressed: puedeAgregar
                                    ? () => setState(() => item.cantidad++)
                                    : null,
                              ),
                            ],
                          ),
                        ),
                        const Spacer(),
                        Text('S/ ${item.subtotal.toStringAsFixed(2)}',
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: Colors.green.shade700)),
                      ],
                    ),
                  ],
                ),
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
          color: const Color(0xFFFFF3E0),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFE65100).withOpacity(0.2)),
        ),
        child: Row(
          children: [
            const Icon(Icons.local_shipping_outlined, size: 18, color: Color(0xFFE65100)),
            const SizedBox(width: 8),
            const Text('Delivery',
                style: TextStyle(
                    fontSize: 13, color: Color(0xFFE65100), fontWeight: FontWeight.w500)),
            const Spacer(),
            const Text('S/ ',
                style: TextStyle(
                    fontSize: 13, color: Color(0xFFE65100), fontWeight: FontWeight.w500)),
            SizedBox(
              width: 72,
              child: TextField(
                controller: _deliveryController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                textAlign: TextAlign.right,
                style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFE65100)),
                decoration: const InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  hintText: '0.00',
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                ),
                onChanged: (v) =>
                    setState(() => _costoDelivery = double.tryParse(v) ?? 0),
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
        minLines: 1, maxLines: 2,
        decoration: InputDecoration(
          hintText: 'Observaciones...',
          hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 12),
          filled: true, fillColor: Colors.grey.shade50,
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          isDense: true,
        ),
      ),
    );
  }

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
              const Text('TOTAL:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              Text('S/ ${_total.toStringAsFixed(2)}',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 20,
                      color: Colors.green.shade700)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              SizedBox(
                width: 24, height: 24,
                child: Checkbox(
                  value: _notificarCliente,
                  onChanged: (v) => setState(() => _notificarCliente = v ?? true),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
              const SizedBox(width: 8),
              const Expanded(
                  child: Text('Notificar por WhatsApp',
                      style: TextStyle(fontSize: 12))),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _carrito.isEmpty ? null : _crearPreventa,
              icon: const Icon(Icons.check),
              label: const Text('Crear Pre-venta'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE65100),
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

  Widget _buildBottomBar() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 10,
              offset: const Offset(0, -2)),
        ],
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                SizedBox(
                  width: 20, height: 20,
                  child: Checkbox(
                    value: _notificarCliente,
                    onChanged: (v) =>
                        setState(() => _notificarCliente = v ?? true),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
                const SizedBox(width: 8),
                const Text('Notificar por WhatsApp',
                    style: TextStyle(fontSize: 12)),
                const Spacer(),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('Total:',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                    Text('S/ ${_total.toStringAsFixed(2)}',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 20,
                            color: Colors.green.shade700)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _carrito.isEmpty ? null : _crearPreventa,
                icon: const Icon(Icons.check_circle),
                label: Text(
                  _carrito.isEmpty
                      ? 'Agrega productos'
                      : 'Crear Pre-venta (${_carrito.length})',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE65100),
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.grey.shade300,
                  disabledForegroundColor: Colors.grey.shade500,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Clases auxiliares
// ═══════════════════════════════════════════════════════════════════════════

class _ItemCarrito {
  final String codigo;
  final String nombre;
  final double precioBase;
  final double precioMayor;
  final int cantidadMayor;
  final double? precioPreferencial;
  final String? presentacionId;
  final String? presentacionLabel;
  final String? grind;
  final String? imageUrl;
  int cantidad;

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
    this.imageUrl,
    required this.cantidad,
  });

  String get key =>
      presentacionId != null ? '$codigo|$presentacionId|${grind ?? ''}' : codigo;

  double get precio {
    if (precioPreferencial != null) return precioPreferencial!;
    if (precioMayor > 0 && cantidadMayor > 0 && cantidad >= cantidadMayor)
      return precioMayor;
    return precioBase;
  }

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
      child: Text(label,
          style: TextStyle(fontSize: 11, color: fg, fontWeight: FontWeight.w600)),
    );
  }
}
