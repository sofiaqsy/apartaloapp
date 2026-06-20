import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:path_provider/path_provider.dart';
import '../services/api_service.dart';
import '../services/vision_service.dart';

class EscanearProductoScreen extends StatefulWidget {
  const EscanearProductoScreen({super.key});

  @override
  State<EscanearProductoScreen> createState() => _EscanearProductoScreenState();
}

class _EscanearProductoScreenState extends State<EscanearProductoScreen> {
  // Estados de pantalla
  int _currentStep = 0; // 0=Scanner, 1=Editar/Crear
  
  // Datos del producto
  String? _codigoBarras;
  Map<String, dynamic>? _productoExistente;
  ProductoDetectado? _productoDetectado;
  final List<File> _fotos = [];
  String? _imagenUrlExistente; // URL de imagen ya guardada en Drive
  
  // Controladores
  final _nombreController = TextEditingController();
  final _precioController = TextEditingController();
  final _stockController = TextEditingController(text: '0');

  // Estados
  bool _isLoading = false;
  bool _scannerActivo = true;
  bool _buscandoProducto = false;
  bool _tomandoFoto = false;
  bool _esNuevoProducto = true;
  
  Uint8List? _ultimoFrame;
  
  final ImagePicker _picker = ImagePicker();
  MobileScannerController? _scannerController;

  @override
  void initState() {
    super.initState();
    _scannerController = MobileScannerController(
      detectionSpeed: DetectionSpeed.normal,
      facing: CameraFacing.back,
      returnImage: true,
    );
  }

  void _onDetect(BarcodeCapture capture) async {
    if (Platform.isAndroid && capture.image != null) {
      _ultimoFrame = capture.image;
    }

    if (!_scannerActivo || _buscandoProducto || _tomandoFoto) return;

    final barcode = capture.barcodes.firstOrNull;
    if (barcode?.rawValue != null) {
      final codigo = barcode!.rawValue!;
      
      setState(() {
        _scannerActivo = false;
        _buscandoProducto = true;
        _codigoBarras = codigo;
      });

      await _buscarProducto(codigo);
    }
  }

  Future<void> _buscarProducto(String codigo) async {
    _mostrarDialogoBuscando(codigo);

    final resultLocal = await ApiService.getProductos(buscar: codigo);
    
    Map<String, dynamic>? productoLocal;
    if (resultLocal.isSuccess && resultLocal.data != null && resultLocal.data!.productos.isNotEmpty) {
      final found = resultLocal.data!.productos.firstWhere(
        (p) => p['codigo'] == codigo,
        orElse: () => <String, dynamic>{},
      );
      if (found.isNotEmpty) productoLocal = found;
    }

    if (mounted) Navigator.pop(context);

    if (productoLocal != null) {
      final producto = productoLocal;
      setState(() {
        _productoExistente = producto;
        _esNuevoProducto = false;
        _nombreController.text = producto['nombre'] ?? '';
        _precioController.text = (producto['precio'] ?? 0).toString();
        _stockController.text = (producto['stock'] ?? 0).toString();
        _imagenUrlExistente = producto['imagenUrl'];
        _buscandoProducto = false;
      });
      _mostrarProductoExistente(producto);
    } else {
      setState(() => _esNuevoProducto = true);
      await _buscarEnAPIsExternas(codigo);
    }
  }

  Future<void> _buscarEnAPIsExternas(String codigo) async {
    _mostrarDialogoBuscando(codigo, mensaje: 'Buscando información...');

    final resultado = await VisionService.buscarPorCodigoBarras(codigo);
    
    if (mounted) Navigator.pop(context);
    setState(() => _buscandoProducto = false);

    if (resultado != null) {
      setState(() {
        _productoDetectado = resultado;
        if (resultado.nombreCompleto.isNotEmpty) {
          _nombreController.text = resultado.nombreCompleto;
        }
        _imagenUrlExistente = resultado.imagenUrl;
      });
      _mostrarProductoNuevoEncontrado(resultado);
    } else {
      _mostrarProductoNoEncontrado(codigo);
    }
  }

