import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../services/api_service.dart';
import '../../services/vision_service.dart';
import '../detalle_producto_screen.dart';
import '../../theme/fincas_tokens.dart';
import '../../widgets/fincas_widgets.dart';
import 'productos/widgets/nuevo_producto_sheet.dart';
import 'productos/widgets/producto_list_card.dart';

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
    final pendingCount = _productos.where((p) => p['pendingTueste'] == true).length;
    return Scaffold(
      backgroundColor: FincasColors.background,
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        behavior: HitTestBehavior.translucent,
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(FincasSpacing.l, FincasSpacing.s, FincasSpacing.l, FincasSpacing.m),
              decoration: const BoxDecoration(
                color: FincasColors.surface,
                border: Border(bottom: BorderSide(color: FincasColors.divider)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    focusNode: _searchFocusNode,
                    textInputAction: TextInputAction.search,
                    onChanged: (value) {
                      Future.delayed(const Duration(milliseconds: 500), () {
                        if (value == _busqueda || (value.isEmpty && _busqueda.isEmpty)) return;
                        _buscar(value);
                      });
                    },
                    decoration: InputDecoration(
                      hintText: 'Buscar producto por nombre...',
                      prefixIcon: const Icon(Icons.search, color: FincasColors.textSecondary),
                      fillColor: FincasColors.background,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(FincasRadii.medium), borderSide: BorderSide.none),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(FincasRadii.medium), borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(horizontal: FincasSpacing.l, vertical: FincasSpacing.m),
                    ),
                  ),
                  // Conteo y aviso en una sola línea: el aviso solo aparece si hay algo pendiente.
                  if ((_total > 0 && !_isLoading) || pendingCount > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: FincasSpacing.s),
                      child: Wrap(
                        spacing: FincasSpacing.s,
                        runSpacing: FincasSpacing.xs,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          if (_total > 0 && !_isLoading)
                            Text('$_total producto${_total != 1 ? 's' : ''}', style: FincasText.metadata),
                          if (pendingCount > 0)
                            FincasStatusBadge('$pendingCount con tueste pendiente', tone: FincasTone.warning),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
      // Una sola acción principal.
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _crearProductoManual,
        shape: const StadiumBorder(),
        label: const Text('Nuevo producto'),
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
    // El selector tarda en abrir la cámara: el indicador queda debajo y se cierra al volver con la foto.
    final image = await runWithFincasLoader(context, 'Abriendo cámara...', () => picker.pickImage(source: ImageSource.camera, maxWidth: 800));

    if (image == null || !mounted) return;
    
    _crearProductoManual(imagenPath: image.path);
  }

  /// Abre la hoja de nuevo producto (entrada manual). Si se crea, abre su edición.
  void _crearProductoManual({String? imagenPath}) {
    _modalAbierto = true;
    Map<String, dynamic>? nuevoProducto;
    showNuevoProductoSheet(
      context,
      onCrear: (nombre) async {
        final result = await ApiService.crearProducto(nombre: nombre);
        if (result.isSuccess) {
          HapticFeedback.heavyImpact();
          nuevoProducto = result.data;
          return null;
        }
        return result.error ?? 'Error al guardar';
      },
      onEscanear: _abrirEscanerCamara,
      onFoto: _tomarFotoYCrearProducto,
    ).then((creado) {
      _modalAbierto = false;
      if (creado == true && nuevoProducto != null && mounted) {
        _cargarProductos(refresh: true);
        _irAEditarProducto(nuevoProducto!);
      }
    });
  }

  Widget _buildSkeletonProducto(double opacity) {
    final c = FincasColors.sand.withValues(alpha: 0.5 + opacity);
    final cl = FincasColors.sand.withValues(alpha: 0.3 + opacity);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: FincasSpacing.l, vertical: FincasSpacing.xs + 1),
      padding: const EdgeInsets.all(FincasSpacing.l),
      decoration: BoxDecoration(
        color: FincasColors.surface,
        borderRadius: BorderRadius.circular(FincasRadii.large),
        border: Border.all(color: FincasColors.border),
      ),
      child: Row(children: [
        Container(width: 48, height: 48, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(FincasRadii.medium - 2))),
        const SizedBox(width: FincasSpacing.m),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(height: 14, width: 140, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(4))),
            const SizedBox(height: 8),
            Container(height: 11, width: 90, decoration: BoxDecoration(color: cl, borderRadius: BorderRadius.circular(4))),
          ]),
        ),
        Container(height: 16, width: 56, decoration: BoxDecoration(color: cl, borderRadius: BorderRadius.circular(4))),
      ]),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return AnimatedBuilder(
        animation: _shimmerCtrl,
        builder: (_, __) {
          final opacity = _shimmerCtrl.value * 0.3;
          return ListView.builder(
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.only(top: FincasSpacing.s, bottom: 100),
            itemCount: 8,
            itemBuilder: (_, __) => _buildSkeletonProducto(opacity),
          );
        },
      );
    }

    if (_error != null) {
      return ListView(
        padding: const EdgeInsets.symmetric(horizontal: FincasSpacing.xl, vertical: FincasSpacing.xxxl),
        children: [
          const FincasMessageState(
            title: 'No se pudieron cargar los productos',
            message: 'Revisa tu conexión e intenta de nuevo.',
            tone: FincasTone.error,
          ),
          const SizedBox(height: FincasSpacing.xl),
          Center(
            child: SizedBox(
              width: 220,
              child: FincasSecondaryButton(label: 'Reintentar', onPressed: () => _cargarProductos(refresh: true)),
            ),
          ),
        ],
      );
    }

    if (_productos.isEmpty) {
      final sinBusqueda = _busqueda.isEmpty;
      return ListView(
        padding: const EdgeInsets.symmetric(horizontal: FincasSpacing.xl, vertical: FincasSpacing.xxxl),
        children: [
          FincasMessageState(
            title: sinBusqueda ? 'Aún no hay productos' : 'Sin resultados',
            message: sinBusqueda ? 'Agrega el primero para empezar a vender.' : 'No se encontraron productos con "$_busqueda".',
          ),
          if (sinBusqueda) ...[
            const SizedBox(height: FincasSpacing.xl),
            Center(
              child: SizedBox(
                width: 260,
                child: FincasPrimaryButton(label: 'Agregar producto', onPressed: _crearProductoManual),
              ),
            ),
          ],
        ],
      );
    }

    return RefreshIndicator(
      color: FincasColors.ink,
      onRefresh: () => _cargarProductos(refresh: true),
      child: ListView.builder(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(top: FincasSpacing.s, bottom: 100), // espacio para el botón flotante
        itemCount: _productos.length + (_hayMas ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == _productos.length) return _buildLoadingMore();
          final producto = _productos[index];
          return ProductoListCard(producto: producto, onTap: () => _irAEditarProducto(producto));
        },
      ),
    );
  }

  Widget _buildLoadingMore() {
    return Padding(
      padding: const EdgeInsets.all(FincasSpacing.l),
      child: Center(
        child: _isLoadingMore
            ? const FincasLoader(message: 'Cargando más...')
            : FincasTextButton(label: 'Cargar más', onPressed: _cargarMasProductos),
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
          // La cámara tarda en arrancar: indicador hasta que esté lista (fondo negro, texto claro).
          ValueListenableBuilder<MobileScannerState>(
            valueListenable: _controller,
            builder: (context, state, _) => state.isInitialized
                ? const SizedBox.shrink()
                : Container(
                    color: Colors.black,
                    alignment: Alignment.center,
                    child: const Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(width: 32, height: 32, child: CircularProgressIndicator(strokeWidth: 3, color: Colors.white)),
                        SizedBox(height: 16),
                        Text('Abriendo cámara...', style: TextStyle(color: Colors.white, fontSize: 15)),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
