import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../services/api_service.dart';
import '../../services/vision_service.dart';
import '../detalle_producto_screen.dart';

class ProductosTab extends StatefulWidget {
  final bool isActive;
  
  const ProductosTab({super.key, this.isActive = true});

  @override
  State<ProductosTab> createState() => _ProductosTabState();
}

class _ProductosTabState extends State<ProductosTab> with SingleTickerProviderStateMixin {
  late AnimationController _shimmerCtrl;
  final List<Map<String, dynamic>> _productos = [];
  final ScrollController _scrollController = ScrollController();
  final FocusNode _scannerFocusNode = FocusNode();
  final FocusNode _searchFocusNode = FocusNode();
  final TextEditingController _codigoController = TextEditingController();
  
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hayMas = true;
  String? _error;
  String _busqueda = '';
  int _paginaActual = 1;
  int _total = 0;
  
  // Para el escáner
  String _scanBuffer = '';
  DateTime _lastKeyTime = DateTime.now();
  bool _buscandoProducto = false;
  bool _modalAbierto = false;
  bool _enOtraPantalla = false;
  
  static const int _limite = 20;

  @override
  void initState() {
    super.initState();
    _shimmerCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);
    _scrollController.addListener(_onScroll);
    _cargarProductos();
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
  }

  @override
  void dispose() {
    _shimmerCtrl.dispose();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _scannerFocusNode.dispose();
    _searchFocusNode.dispose();
    _codigoController.dispose();
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    super.dispose();
  }

  bool _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    if (_buscandoProducto || _modalAbierto || _enOtraPantalla) return false;
    if (!widget.isActive) return false;
    
    final now = DateTime.now();
    final timeDiff = now.difference(_lastKeyTime).inMilliseconds;
    
    if (timeDiff > 100 && _scanBuffer.isNotEmpty) {
      _scanBuffer = '';
    }
    
    _lastKeyTime = now;
    
    if (event.logicalKey == LogicalKeyboardKey.enter) {
      if (_scanBuffer.length >= 4) {
        _procesarCodigoEscaneado(_scanBuffer);
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

  Future<void> _procesarCodigoEscaneado(String codigo) async {
    debugPrint('📦 Código escaneado: $codigo');
    
    setState(() => _buscandoProducto = true);
    HapticFeedback.heavyImpact();
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            const SizedBox(width: 50, height: 50, child: CircularProgressIndicator(strokeWidth: 3)),
            const SizedBox(height: 24),
            const Text('Buscando producto...', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 18)),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(codigo, 
                style: TextStyle(
                  fontFamily: 'monospace', 
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue.shade700,
                  letterSpacing: 2,
                )),
            ),
          ],
        ),
      ),
    );
    
    final resultado = await ApiService.buscarProductoPorCodigo(codigo);
    
    if (!mounted) return;
    Navigator.pop(context);
    
    setState(() => _buscandoProducto = false);
    
    if (resultado.isSuccess && resultado.data != null) {
      _mostrarProductoEncontrado(resultado.data!, codigo);
    } else {
      _mostrarRegistrarNuevo(codigo);
    }
  }

  void _mostrarProductoEncontrado(Map<String, dynamic> producto, String codigo) {
    HapticFeedback.mediumImpact();
    _modalAbierto = true;
    
    final precioActual = (producto['precio'] ?? 0).toDouble();
    final precioController = TextEditingController(text: precioActual.toStringAsFixed(2));
    final stockActual = producto['stock'] ?? 0;
    final imagenUrl = producto['imagenUrl'] as String?;
    bool guardando = false;
    bool precioModificado = false;
    
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
          child: Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            padding: const EdgeInsets.all(24),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (imagenUrl != null && imagenUrl.isNotEmpty)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Image.network(
                        imagenUrl,
                        width: 100, height: 100,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          width: 100, height: 100,
                          decoration: BoxDecoration(
                            color: Colors.green.shade50,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Icon(Icons.check_circle, color: Colors.green.shade600, size: 50),
                        ),
                      ),
                    )
                  else
                    Container(
                      width: 80, height: 80,
                      decoration: BoxDecoration(color: Colors.green.shade50, shape: BoxShape.circle),
                      child: Icon(Icons.check_circle, color: Colors.green.shade600, size: 50),
                    ),
                  
                  const SizedBox(height: 16),
                  Text(
                    producto['nombre'] ?? 'Sin nombre',
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      codigo,
                      style: TextStyle(fontFamily: 'monospace', fontSize: 14, color: Colors.grey.shade600),
                    ),
                  ),
                  const SizedBox(height: 24),
                  
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.green.shade200, width: 2),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Icon(Icons.edit, color: Colors.green.shade700, size: 24),
                            const SizedBox(width: 8),
                            Text(
                              'PRECIO',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.green.shade700,
                                letterSpacing: 1,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: precioController,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 48,
                            fontWeight: FontWeight.bold,
                            color: Colors.green.shade700,
                          ),
                          decoration: InputDecoration(
                            prefixText: 'S/ ',
                            prefixStyle: TextStyle(
                              fontSize: 32,
                              fontWeight: FontWeight.bold,
                              color: Colors.green.shade700,
                            ),
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide.none,
                            ),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
                          ),
                          onChanged: (value) {
                            setModalState(() => precioModificado = true);
                          },
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Toca para modificar el precio',
                          style: TextStyle(fontSize: 14, color: Colors.green.shade600),
                        ),
                      ],
                    ),
                  ),
                  
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.inventory_2, color: Colors.blue.shade700, size: 28),
                        const SizedBox(width: 12),
                        Text(
                          'Stock: $stockActual unidades',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                            color: Colors.blue.shade700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  
                  if (guardando)
                    const Padding(
                      padding: EdgeInsets.all(20),
                      child: CircularProgressIndicator(),
                    )
                  else
                    Column(
                      children: [
                        if (precioModificado)
                          SizedBox(
                            width: double.infinity,
                            height: 64,
                            child: ElevatedButton.icon(
                              onPressed: () async {
                                final precioStr = precioController.text.trim().replaceAll(',', '.');
                                final nuevoPrecio = double.tryParse(precioStr);
                                if (nuevoPrecio == null || nuevoPrecio <= 0) {
                                  _mostrarError('Precio inválido');
                                  return;
                                }
                                
                                setModalState(() => guardando = true);
                                
                                final result = await ApiService.actualizarProducto(
                                  codigo: codigo,
                                  nombre: producto['nombre'],
                                  precio: nuevoPrecio,
                                  stock: stockActual,
                                );
                                
                                if (!context.mounted) return;
                                
                                if (result.isSuccess) {
                                  HapticFeedback.heavyImpact();
                                  _modalAbierto = false;
                                  Navigator.pop(context);
                                  ScaffoldMessenger.of(this.context).showSnackBar(
                                    SnackBar(
                                      content: Text('✅ Precio actualizado a S/ ${nuevoPrecio.toStringAsFixed(2)}'),
                                      backgroundColor: Colors.green,
                                      behavior: SnackBarBehavior.floating,
                                    ),
                                  );
                                  _cargarProductos(refresh: true);
                                } else {
                                  setModalState(() => guardando = false);
                                  _mostrarError(result.error ?? 'Error al guardar');
                                }
                              },
                              icon: const Icon(Icons.save, size: 28),
                              label: const Text('GUARDAR PRECIO', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green.shade600,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              ),
                            ),
                          ),
                        
                        if (precioModificado) const SizedBox(height: 12),
                        
                        Row(
                          children: [
                            Expanded(
                              child: SizedBox(
                                height: 60,
                                child: OutlinedButton(
                                  onPressed: () {
                                    _modalAbierto = false;
                                    Navigator.pop(context);
                                  },
                                  style: OutlinedButton.styleFrom(
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                    side: BorderSide(color: Colors.grey.shade400),
                                  ),
                                  child: Text('Cerrar', style: TextStyle(fontSize: 18, color: Colors.grey.shade700)),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: SizedBox(
                                height: 60,
                                child: ElevatedButton.icon(
                                  onPressed: () {
                                    _modalAbierto = false;
                                    Navigator.pop(context);
                                    _irAEditarProducto(producto);
                                  },
                                  icon: const Icon(Icons.edit, size: 24),
                                  label: const Text('Más opciones', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.blue.shade600,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        ),
      ),
    ).whenComplete(() => _modalAbierto = false);
  }

  void _mostrarRegistrarNuevo(String codigo) async {
    HapticFeedback.vibrate();
    _modalAbierto = true;

    final nombreController = TextEditingController();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 20),
            const Text('Buscando información...', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text(codigo, style: TextStyle(fontFamily: 'monospace', color: Colors.grey.shade600)),
          ],
        ),
      ),
    );

    final productoInfo = await VisionService.buscarPorCodigoBarras(codigo);

    if (!mounted) return;
    Navigator.pop(context);

    if (productoInfo != null && productoInfo.nombreCompleto.isNotEmpty) {
      nombreController.text = productoInfo.nombreCompleto;
    }

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 80, height: 80,
                decoration: BoxDecoration(color: Colors.orange.shade50, shape: BoxShape.circle),
                child: Icon(Icons.add_box, color: Colors.orange.shade600, size: 45),
              ),
              const SizedBox(height: 20),
              const Text('Nuevo producto', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text('Luego podrás agregar presentaciones con precio y stock.',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 14), textAlign: TextAlign.center),
              const SizedBox(height: 20),
              TextField(
                controller: nombreController,
                textCapitalization: TextCapitalization.words,
                style: const TextStyle(fontSize: 18),
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'Nombre del producto *',
                  hintText: 'Ej: Café Blend',
                  filled: true, fillColor: Colors.grey.shade50,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    final nombre = nombreController.text.trim();
                    if (nombre.isEmpty) { _mostrarError('Ingresa el nombre'); return; }

                    final result = await ApiService.crearProducto(nombre: nombre);

                    if (!context.mounted) return;

                    if (result.isSuccess) {
                      HapticFeedback.heavyImpact();
                      _modalAbierto = false;
                      Navigator.pop(context);
                      _cargarProductos(refresh: true);
                      final nuevoProducto = result.data!;
                      if (mounted) _irAEditarProducto(nuevoProducto);
                    } else {
                      _mostrarError(result.error ?? 'Error al guardar');
                    }
                  },
                  icon: const Icon(Icons.arrow_forward, size: 24),
                  label: const Text('Crear y configurar', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green.shade600,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () { _modalAbierto = false; Navigator.pop(context); },
                child: const Text('Cancelar', style: TextStyle(fontSize: 16)),
              ),
            ],
          ),
        ),
      ),
    ).whenComplete(() => _modalAbierto = false);
  }

  void _mostrarError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red, behavior: SnackBarBehavior.floating),
    );
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      _cargarMasProductos();
    }
  }

  Future<void> _cargarProductos({bool refresh = false}) async {
    if (refresh) {
      setState(() { _productos.clear(); _paginaActual = 1; _hayMas = true; });
    }

    setState(() { _isLoading = _productos.isEmpty; _error = null; });

    final result = await ApiService.getProductos(
      buscar: _busqueda.isNotEmpty ? _busqueda : null,
      pagina: 1,
      limite: _limite,
    );

    setState(() {
      _isLoading = false;
      if (result.isSuccess && result.data != null) {
        _productos.clear();
        _productos.addAll(result.data!.productos);
        _total = result.data!.total;
        _hayMas = result.data!.hayMas;
        _paginaActual = 1;
      } else {
        _error = result.error;
      }
    });
  }

  Future<void> _cargarMasProductos() async {
    if (_isLoadingMore || !_hayMas) return;

    setState(() => _isLoadingMore = true);

    final result = await ApiService.getProductos(
      buscar: _busqueda.isNotEmpty ? _busqueda : null,
      pagina: _paginaActual + 1,
      limite: _limite,
    );

    setState(() {
      _isLoadingMore = false;
      if (result.isSuccess && result.data != null) {
        _productos.addAll(result.data!.productos);
        _paginaActual++;
        _hayMas = result.data!.hayMas;
      }
    });
  }

  void _buscar(String query) {
    setState(() => _busqueda = query);
    _cargarProductos(refresh: true);
  }

  void _irAEditarProducto(Map<String, dynamic> producto) async {
    _searchFocusNode.unfocus();
    FocusScope.of(context).unfocus();
    setState(() => _enOtraPantalla = true);

    final resultado = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => DetalleProductoScreen(producto: producto)),
    );
    
    if (mounted) {
      setState(() => _enOtraPantalla = false);
      if (resultado == true) _cargarProductos(refresh: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        behavior: HitTestBehavior.translucent,
        child: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            color: Colors.white,
            child: Column(
              children: [
                TextField(
                  focusNode: _searchFocusNode,
                  onChanged: (value) {
                    Future.delayed(const Duration(milliseconds: 500), () {
                      if (value == _busqueda || (value.isEmpty && _busqueda.isEmpty)) return;
                      _buscar(value);
                    });
                  },
                  decoration: InputDecoration(
                    hintText: 'Buscar producto por nombre...',
                    prefixIcon: const Icon(Icons.search),
                    filled: true,
                    fillColor: Colors.grey.shade100,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  ),
                ),
                if (_total > 0 && !_isLoading)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text('$_total producto${_total != 1 ? 's' : ''}', style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                  ),
                Builder(builder: (_) {
                  final pendingCount = _productos.where((p) => p['pendingTueste'] == true).length;
                  if (pendingCount == 0) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.red.shade300),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.local_fire_department_rounded, color: Colors.red.shade600, size: 18),
                          const SizedBox(width: 8),
                          Text(
                            '$pendingCount producto${pendingCount != 1 ? 's' : ''} con tueste pendiente',
                            style: TextStyle(color: Colors.red.shade700, fontSize: 13, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),
          Expanded(child: _buildBody()),
        ],
      ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _mostrarOpcionesNuevoProducto,
        backgroundColor: Colors.orange.shade600,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Nuevo', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
      ),
    );
  }

  void _mostrarOpcionesNuevoProducto() {
    _modalAbierto = true;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Agregar producto',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Elige cómo quieres agregar el producto',
              style: TextStyle(color: Colors.grey.shade600),
            ),
            const SizedBox(height: 24),
            
            // Opción 1: Escanear código
            _buildOpcionNuevoProducto(
              icon: Icons.qr_code_scanner,
              color: Colors.blue,
              titulo: 'Escanear código de barras',
              subtitulo: 'Busca info automáticamente',
              onTap: () {
                Navigator.pop(ctx);
                _abrirEscanerCamara();
              },
            ),
            const SizedBox(height: 12),
            
            // Opción 2: Tomar foto
            _buildOpcionNuevoProducto(
              icon: Icons.camera_alt,
              color: Colors.green,
              titulo: 'Tomar foto del producto',
              subtitulo: 'Guarda imagen del producto',
              onTap: () {
                Navigator.pop(ctx);
                _tomarFotoYCrearProducto();
              },
            ),
            const SizedBox(height: 12),
            
            // Opción 3: Manual
            _buildOpcionNuevoProducto(
              icon: Icons.edit,
              color: Colors.orange,
              titulo: 'Ingresar manualmente',
              subtitulo: 'Escribe nombre y precio',
              onTap: () {
                Navigator.pop(ctx);
                _crearProductoManual();
              },
            ),
            
            const SizedBox(height: 16),
            TextButton(
              onPressed: () {
                _modalAbierto = false;
                Navigator.pop(ctx);
              },
              child: const Text('Cancelar'),
            ),
          ],
        ),
      ),
    ).whenComplete(() => _modalAbierto = false);
  }

  Widget _buildOpcionNuevoProducto({
    required IconData icon,
    required Color color,
    required String titulo,
    required String subtitulo,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.grey.shade50,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 50, height: 50,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: color, size: 26),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(titulo, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    Text(subtitulo, style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: Colors.grey.shade400),
            ],
          ),
        ),
      ),
    );
  }

  void _abrirEscanerCamara() {
    _enOtraPantalla = true;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => _EscanerCamaraScreen(
          onCodigoEscaneado: (codigo) {
            Navigator.pop(context);
            _enOtraPantalla = false;
            _procesarCodigoEscaneado(codigo);
          },
        ),
      ),
    ).whenComplete(() => _enOtraPantalla = false);
  }

  Future<void> _tomarFotoYCrearProducto() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(source: ImageSource.camera, maxWidth: 800);
    
    if (image == null || !mounted) return;
    
    _crearProductoManual(imagenPath: image.path);
  }

  void _crearProductoManual({String? imagenPath}) {
    _modalAbierto = true;
    final nombreController = TextEditingController();
    bool guardando = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      isDismissible: true,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => Padding(
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
                Container(
                  width: 80, height: 80,
                  decoration: BoxDecoration(color: Colors.orange.shade50, shape: BoxShape.circle),
                  child: Icon(Icons.inventory_2_outlined, color: Colors.orange.shade600, size: 40),
                ),
                const SizedBox(height: 20),
                const Text('Nuevo producto', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text('Luego podrás agregar presentaciones con precio y stock.',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 14), textAlign: TextAlign.center),
                const SizedBox(height: 20),

                TextField(
                  controller: nombreController,
                  style: const TextStyle(fontSize: 18),
                  textCapitalization: TextCapitalization.words,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: 'Nombre del producto *',
                    hintText: 'Ej: Café Blend',
                    filled: true,
                    fillColor: Colors.grey.shade50,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    prefixIcon: const Icon(Icons.inventory_2),
                  ),
                ),
                const SizedBox(height: 24),

                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton.icon(
                    onPressed: guardando ? null : () async {
                      final nombre = nombreController.text.trim();
                      if (nombre.isEmpty) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          const SnackBar(content: Text('Ingresa el nombre'), backgroundColor: Colors.orange),
                        );
                        return;
                      }

                      setModalState(() => guardando = true);

                      final result = await ApiService.crearProducto(nombre: nombre);

                      if (!ctx.mounted) return;

                      if (result.isSuccess) {
                        HapticFeedback.heavyImpact();
                        _modalAbierto = false;
                        Navigator.pop(ctx);
                        _cargarProductos(refresh: true);
                        final nuevoProducto = result.data!;
                        if (mounted) _irAEditarProducto(nuevoProducto);
                      } else {
                        setModalState(() => guardando = false);
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          SnackBar(content: Text(result.error ?? 'Error al guardar'), backgroundColor: Colors.red),
                        );
                      }
                    },
                    icon: guardando
                        ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Icon(Icons.arrow_forward, color: Colors.white, size: 24),
                    label: Text(
                      guardando ? 'Creando...' : 'Crear y configurar',
                      style: const TextStyle(fontSize: 18, color: Colors.white, fontWeight: FontWeight.w600),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green.shade600,
                      disabledBackgroundColor: Colors.green.shade400,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: guardando ? null : () {
                    _modalAbierto = false;
                    Navigator.pop(ctx);
                  },
                  child: const Text('Cancelar'),
                ),
              ],
            ),
          ),
        ),
      ),
    ).whenComplete(() => _modalAbierto = false);
  }

  Widget _buildSkeletonProducto(double opacity) {
    final c = Colors.grey.withOpacity(opacity);
    final cl = Colors.grey.withOpacity(opacity * 0.6);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
      child: Row(children: [
        Container(width: 52, height: 52, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(10))),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(height: 13, width: 120, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(4))),
          const SizedBox(height: 6),
          Container(height: 11, width: 80, decoration: BoxDecoration(color: cl, borderRadius: BorderRadius.circular(4))),
          const SizedBox(height: 6),
          Container(height: 11, width: 60, decoration: BoxDecoration(color: cl, borderRadius: BorderRadius.circular(4))),
        ])),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Container(height: 16, width: 55, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(4))),
          const SizedBox(height: 6),
          Container(height: 20, width: 40, decoration: BoxDecoration(color: cl, borderRadius: BorderRadius.circular(8))),
        ]),
      ]),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return AnimatedBuilder(
        animation: _shimmerCtrl,
        builder: (_, __) {
          final opacity = 0.25 + _shimmerCtrl.value * 0.25;
          return ListView.builder(
            padding: const EdgeInsets.only(top: 8, bottom: 100),
            itemCount: 10,
            itemBuilder: (_, __) => _buildSkeletonProducto(opacity),
          );
        },
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: Colors.red.shade300),
            const SizedBox(height: 16),
            Text('Error: $_error'),
            const SizedBox(height: 16),
            ElevatedButton.icon(onPressed: () => _cargarProductos(refresh: true), icon: const Icon(Icons.refresh), label: const Text('Reintentar')),
          ],
        ),
      );
    }

    if (_productos.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inventory_2_outlined, size: 80, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(_busqueda.isEmpty ? 'No hay productos' : 'Sin resultados',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: Colors.grey.shade600)),
            const SizedBox(height: 8),
            Text(_busqueda.isEmpty ? 'Toca el botón "Nuevo" para agregar uno' : 'No se encontraron productos con "$_busqueda"',
              style: TextStyle(color: Colors.grey.shade500), textAlign: TextAlign.center),
            if (_busqueda.isEmpty) ...[
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _mostrarOpcionesNuevoProducto,
                icon: const Icon(Icons.add),
                label: const Text('Agregar producto'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange.shade600,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _cargarProductos(refresh: true),
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.only(top: 8, bottom: 100),
        itemCount: _productos.length + (_hayMas ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == _productos.length) return _buildLoadingMore();
          final producto = _productos[index];
          return _ProductoCard(producto: producto, onTap: () => _irAEditarProducto(producto));
        },
      ),
    );
  }

  Widget _buildLoadingMore() {
    return Container(
      padding: const EdgeInsets.all(16),
      alignment: Alignment.center,
      child: _isLoadingMore
          ? const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
              SizedBox(width: 12),
              Text('Cargando más...'),
            ])
          : TextButton(onPressed: _cargarMasProductos, child: const Text('Cargar más')),
    );
  }
}

class _ProductoCard extends StatelessWidget {
  final Map<String, dynamic> producto;
  final VoidCallback onTap;

  const _ProductoCard({required this.producto, required this.onTap});

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
          if (predeterminada)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Icon(Icons.star, size: 12, color: Colors.amber.shade600),
            ),
          Text(etiqueta, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(width: 8),
          Text('S/ ${precio.toStringAsFixed(2)}',
              style: TextStyle(fontSize: 13, color: Colors.green.shade700, fontWeight: FontWeight.w600)),
          const Spacer(),
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