  void _mostrarDialogoBuscando(String codigo, {String? mensaje}) {
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
            Text(mensaje ?? '🔍 Buscando en inventario...', style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text(codigo, style: TextStyle(color: Colors.grey.shade600, fontFamily: 'monospace')),
          ],
        ),
      ),
    );
  }

  void _mostrarProductoExistente(Map<String, dynamic> producto) {
    final nombre = producto['nombre'] ?? 'Sin nombre';
    final precio = producto['precio'] ?? 0;
    final stock = producto['stock'] ?? 0;
    final imagenUrl = producto['imagenUrl'];

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64, height: 64,
              decoration: BoxDecoration(color: Colors.blue.shade50, shape: BoxShape.circle),
              child: Icon(Icons.inventory_2, color: Colors.blue.shade600, size: 32),
            ),
            const SizedBox(height: 16),
            const Text('Producto en inventario', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),

            // Imagen existente
            if (imagenUrl != null && imagenUrl.toString().isNotEmpty) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(
                  imagenUrl,
                  width: 100, height: 100, fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    width: 100, height: 100,
                    color: Colors.grey.shade200,
                    child: Icon(Icons.image_not_supported, color: Colors.grey.shade400),
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(12)),
              child: Column(
                children: [
                  _buildInfoRow('📦 Nombre', nombre.toString()),
                  const SizedBox(height: 8),
                  _buildInfoRow('💰 Precio', 'S/ ${(precio as num).toStringAsFixed(2)}'),
                  const SizedBox(height: 8),
                  _buildInfoRow('📊 Stock', '$stock unidades'),
                ],
              ),
            ),

            const SizedBox(height: 20),
            const Text('¿Qué deseas hacer?', style: TextStyle(fontWeight: FontWeight.w500)),
            const SizedBox(height: 16),

            Row(
              children: [
                Expanded(
                  child: _buildAccionRapida(
                    icon: Icons.remove_circle_outline,
                    label: 'Vender (-1)',
                    color: Colors.orange,
                    onTap: () async {
                      Navigator.pop(context);
                      await _actualizarStockRapido(producto['codigo'], -1);
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildAccionRapida(
                    icon: Icons.add_circle_outline,
                    label: 'Agregar (+1)',
                    color: Colors.green,
                    onTap: () async {
                      Navigator.pop(context);
                      await _actualizarStockRapido(producto['codigo'], 1);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      setState(() => _currentStep = 1);
                    },
                    icon: const Icon(Icons.edit),
                    label: const Text('Editar'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      _resetearYEscanearOtro();
                    },
                    icon: const Icon(Icons.qr_code_scanner),
                    label: const Text('Otro'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAccionRapida({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: color.withOpacity(0.1),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            children: [
              Icon(icon, color: color, size: 28),
              const SizedBox(height: 4),
              Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _actualizarStockRapido(String codigo, int cantidad) async {
    setState(() => _isLoading = true);

    final result = await ApiService.actualizarStock(
      codigo: codigo,
      cantidad: cantidad.abs(),
      operacion: cantidad > 0 ? 'agregar' : 'restar',
    );

    setState(() => _isLoading = false);

    if (result.isSuccess) {
      final nuevoStock = result.data?['stockNuevo'] ?? 0;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(cantidad > 0 
            ? '✅ Stock: $nuevoStock unidades' 
            : '✅ Venta registrada: $nuevoStock restantes'),
          backgroundColor: Colors.green,
        ),
      );
      _resetearYEscanearOtro();
    } else {
      _mostrarError(result.error ?? 'Error');
    }
  }

  void _resetearYEscanearOtro() {
    setState(() {
      _codigoBarras = null;
      _productoExistente = null;
      _productoDetectado = null;
      _fotos.clear();
      _imagenUrlExistente = null;
      _nombreController.clear();
      _precioController.clear();
      _stockController.text = '0';
      _esNuevoProducto = true;
      _currentStep = 0;
      _scannerActivo = true;
    });
    _scannerController?.start();
  }

  void _mostrarProductoNuevoEncontrado(ProductoDetectado producto) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64, height: 64,
              decoration: BoxDecoration(color: Colors.green.shade50, shape: BoxShape.circle),
              child: Icon(Icons.new_releases, color: Colors.green.shade600, size: 32),
            ),
            const SizedBox(height: 16),
            const Text('Producto nuevo', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('No está en tu inventario', style: TextStyle(color: Colors.grey.shade600)),
            const SizedBox(height: 16),

            if (producto.imagenUrl != null) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(
                  producto.imagenUrl!,
                  width: 100, height: 100, fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox(),
                ),
              ),
              const SizedBox(height: 16),
            ],

            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(12)),
              child: Column(
                children: [
                  if (producto.nombre != null) _buildInfoRow('📦', producto.nombre!),
                  if (producto.marca != null) ...[const SizedBox(height: 8), _buildInfoRow('🏷️', producto.marca!)],
                  if (producto.peso != null) ...[const SizedBox(height: 8), _buildInfoRow('⚖️', producto.peso!)],
                ],
              ),
            ),

            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      _resetearYEscanearOtro();
                    },
                    child: const Text('Cancelar'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      setState(() => _currentStep = 1);
                    },
                    icon: const Icon(Icons.add),
                    label: const Text('Registrar'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green.shade600,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _mostrarProductoNoEncontrado(String codigo) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64, height: 64,
              decoration: BoxDecoration(color: Colors.orange.shade50, shape: BoxShape.circle),
              child: Icon(Icons.help_outline, color: Colors.orange.shade600, size: 32),
            ),
            const SizedBox(height: 16),
            const Text('Producto desconocido', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(8)),
              child: Text(codigo, style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w600)),
            ),
            const SizedBox(height: 12),
            Text('Ingresa los datos manualmente', style: TextStyle(color: Colors.grey.shade600)),
            const SizedBox(height: 20),

            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () { Navigator.pop(context); _resetearYEscanearOtro(); },
                    child: const Text('Cancelar'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () { Navigator.pop(context); setState(() => _currentStep = 1); },
                    icon: const Icon(Icons.add),
                    label: const Text('Registrar'),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.blue.shade600, foregroundColor: Colors.white),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 80, child: Text(label, style: TextStyle(color: Colors.grey.shade600, fontSize: 13))),
        Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14))),
      ],
    );
  }

  // ============ TOMAR FOTOS ============

  Future<void> _tomarFoto() async {
    if (_tomandoFoto) return;
    if (Platform.isAndroid) {
      await _capturarFotoAndroid();
    } else {
      await _tomarFotoConPicker();
    }
  }

  Future<void> _capturarFotoAndroid() async {
    setState(() => _tomandoFoto = true);
    try {
      await Future.delayed(const Duration(milliseconds: 300));
      if (_ultimoFrame != null) {
        final tempDir = await getTemporaryDirectory();
        final file = File('${tempDir.path}/producto_${DateTime.now().millisecondsSinceEpoch}.jpg');
        await file.writeAsBytes(_ultimoFrame!);
        setState(() { _fotos.add(file); _tomandoFoto = false; });
        _mostrarSnackBar('📸 ¡Foto capturada!', Colors.green);
      } else {
        setState(() => _tomandoFoto = false);
        await _tomarFotoConPicker();
      }
    } catch (e) {
      setState(() => _tomandoFoto = false);
      await _tomarFotoConPicker();
    }
  }

  Future<void> _tomarFotoConPicker() async {
    try {
      _scannerController?.stop();
      setState(() => _tomandoFoto = true);
      
      final XFile? foto = await _picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1024, maxHeight: 1024, imageQuality: 85,
      );

      setState(() => _tomandoFoto = false);

      if (foto != null) {
        setState(() => _fotos.add(File(foto.path)));
      }
      _scannerController?.start();
    } catch (e) {
      setState(() => _tomandoFoto = false);
      _mostrarError('No se pudo acceder a la cámara');
    }
  }

  void _eliminarFoto(int index) => setState(() => _fotos.removeAt(index));

  // ============ GUARDAR ============

  Future<void> _guardarProducto() async {
    final nombre = _nombreController.text.trim();
    final precioText = _precioController.text.trim();

    if (nombre.isEmpty) return _mostrarError('Ingresa el nombre');
    if (precioText.isEmpty) return _mostrarError('Ingresa el precio');

    final precio = double.tryParse(precioText);
    if (precio == null || precio <= 0) return _mostrarError('Precio inválido');

    setState(() => _isLoading = true);

    // Subir fotos nuevas a Google Drive si hay
    String? imagenUrl = _imagenUrlExistente;
    if (_fotos.isNotEmpty) {
      _mostrarSnackBar('📤 Subiendo foto...', Colors.blue);
      
      final uploadResult = await ApiService.uploadImage(_fotos.first);
      if (uploadResult.isSuccess) {
        imagenUrl = uploadResult.data;
        debugPrint('✅ Foto subida: $imagenUrl');
      } else {
        debugPrint('⚠️ Error subiendo foto: ${uploadResult.error}');
      }
    }

    final codigo = _codigoBarras ?? 'P${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}';
    final stock = int.tryParse(_stockController.text.trim()) ?? 0;

    ApiResponse result;
    
    if (_esNuevoProducto) {
      // CREAR nuevo producto
      result = await ApiService.crearProducto(nombre: nombre);
    } else {
      // ACTUALIZAR producto existente
      result = await ApiService.actualizarProducto(
        codigo: codigo,
        nombre: nombre,
        precio: precio,
        stock: stock,
        imagenUrl: imagenUrl,
      );
    }

    setState(() => _isLoading = false);

    if (result.isSuccess && mounted) {
      _mostrarSnackBar(
        _esNuevoProducto ? '✅ $nombre registrado' : '✅ $nombre actualizado',
        Colors.green,
      );
      Navigator.pop(context, true);
    } else {
      _mostrarError(result.error ?? 'Error');
    }
  }

  void _mostrarError(String msg) => _mostrarSnackBar(msg, Colors.red);
  
  void _mostrarSnackBar(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: color),
    );
  }

  // ============ BUILD ============

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _currentStep == 0 ? Colors.black : Colors.grey.shade100,
      appBar: AppBar(
        title: Text(_currentStep == 0 
            ? 'Escanear Producto' 
            : (_esNuevoProducto ? 'Nuevo Producto' : 'Editar Producto')),
        backgroundColor: _currentStep == 0 ? Colors.black : Colors.blue.shade600,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
        actions: _currentStep == 0 ? [
          TextButton(
            onPressed: () => setState(() { _currentStep = 1; _esNuevoProducto = true; }),
            child: const Text('Manual', style: TextStyle(color: Colors.white70)),
          ),
        ] : null,
      ),
      body: _currentStep == 0 ? _buildScannerStep() : _buildFormStep(),
    );
  }

  Widget _buildScannerStep() {
    return Stack(
      children: [
        MobileScanner(controller: _scannerController, onDetect: _onDetect),
        
        Center(
          child: Container(
            width: 280, height: 180,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white54, width: 3),
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),

        Positioned(
          top: 20, left: 20, right: 20,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(12)),
            child: const Text(
              '📦 Escanea el código de barras',
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
          ),
        ),

        if (_isLoading)
          Container(
            color: Colors.black54,
            child: const Center(child: CircularProgressIndicator(color: Colors.white)),
          ),
      ],
    );
  }

  Widget _buildFormStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Indicador nuevo/existente
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _esNuevoProducto ? Colors.green.shade50 : Colors.blue.shade50,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(
                  _esNuevoProducto ? Icons.new_releases : Icons.edit,
                  color: _esNuevoProducto ? Colors.green.shade600 : Colors.blue.shade600,
                ),
                const SizedBox(width: 12),
                Text(
                  _esNuevoProducto ? 'Registrar nuevo producto' : 'Editando producto existente',
                  style: TextStyle(
                    color: _esNuevoProducto ? Colors.green.shade700 : Colors.blue.shade700,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),

          if (_codigoBarras != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(12)),
              child: Row(
                children: [
                  const Icon(Icons.qr_code),
                  const SizedBox(width: 12),
                  Text(_codigoBarras!, style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ],

          // Imagen existente o nuevas fotos
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Fotos', style: TextStyle(fontWeight: FontWeight.w600)),
              TextButton.icon(
                onPressed: _tomarFoto,
                icon: const Icon(Icons.add_a_photo, size: 18),
                label: const Text('Agregar'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          
          // Mostrar imagen existente + fotos nuevas
          SizedBox(
            height: 100,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                // Imagen existente de Drive
                if (_imagenUrlExistente != null && _imagenUrlExistente!.isNotEmpty && _fotos.isEmpty)
                  Container(
                    width: 100, height: 100,
                    margin: const EdgeInsets.only(right: 8),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.green.shade300, width: 2),
                    ),
                    child: Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.network(
                            _imagenUrlExistente!,
                            width: 100, height: 100, fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              color: Colors.grey.shade200,
                              child: Icon(Icons.image_not_supported, color: Colors.grey.shade400),
                            ),
                          ),
                        ),
                        Positioned(
                          bottom: 4, right: 4,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.green,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text('✓', style: TextStyle(color: Colors.white, fontSize: 10)),
                          ),
                        ),
                      ],
                    ),
                  ),

                // Fotos nuevas tomadas
                ..._fotos.asMap().entries.map((entry) {
                  final i = entry.key;
                  final foto = entry.value;
                  return Stack(
                    children: [
                      Container(
                        width: 100, height: 100,
                        margin: const EdgeInsets.only(right: 8),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.blue.shade300, width: 2),
                          image: DecorationImage(image: FileImage(foto), fit: BoxFit.cover),
                        ),
                      ),
                      Positioned(
                        top: 4, right: 12,
                        child: GestureDetector(
                          onTap: () => _eliminarFoto(i),
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                            child: const Icon(Icons.close, color: Colors.white, size: 14),
                          ),
                        ),
                      ),
                      Positioned(
                        bottom: 4, right: 12,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.blue,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text('Nueva', style: TextStyle(color: Colors.white, fontSize: 10)),
                        ),
                      ),
                    ],
                  );
                }),

                // Botón agregar
                if (_fotos.isEmpty && (_imagenUrlExistente == null || _imagenUrlExistente!.isEmpty))
                  GestureDetector(
                    onTap: _tomarFoto,
                    child: Container(
                      width: 100, height: 100,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade300, style: BorderStyle.solid),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add_a_photo, color: Colors.grey.shade400, size: 32),
                          const SizedBox(height: 4),
                          Text('Foto', style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // Campos
          const SizedBox(height: 24),
          const Text('Nombre *', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          TextField(
            controller: _nombreController,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              hintText: 'Ej: Café Premium 250g',
              filled: true, fillColor: Colors.white,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade300)),
            ),
          ),

          const SizedBox(height: 16),
          const Text('Precio *', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          TextField(
            controller: _precioController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              hintText: '0.00', prefixText: 'S/ ',
              filled: true, fillColor: Colors.white,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade300)),
            ),
          ),

          const SizedBox(height: 16),
          const Text('Stock', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          TextField(
            controller: _stockController,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              hintText: '0', suffixText: 'unidades',
              filled: true, fillColor: Colors.white,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade300)),
            ),
          ),

          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity, height: 54,
            child: ElevatedButton.icon(
              onPressed: _isLoading ? null : _guardarProducto,
              icon: _isLoading 
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) 
                  : Icon(_esNuevoProducto ? Icons.add : Icons.save),
              label: Text(
                _isLoading ? 'Guardando...' : (_esNuevoProducto ? 'Registrar Producto' : 'Guardar Cambios'),
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: _esNuevoProducto ? Colors.green.shade600 : Colors.blue.shade600,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Center(child: TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar'))),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _scannerController?.dispose();
    _nombreController.dispose();
    _precioController.dispose();
    _stockController.dispose();
    super.dispose();
  }
}
