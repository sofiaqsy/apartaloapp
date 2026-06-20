import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../services/api_service.dart';
import '../../services/vision_service.dart';
import 'pedidos/widgets/detalle_pedido/detalle_pedido_sheet.dart';

class HomeTab extends StatefulWidget {
  final String businessName;
  final bool isActive;

  const HomeTab({super.key, required this.businessName, this.isActive = true});

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> with SingleTickerProviderStateMixin {
  final List<ItemCarrito> _carrito = [];
  double _total = 0;
  
  // Para pistola (Sunmi)
  String _scanBuffer = '';
  DateTime _lastKeyTime = DateTime.now();
  bool _ocupado = false;
  
  // Detectar tipo de dispositivo
  late bool _esTelefono;
  
  // Para búsqueda de productos (modo teléfono)
  List<Map<String, dynamic>> _productos = [];
  List<Map<String, dynamic>> _productosFiltrados = [];
  bool _cargandoProductos = true;
  String _busqueda = '';
  
  // Tab controller para móvil
  TabController? _tabController;
  
  // Cliente asignado (opcional)
  Map<String, dynamic>? _clienteAsignado;
  
  // Precios personalizados del cliente asignado
  Map<String, double> _preciosCliente = {};

  @override
  void initState() {
    super.initState();
    _detectarDispositivo();
    
    if (_esTelefono) {
      _tabController = TabController(length: 2, vsync: this);
      _cargarProductos();
    } else {
      HardwareKeyboard.instance.addHandler(_handleKeyEvent);
    }
  }

  void _detectarDispositivo() {
    _esTelefono = Platform.isIOS || !_esSunmi();
  }
  
  bool _esSunmi() {
    if (Platform.isIOS) return false;
    return false;
  }

  Future<void> _cargarProductos() async {
    final result = await ApiService.getProductos(limite: 100, estado: 'ACTIVO');
    if (result.isSuccess && mounted) {
      setState(() {
        _productos = result.data!.productos;
        _productosFiltrados = _productos;
        _cargandoProductos = false;
      });
    } else {
      setState(() => _cargandoProductos = false);
    }
  }

  void _filtrarProductos(String query) {
    setState(() {
      _busqueda = query;
      if (query.isEmpty) {
        _productosFiltrados = _productos;
      } else {
        final queryLower = query.toLowerCase();
        _productosFiltrados = _productos.where((p) =>
          (p['nombre'] ?? '').toLowerCase().contains(queryLower) ||
          (p['codigo'] ?? '').toLowerCase().contains(queryLower)
        ).toList();
      }
    });
  }

  @override
  void dispose() {
    if (!_esTelefono) {
      HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    }
    _tabController?.dispose();
    super.dispose();
  }

  // ==================== ESCÁNER PISTOLA (SUNMI) ====================

  bool _handleKeyEvent(KeyEvent event) {
    if (_esTelefono) return false;
    if (event is! KeyDownEvent) return false;
    if (_ocupado) return false;
    if (!widget.isActive) return false;
    
    final now = DateTime.now();
    final timeDiff = now.difference(_lastKeyTime).inMilliseconds;
    
    if (timeDiff > 100 && _scanBuffer.isNotEmpty) {
      _scanBuffer = '';
    }
    
    _lastKeyTime = now;
    
    if (event.logicalKey == LogicalKeyboardKey.enter) {
      if (_scanBuffer.length >= 4) {
        _procesarCodigo(_scanBuffer);
      }
      _scanBuffer = '';
      return true;
    }
    
    final char = event.character;
    if (char != null && char.isNotEmpty) {
      _scanBuffer += char;
      return true;
    }
    
    return false;
  }

  Future<void> _procesarCodigo(String codigo) async {
    _ocupado = true;
    HapticFeedback.heavyImpact();
    
    final resultado = await ApiService.buscarProductoPorCodigo(codigo);
    
    _ocupado = false;
    if (!mounted) return;
    
    if (resultado.isSuccess && resultado.data != null) {
      _agregarAlCarrito(resultado.data!);
    } else {
      _registrarNuevo(codigo);
    }
  }

  // ==================== ESCÁNER CÁMARA (TELÉFONO) ====================

  void _abrirEscanerCamara() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => _EscanerCamaraScreen(
          onCodigoEscaneado: (codigo) {
            Navigator.pop(context);
            _procesarCodigo(codigo);
          },
        ),
      ),
    );
  }

  // ==================== ASIGNAR CLIENTE ====================

  void _mostrarSelectorCliente() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _SelectorClienteSheet(
        clienteActual: _clienteAsignado,
        onClienteSeleccionado: (cliente) async {
          Navigator.pop(ctx);
          await _asignarCliente(cliente);
        },
        onQuitarCliente: () {
          setState(() {
            _clienteAsignado = null;
            _preciosCliente = {};
          });
          Navigator.pop(ctx);
        },
      ),
    );
  }

  Future<void> _asignarCliente(Map<String, dynamic> cliente) async {
    setState(() => _clienteAsignado = cliente);
    
    // Cargar precios personalizados del cliente
    final clienteId = cliente['id'] as String?;
    if (clienteId != null && clienteId.isNotEmpty) {
      final result = await ApiService.getPreciosCliente(clienteId: clienteId);
      if (result.isSuccess && result.data != null) {
        setState(() => _preciosCliente = result.data!);
        
        // Si hay precios personalizados, actualizar el carrito existente
        if (_preciosCliente.isNotEmpty && _carrito.isNotEmpty) {
          _actualizarPreciosCarrito();
        }
      }
    }
  }

  void _actualizarPreciosCarrito() {
    setState(() {
      for (final item in _carrito) {
        if (_preciosCliente.containsKey(item.codigo)) {
          item.precio = _preciosCliente[item.codigo]!;
        }
      }
      _calcularTotal();
    });
  }

  // ==================== LÓGICA COMPARTIDA ====================

  void _agregarAlCarrito(Map<String, dynamic> producto) {
    final codigo = producto['codigo'] ?? '';
    final nombre = producto['nombre'] ?? 'Producto';
    final precioBase = (producto['precio'] as num?)?.toDouble() ?? 0;
    final imagen = producto['imagenUrl'] as String?;
    
    // Usar precio personalizado si existe para este cliente
    final precio = _preciosCliente[codigo] ?? precioBase;
    
    setState(() {
      final index = _carrito.indexWhere((item) => item.codigo == codigo);
      
      if (index >= 0) {
        _carrito[index].cantidad++;
      } else {
        _carrito.add(ItemCarrito(
          codigo: codigo,
          nombre: nombre,
          precio: precio,
          cantidad: 1,
          imagenUrl: imagen,
        ));
      }
      
      _calcularTotal();
    });
    
    HapticFeedback.mediumImpact();
  }

  void _registrarNuevo(String codigo) async {
    _ocupado = true;
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 20),
            const Text('Buscando información...'),
            const SizedBox(height: 8),
            Text(codigo, style: TextStyle(fontFamily: 'monospace', color: Colors.grey.shade600)),
          ],
        ),
      ),
    );
    
    final productoInfo = await VisionService.buscarPorCodigoBarras(codigo);
    
    if (!mounted) return;
    Navigator.pop(context);
    
    _ocupado = false;
    
    final nombreController = TextEditingController(text: productoInfo?.nombreCompleto ?? '');
    final precioController = TextEditingController();
    final imagenUrl = productoInfo?.imagenUrl;
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      isDismissible: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (imagenUrl != null) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Image.network(
                    imagenUrl,
                    width: 100, height: 100,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _iconoProductoNuevo(),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text('✨ Info encontrada', style: TextStyle(color: Colors.green.shade700, fontSize: 12)),
                ),
              ] else
                _iconoProductoNuevo(),
              
              const SizedBox(height: 16),
              const Text('Producto nuevo', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(codigo, style: TextStyle(fontFamily: 'monospace', color: Colors.blue.shade700, fontWeight: FontWeight.w600)),
              ),
              const SizedBox(height: 20),
              
              TextField(
                controller: nombreController,
                style: const TextStyle(fontSize: 18),
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  labelText: 'Nombre del producto',
                  filled: true,
                  fillColor: Colors.grey.shade50,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  prefixIcon: const Icon(Icons.inventory_2),
                ),
              ),
              const SizedBox(height: 16),
              
              TextField(
                controller: precioController,
                style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                textAlign: TextAlign.center,
                autofocus: productoInfo?.nombreCompleto != null,
                decoration: InputDecoration(
                  labelText: 'Precio',
                  prefixText: 'S/ ',
                  prefixStyle: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.green.shade700),
                  filled: true,
                  fillColor: Colors.green.shade50,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 24),
              
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    final nombre = nombreController.text.trim();
                    final precioStr = precioController.text.trim().replaceAll(',', '.');
                    final precio = double.tryParse(precioStr) ?? 0;
                    
                    if (nombre.isEmpty || precio <= 0) {
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        const SnackBar(content: Text('Completa nombre y precio'), backgroundColor: Colors.orange),
                      );
                      return;
                    }
                    
                    Navigator.pop(ctx);
                    
                    await ApiService.crearProducto(nombre: nombre);
                    
                    _agregarAlCarrito({
                      'codigo': codigo,
                      'nombre': nombre,
                      'precio': precio,
                      'imagenUrl': imagenUrl,
                    });
                    
                    if (_esTelefono) _cargarProductos();
                  },
                  icon: const Icon(Icons.add_shopping_cart, color: Colors.white, size: 26),
                  label: const Text('Agregar al carrito', style: TextStyle(fontSize: 18, color: Colors.white, fontWeight: FontWeight.w600)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green.shade600,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancelar'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _iconoProductoNuevo() {
    return Container(
      width: 80, height: 80,
      decoration: BoxDecoration(color: Colors.orange.shade50, shape: BoxShape.circle),
      child: Icon(Icons.add_box, size: 40, color: Colors.orange.shade400),
    );
  }

  void _calcularTotal() {
    _total = _carrito.fold(0, (sum, item) => sum + (item.precio * item.cantidad));
  }

  void _aumentarCantidad(int index) {
    setState(() {
      _carrito[index].cantidad++;
      _calcularTotal();
    });
    HapticFeedback.selectionClick();
  }

  void _disminuirCantidad(int index) {
    setState(() {
      if (_carrito[index].cantidad > 1) {
        _carrito[index].cantidad--;
      } else {
        _carrito.removeAt(index);
      }
      _calcularTotal();
    });
    HapticFeedback.selectionClick();
  }

  void _eliminarItem(int index) {
    setState(() {
      _carrito.removeAt(index);
      _calcularTotal();
    });
    HapticFeedback.mediumImpact();
  }

  void _limpiarCarrito() {
    if (_carrito.isEmpty) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Limpiar carrito?'),
        content: Text('Se eliminarán ${_carrito.length} productos'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              setState(() {
                _carrito.clear();
                _total = 0;
                _clienteAsignado = null;
                _preciosCliente = {};
              });
              HapticFeedback.heavyImpact();
            },
            child: const Text('Limpiar', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _cobrar() async {
    if (_carrito.isEmpty) return;
    
    HapticFeedback.heavyImpact();
    
    final totalCobrado = _total;
    final cantidadItems = _carrito.length;
    final cantidadUnidades = _carrito.fold<int>(0, (sum, item) => sum + item.cantidad);
    
    final productosParaPedido = _carrito.map((item) => {
      'codigo': item.codigo,
      'nombre': item.nombre,
      'precio': item.precio,
      'cantidad': item.cantidad,
      'subtotal': item.precio * item.cantidad,
    }).toList();
    
    final whatsapp = _clienteAsignado?['whatsapp'] ?? '000000000';
    final nombreCliente = _clienteAsignado != null
        ? (_clienteAsignado!['nombreNegocio'] ?? _clienteAsignado!['nombreResponsable'] ?? _clienteAsignado!['nombre'] ?? 'Cliente')
        : 'Venta en tienda';
    
    final result = await ApiService.crearPedido(
      whatsapp: whatsapp,
      cliente: nombreCliente,
      telefono: _clienteAsignado?['telefono']?.toString(),
      direccion: _clienteAsignado?['direccion']?.toString(),
      ciudad: (_clienteAsignado?['ciudad']?.toString() ?? '').isNotEmpty ? _clienteAsignado!['ciudad'].toString() : ((_clienteAsignado?['distrito']?.toString() ?? '').isNotEmpty ? _clienteAsignado!['distrito'].toString() : null),
      departamento: (_clienteAsignado?['departamento']?.toString() ?? '').isNotEmpty ? _clienteAsignado!['departamento'].toString() : null,
      productos: productosParaPedido,
      total: totalCobrado,
      observaciones: _clienteAsignado != null
          ? 'Venta a cliente - $cantidadUnidades unidades'
          : 'Venta directa - $cantidadUnidades unidades',
      estado: 'COMPLETADO',
      origen: 'TIENDA',
    );

    final nuevoPedido = result.isSuccess ? result.data?['pedido'] as Map<String, dynamic>? : null;

    setState(() {
      _carrito.clear();
      _total = 0;
      _clienteAsignado = null;
      _preciosCliente = {};
    });

    if (!mounted) return;
    
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.check_circle, size: 64, color: Colors.green.shade500),
            ),
            const SizedBox(height: 20),
            const Text('¡Venta completada!', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            if (nombreCliente != 'Venta en tienda') ...[
              const SizedBox(height: 8),
              Text('Cliente: $nombreCliente', style: TextStyle(color: Colors.grey.shade600)),
            ],
            const SizedBox(height: 20),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  Text(
                    'S/ ${totalCobrado.toStringAsFixed(2)}',
                    style: TextStyle(fontSize: 42, fontWeight: FontWeight.bold, color: Colors.green.shade700),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '$cantidadItems productos • $cantidadUnidades unidades',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            if (nuevoPedido != null)
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: Colors.transparent,
                      builder: (_) => DetallePedidoSheet(
                        pedido: nuevoPedido,
                        onActualizado: () {},
                      ),
                    );
                  },
                  icon: const Icon(Icons.receipt_long, size: 18),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue.shade600,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  label: const Text('Ver pedido', style: TextStyle(fontSize: 16, color: Colors.white, fontWeight: FontWeight.w600)),
                ),
              ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(ctx),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green.shade600,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: const Text('Continuar', style: TextStyle(fontSize: 18, color: Colors.white, fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==================== BUILD ====================

  @override
  Widget build(BuildContext context) {
    if (_esTelefono) {
      return _buildLayoutTelefono();
    } else {
      return _buildLayoutSunmi();
    }
  }

  // ==================== LAYOUT TELÉFONO (con tabs) ====================

  Widget _buildLayoutTelefono() {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        backgroundColor: Colors.blue.shade600,
        foregroundColor: Colors.white,
        elevation: 0,
        toolbarHeight: 0,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          indicatorWeight: 3,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
          tabs: [
            const Tab(
              icon: Icon(Icons.inventory_2, size: 24),
              text: 'Productos',
            ),
            Tab(
              icon: Badge(
                label: Text('${_carrito.fold<int>(0, (sum, i) => sum + i.cantidad)}'),
                isLabelVisible: _carrito.isNotEmpty,
                backgroundColor: Colors.orange,
                child: const Icon(Icons.shopping_cart, size: 24),
              ),
              text: 'Carrito',
            ),
          ],
        ),
      ),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        behavior: HitTestBehavior.translucent,
        child: Column(
          children: [
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildTabProductos(),
                  _buildTabCarrito(),
                ],
              ),
            ),
            _buildBarraInferiorTelefono(),
          ],
        ),
      ),
    );
  }

  Widget _buildTabProductos() {
    return Column(
      children: [
        // Buscador con botón de escanear
        Container(
          padding: const EdgeInsets.all(12),
          color: Colors.white,
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  onChanged: _filtrarProductos,
                  decoration: InputDecoration(
                    hintText: 'Buscar producto...',
                    hintStyle: TextStyle(color: Colors.grey.shade400),
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _busqueda.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () => _filtrarProductos(''),
                          )
                        : null,
                    filled: true,
                    fillColor: Colors.grey.shade100,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              // Botón escanear
              Material(
                color: Colors.blue.shade600,
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: _abrirEscanerCamara,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    child: const Icon(Icons.qr_code_scanner, color: Colors.white, size: 28),
                  ),
                ),
              ),
            ],
          ),
        ),
        
        // Lista de productos
        Expanded(
          child: _cargandoProductos
              ? const Center(child: CircularProgressIndicator())
              : _productosFiltrados.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.inventory_2_outlined, size: 64, color: Colors.grey.shade300),
                          const SizedBox(height: 12),
                          Text(
                            _busqueda.isEmpty ? 'No hay productos' : 'Sin resultados',
                            style: TextStyle(fontSize: 18, color: Colors.grey.shade500),
                          ),
                          if (_busqueda.isEmpty) ...[
                            const SizedBox(height: 16),
                            ElevatedButton.icon(
                              onPressed: _abrirEscanerCamara,
                              icon: const Icon(Icons.qr_code_scanner),
                              label: const Text('Escanear producto'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blue.shade600,
                                foregroundColor: Colors.white,
                              ),
                            ),
                          ],
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _cargarProductos,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(8),
                        itemCount: _productosFiltrados.length,
                        itemBuilder: (context, index) {
                          final p = _productosFiltrados[index];
                          return _buildProductoCard(p);
                        },
                      ),
                    ),
        ),
      ],
    );
  }

  Widget _buildProductoCard(Map<String, dynamic> producto) {
    final nombre = producto['nombre'] ?? '';
    final precioBase = (producto['precio'] as num?)?.toDouble() ?? 0;
    final codigo = producto['codigo'] ?? '';
    final imagenUrl = producto['imagenUrl'] as String?;
    final stock = producto['stock'] ?? 0;
    
    // Precio personalizado si existe
    final precioPersonalizado = _preciosCliente[codigo];
    final precioFinal = precioPersonalizado ?? precioBase;
    final tieneDescuento = precioPersonalizado != null && precioPersonalizado < precioBase;
    
    final cantidadEnCarrito = _carrito
        .where((i) => i.codigo == codigo)
        .fold(0, (sum, i) => sum + i.cantidad);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        elevation: 1,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _agregarAlCarrito(producto),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: imagenUrl != null && imagenUrl.isNotEmpty
                      ? Image.network(
                          imagenUrl,
                          width: 60, height: 60,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _placeholderProducto(),
                        )
                      : _placeholderProducto(),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        nombre,
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    'S/ ${precioFinal.toStringAsFixed(2)}',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: tieneDescuento ? Colors.orange.shade600 : Colors.green.shade600,
                                    ),
                                  ),
                                  if (tieneDescuento) ...[                                    const SizedBox(width: 6),
                                    Text(
                                      'S/ ${precioBase.toStringAsFixed(2)}',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: Colors.grey.shade400,
                                        decoration: TextDecoration.lineThrough,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              if (tieneDescuento)
                                Container(
                                  margin: const EdgeInsets.only(top: 2),
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: Colors.orange.shade100,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    'PRECIO ESPECIAL',
                                    style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.orange.shade700),
                                  ),
                                ),
                            ],
                          ),
                          const Spacer(),
                          Text(
                            'Stock: $stock',
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Stack(
                  children: [
                    Container(
                      width: 48, height: 48,
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(Icons.add, color: Colors.blue.shade600, size: 28),
                    ),
                    if (cantidadEnCarrito > 0)
                      Positioned(
                        right: 0, top: 0,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(
                            color: Colors.orange,
                            shape: BoxShape.circle,
                          ),
                          child: Text(
                            '$cantidadEnCarrito',
                            style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _placeholderProducto() {
    return Container(
      width: 60, height: 60,
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(Icons.inventory_2, color: Colors.blue.shade300, size: 28),
    );
  }

  Widget _buildTabCarrito() {
    return Column(
      children: [
        // Asignar cliente (opcional)
        Container(
          padding: const EdgeInsets.all(12),
          color: Colors.white,
          child: InkWell(
            onTap: _mostrarSelectorCliente,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _clienteAsignado != null ? Colors.green.shade50 : Colors.grey.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _clienteAsignado != null ? Colors.green.shade200 : Colors.grey.shade200,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _clienteAsignado != null ? Icons.person : Icons.person_add_alt_1,
                    color: _clienteAsignado != null ? Colors.green.shade600 : Colors.grey.shade500,
                    size: 22,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _clienteAsignado != null
                              ? (_clienteAsignado!['nombreNegocio'] ?? _clienteAsignado!['nombreResponsable'] ?? _clienteAsignado!['nombre'] ?? 'Cliente')
                              : 'Asignar cliente (opcional)',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: _clienteAsignado != null ? Colors.green.shade700 : Colors.grey.shade600,
                          ),
                        ),
                        if (_clienteAsignado != null)
                          Text(
                            _clienteAsignado!['whatsapp'] ?? '',
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                          ),
                      ],
                    ),
                  ),
                  Icon(
                    _clienteAsignado != null ? Icons.edit : Icons.chevron_right,
                    color: Colors.grey.shade400,
                  ),
                ],
              ),
            ),
          ),
        ),
        
        // Lista o vacío
        Expanded(
          child: _carrito.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.shopping_cart_outlined, size: 80, color: Colors.grey.shade300),
                      const SizedBox(height: 16),
                      Text('Carrito vacío', style: TextStyle(fontSize: 20, color: Colors.grey.shade500)),
                      const SizedBox(height: 8),
                      Text('Agrega productos desde la lista', style: TextStyle(color: Colors.grey.shade400)),
                      const SizedBox(height: 24),
                      OutlinedButton.icon(
                        onPressed: () => _tabController?.animateTo(0),
                        icon: const Icon(Icons.arrow_back),
                        label: const Text('Ver productos'),
                      ),
                    ],
                  ),
                )
              : Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      color: Colors.blue.shade50,
                      child: Row(
                        children: [
                          Icon(Icons.shopping_cart, color: Colors.blue.shade700, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            '${_carrito.length} productos',
                            style: TextStyle(fontWeight: FontWeight.w600, color: Colors.blue.shade700),
                          ),
                          const Spacer(),
                          TextButton.icon(
                            onPressed: _limpiarCarrito,
                            icon: Icon(Icons.delete_outline, size: 18, color: Colors.red.shade400),
                            label: Text('Limpiar', style: TextStyle(color: Colors.red.shade400, fontSize: 13)),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: _carrito.length,
                        itemBuilder: (context, index) => _buildItemCarritoTelefono(index),
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _buildItemCarritoTelefono(int index) {
    final item = _carrito[index];
    
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 4)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  item.nombre,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                icon: Icon(Icons.close, size: 20, color: Colors.grey.shade400),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () => _eliminarItem(index),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'S/ ${item.precio.toStringAsFixed(2)} c/u',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    InkWell(
                      onTap: () => _disminuirCantidad(index),
                      child: Container(
                        width: 40, height: 40,
                        alignment: Alignment.center,
                        child: Icon(Icons.remove, size: 20, color: Colors.grey.shade700),
                      ),
                    ),
                    Container(
                      width: 45,
                      alignment: Alignment.center,
                      child: Text(
                        '${item.cantidad}',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                    ),
                    InkWell(
                      onTap: () => _aumentarCantidad(index),
                      child: Container(
                        width: 40, height: 40,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: const BorderRadius.horizontal(right: Radius.circular(9)),
                        ),
                        child: Icon(Icons.add, size: 20, color: Colors.blue.shade700),
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              Text(
                'S/ ${(item.precio * item.cantidad).toStringAsFixed(2)}',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.green.shade700),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBarraInferiorTelefono() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10, offset: const Offset(0, -2))],
      ),
      child: SafeArea(
        child: Row(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Total', style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
                Text(
                  'S/ ${_total.toStringAsFixed(2)}',
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.green.shade700),
                ),
              ],
            ),
            const SizedBox(width: 20),
            Expanded(
              child: SizedBox(
                height: 56,
                child: ElevatedButton.icon(
                  onPressed: _carrito.isEmpty ? null : _cobrar,
                  icon: Icon(Icons.payment, size: 24, color: _carrito.isEmpty ? Colors.grey : Colors.white),
                  label: Text(
                    _carrito.isEmpty ? 'Agregar productos' : 'COBRAR',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: _carrito.isEmpty ? Colors.grey : Colors.white,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green.shade600,
                    disabledBackgroundColor: Colors.grey.shade200,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==================== LAYOUT SUNMI (original) ====================

  Widget _buildLayoutSunmi() {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        behavior: HitTestBehavior.translucent,
        child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            color: Colors.blue.shade600,
            child: Row(
              children: [
                const Icon(Icons.qr_code_scanner, color: Colors.white, size: 22),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text('Escanea para agregar', style: TextStyle(color: Colors.white, fontSize: 15)),
                ),
                if (_carrito.isNotEmpty)
                  GestureDetector(
                    onTap: _limpiarCarrito,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text('Limpiar', style: TextStyle(color: Colors.white, fontSize: 14)),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: _carrito.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.shopping_cart_outlined, size: 100, color: Colors.grey.shade300),
                        const SizedBox(height: 16),
                        Text('Carrito vacío', style: TextStyle(fontSize: 24, color: Colors.grey.shade400)),
                        const SizedBox(height: 8),
                        Text('Escanea un producto', style: TextStyle(fontSize: 16, color: Colors.grey.shade400)),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _carrito.length,
                    itemBuilder: (context, index) => _buildItemCarritoSunmi(index),
                  ),
          ),
          _buildBarraInferiorSunmi(),
        ],
      ),
      ),
    );
  }

  Widget _buildItemCarritoSunmi(int index) {
    final item = _carrito[index];
    
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6)],
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: item.imagenUrl != null
                ? Image.network(item.imagenUrl!, width: 70, height: 70, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _placeholderImagen())
                : _placeholderImagen(),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.nombre, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600), maxLines: 2, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                Text('S/ ${item.precio.toStringAsFixed(2)}', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.green.shade700)),
              ],
            ),
          ),
          Container(
            decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(14)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  onTap: () => _disminuirCantidad(index),
                  child: Container(width: 50, height: 50, alignment: Alignment.center, child: const Icon(Icons.remove, size: 28)),
                ),
                Container(width: 40, alignment: Alignment.center, child: Text('${item.cantidad}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold))),
                GestureDetector(
                  onTap: () => _aumentarCantidad(index),
                  child: Container(
                    width: 50, height: 50,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: Colors.blue.shade100, borderRadius: BorderRadius.circular(14)),
                    child: Icon(Icons.add, size: 28, color: Colors.blue.shade700),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _placeholderImagen() {
    return Container(
      width: 70, height: 70,
      decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(12)),
      child: Icon(Icons.inventory_2, color: Colors.blue.shade300, size: 35),
    );
  }

  Widget _buildBarraInferiorSunmi() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 8, offset: const Offset(0, -2))],
      ),
      child: SafeArea(
        child: SizedBox(
          width: double.infinity,
          height: 65,
          child: ElevatedButton(
            onPressed: _carrito.isEmpty ? null : _cobrar,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green.shade600,
              disabledBackgroundColor: Colors.grey.shade300,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.payment, size: 28, color: _carrito.isEmpty ? Colors.grey : Colors.white),
                const SizedBox(width: 12),
                Text('COBRAR', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: _carrito.isEmpty ? Colors.grey : Colors.white)),
                const SizedBox(width: 16),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: _carrito.isEmpty ? Colors.grey.shade400 : Colors.white.withOpacity(0.25),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text('S/ ${_total.toStringAsFixed(2)}', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: _carrito.isEmpty ? Colors.grey.shade600 : Colors.white)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ==================== SELECTOR DE CLIENTE ====================

class _SelectorClienteSheet extends StatefulWidget {
  final Map<String, dynamic>? clienteActual;
  final Function(Map<String, dynamic>) onClienteSeleccionado;
  final VoidCallback onQuitarCliente;

  const _SelectorClienteSheet({
    required this.clienteActual,
    required this.onClienteSeleccionado,
    required this.onQuitarCliente,
  });

  @override
  State<_SelectorClienteSheet> createState() => _SelectorClienteSheetState();
}

class _SelectorClienteSheetState extends State<_SelectorClienteSheet> {
  List<Map<String, dynamic>> _clientes = [];
  List<Map<String, dynamic>> _clientesFiltrados = [];
  bool _cargando = true;
  String _busqueda = '';

  @override
  void initState() {
    super.initState();
    _cargarClientes();
  }

  Future<void> _cargarClientes() async {
    final result = await ApiService.getClientes();
    if (result.isSuccess && mounted) {
      setState(() {
        _clientes = result.data ?? [];
        _clientesFiltrados = _clientes;
        _cargando = false;
      });
    } else {
      setState(() => _cargando = false);
    }
  }

  void _filtrar(String query) {
    setState(() {
      _busqueda = query;
      if (query.isEmpty) {
        _clientesFiltrados = _clientes;
      } else {
        final q = query.toLowerCase();
        _clientesFiltrados = _clientes.where((c) =>
          (c['nombreNegocio'] ?? '').toLowerCase().contains(q) ||
          (c['nombreResponsable'] ?? '').toLowerCase().contains(q) ||
          (c['nombre'] ?? '').toLowerCase().contains(q) ||
          (c['whatsapp'] ?? '').contains(query)
        ).toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.green.shade50,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Icon(Icons.person_search, color: Colors.green.shade700, size: 26),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text('Asignar cliente', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  onChanged: _filtrar,
                  decoration: InputDecoration(
                    hintText: 'Buscar cliente...',
                    prefixIcon: const Icon(Icons.search),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          if (widget.clienteActual != null)
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.person_remove, color: Colors.red.shade400),
              ),
              title: const Text('Quitar cliente asignado'),
              subtitle: const Text('Volver a venta anónima'),
              onTap: widget.onQuitarCliente,
            ),
          
          const Divider(height: 1),
          
          Expanded(
            child: _cargando
                ? const Center(child: CircularProgressIndicator())
                : _clientesFiltrados.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.people_outline, size: 48, color: Colors.grey.shade300),
                            const SizedBox(height: 12),
                            Text(
                              _busqueda.isEmpty ? 'No hay clientes' : 'Sin resultados',
                              style: TextStyle(color: Colors.grey.shade500),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: _clientesFiltrados.length,
                        itemBuilder: (context, index) {
                          final cliente = _clientesFiltrados[index];
                          final nombre = cliente['nombreNegocio'] ?? cliente['nombreResponsable'] ?? cliente['nombre'] ?? 'Sin nombre';
                          final whatsapp = cliente['whatsapp'] ?? '';
                          final esActual = widget.clienteActual?['id'] == cliente['id'];
                          
                          return ListTile(
                            leading: Container(
                              width: 45, height: 45,
                              decoration: BoxDecoration(
                                color: esActual ? Colors.green.shade100 : Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(23),
                              ),
                              child: Center(
                                child: Text(
                                  nombre.isNotEmpty ? nombre[0].toUpperCase() : '?',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: esActual ? Colors.green.shade700 : Colors.grey.shade600,
                                  ),
                                ),
                              ),
                            ),
                            title: Text(
                              nombre,
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: esActual ? Colors.green.shade700 : null,
                              ),
                            ),
                            subtitle: Text(whatsapp),
                            trailing: esActual
                                ? Icon(Icons.check_circle, color: Colors.green.shade600)
                                : Icon(Icons.chevron_right, color: Colors.grey.shade400),
                            onTap: () => widget.onClienteSeleccionado(cliente),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

// ==================== ESCÁNER CON CÁMARA ====================

class _EscanerCamaraScreen extends StatefulWidget {
  final Function(String) onCodigoEscaneado;

  const _EscanerCamaraScreen({required this.onCodigoEscaneado});

  @override
  State<_EscanerCamaraScreen> createState() => _EscanerCamaraScreenState();
}

class _EscanerCamaraScreenState extends State<_EscanerCamaraScreen> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    facing: CameraFacing.back,
  );
  bool _escaneado = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Escanear código'),
        actions: [
          IconButton(icon: const Icon(Icons.flash_on), onPressed: () => _controller.toggleTorch()),
          IconButton(icon: const Icon(Icons.cameraswitch), onPressed: () => _controller.switchCamera()),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: (capture) {
              if (_escaneado) return;
              final barcode = capture.barcodes.firstOrNull;
              if (barcode?.rawValue != null) {
                _escaneado = true;
                HapticFeedback.heavyImpact();
                widget.onCodigoEscaneado(barcode!.rawValue!);
              }
            },
          ),
          Center(
            child: Container(
              width: 260, height: 260,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white, width: 3),
                borderRadius: BorderRadius.circular(20),
              ),
            ),
          ),
          Positioned(
            bottom: 100, left: 0, right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(30)),
                child: const Text('Apunta al código de barras', style: TextStyle(color: Colors.white, fontSize: 16)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ItemCarrito {
  final String codigo;
  final String nombre;
  double precio;  // Mutable para poder actualizar con precios personalizados
  final String? imagenUrl;
  int cantidad;

  ItemCarrito({required this.codigo, required this.nombre, required this.precio, required this.cantidad, this.imagenUrl});
}
