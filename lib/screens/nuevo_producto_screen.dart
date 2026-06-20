import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:path_provider/path_provider.dart';
import '../services/api_service.dart';
import '../services/vision_service.dart';
import '../services/sunmi_scanner_service.dart';

class NuevoProductoScreen extends StatefulWidget {
  const NuevoProductoScreen({super.key});

  @override
  State<NuevoProductoScreen> createState() => _NuevoProductoScreenState();
}

class _NuevoProductoScreenState extends State<NuevoProductoScreen> {
  int _currentStep = 0;
  String? _codigoBarras;
  final List<File> _fotos = [];
  ProductoDetectado? _productoDetectado;
  
  final _nombreController = TextEditingController();
  final _precioController = TextEditingController();
  final _stockController = TextEditingController(text: '0');
  
  // Para entrada manual de código
  final _codigoManualController = TextEditingController();
  final _codigoFocusNode = FocusNode();

  bool _isLoading = false;
  bool _scannerActivo = true;
  bool _buscandoProducto = false;
  bool _tomandoFoto = false;
  bool _usarEscanerHardware = true; // Por defecto true, se cambia si no es Sunmi
  bool _dispositivoDetectado = false;
  
  // Para captura en Android
  Uint8List? _ultimoFrame;
  
  final ImagePicker _picker = ImagePicker();
  MobileScannerController? _scannerController;
  
  // Sunmi scanner
  final SunmiScannerService _sunmiScanner = SunmiScannerService();
  StreamSubscription<String>? _scanSubscription;

  @override
  void initState() {
    super.initState();
    _detectarTipoDispositivo();
    _initSunmiScanner();
  }

  Future<void> _detectarTipoDispositivo() async {
    // Detectar tamaño de pantalla
    final size = WidgetsBinding.instance.platformDispatcher.views.first.physicalSize;
    final ratio = WidgetsBinding.instance.platformDispatcher.views.first.devicePixelRatio;
    final width = size.width / ratio;
    final height = size.height / ratio;
    
    // Es tablet si el ancho es mayor a 600dp
    final esTablet = width > 600 || height > 600;
    
    debugPrint('🔍 Dispositivo detectado:');
    debugPrint('   - Ancho: $width, Alto: $height');
    debugPrint('   - Es tablet: $esTablet');
    debugPrint('   - Usar escáner pistola: $esTablet');
    
    if (mounted) {
      setState(() {
        // En tablets SIEMPRE usar modo escáner de hardware (pistola)
        _usarEscanerHardware = esTablet;
        _dispositivoDetectado = true;
      });
      
      // Solo inicializar cámara si es celular (NO tablet)
      if (!esTablet) {
        _initScannerController();
      }
    }
  }

  void _initScannerController() {
    _scannerController = MobileScannerController(
      detectionSpeed: DetectionSpeed.normal,
      facing: CameraFacing.back,
      returnImage: true,
    );
  }

  void _initSunmiScanner() {
    _sunmiScanner.initialize();
    _scanSubscription = _sunmiScanner.onScan.listen(_onHardwareScan);
  }

  /// Cuando el escáner de hardware (Sunmi) detecta un código
  void _onHardwareScan(String codigo) {
    if (_buscandoProducto) return;
    
    debugPrint('📦 Código escaneado por hardware: $codigo');
    
    // Vibración de feedback
    HapticFeedback.heavyImpact();
    
    setState(() {
      _codigoBarras = codigo;
      _codigoManualController.text = codigo;
    });
    
    _buscarProductoPorCodigo(codigo);
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

      await _buscarProductoPorCodigo(codigo);
    }
  }

  /// Buscar código manualmente ingresado
  void _buscarCodigoManual() {
    final codigo = _codigoManualController.text.trim();
    if (codigo.isEmpty) {
      _mostrarError('Ingresa un código');
      return;
    }
    
    if (codigo.length < 4) {
      _mostrarError('Código muy corto');
      return;
    }
    
    setState(() {
      _codigoBarras = codigo;
    });
    
    _buscarProductoPorCodigo(codigo);
  }

  Future<void> _tomarFoto() async {
    if (_tomandoFoto) return;
    await _tomarFotoConPicker();
  }

  Future<void> _tomarFotoConPicker() async {
    try {
      _scannerController?.stop();
      setState(() => _tomandoFoto = true);
      
      final XFile? foto = await _picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );

      setState(() => _tomandoFoto = false);

      if (foto != null) {
        final file = File(foto.path);
        setState(() => _fotos.add(file));
        
        if (_fotos.length == 1 && _productoDetectado == null) {
          await _analizarFotoConIA(file);
        } else {
          _preguntarOtraFoto();
        }
      }
    } catch (e) {
      setState(() => _tomandoFoto = false);
      _mostrarError('No se pudo acceder a la cámara');
    }
  }

  Future<void> _analizarFotoConIA(File foto) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.file(foto, width: 100, height: 100, fit: BoxFit.cover),
            ),
            const SizedBox(height: 16),
            const CircularProgressIndicator(),
            const SizedBox(height: 12),
            const Text('🔍 Analizando con IA...'),
          ],
        ),
      ),
    );

    final resultado = await VisionService.analizarImagenProducto(foto);
    if (mounted) Navigator.pop(context);

    if (resultado != null) {
      setState(() {
        _productoDetectado = resultado;
        if (resultado.nombreCompleto.isNotEmpty) {
          _nombreController.text = resultado.nombreCompleto;
        }
        if (resultado.codigoBarras != null && _codigoBarras == null) {
          _codigoBarras = resultado.codigoBarras;
        }
      });
      _mostrarResultadoIA(resultado);
    } else {
      _preguntarOtraFoto();
    }
  }

  Future<void> _buscarProductoPorCodigo(String codigo) async {
    setState(() => _buscandoProducto = true);
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 60,
              height: 60,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
            const SizedBox(height: 24),
            const Text('🔍 Buscando producto...', 
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 18)),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(codigo, 
                style: const TextStyle(
                  fontFamily: 'monospace', 
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2,
                )),
            ),
          ],
        ),
      ),
    );

    final resultado = await VisionService.buscarPorCodigoBarras(codigo);
    if (mounted) Navigator.pop(context);

    setState(() => _buscandoProducto = false);

    if (resultado != null) {
      setState(() {
        _productoDetectado = resultado;
        if (resultado.nombreCompleto.isNotEmpty) {
          _nombreController.text = resultado.nombreCompleto;
        }
      });
      _mostrarProductoEncontrado(resultado);
    } else {
      _mostrarProductoNoEncontrado(codigo);
    }
  }

  void _mostrarProductoEncontrado(ProductoDetectado producto) {
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
              width: 80, height: 80,
              decoration: BoxDecoration(color: Colors.green.shade50, shape: BoxShape.circle),
              child: Icon(Icons.check_circle, color: Colors.green.shade600, size: 50),
            ),
            const SizedBox(height: 20),
            const Text('¡Producto encontrado!', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),

            if (producto.imagenUrl != null) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(
                  producto.imagenUrl!,
                  width: 150, height: 150,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    width: 150, height: 150,
                    color: Colors.grey.shade200,
                    child: Icon(Icons.image_not_supported, color: Colors.grey.shade400, size: 50),
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ],

            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(16)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (producto.nombre != null) _buildInfoRow('📦 Producto', producto.nombre!),
                  if (producto.marca != null) ...[const SizedBox(height: 12), _buildInfoRow('🏷️ Marca', producto.marca!)],
                  if (producto.peso != null) ...[const SizedBox(height: 12), _buildInfoRow('⚖️ Cantidad', producto.peso!)],
                  if (producto.categoria != null) ...[const SizedBox(height: 12), _buildInfoRow('📂 Categoría', producto.categoria!)],
                ],
              ),
            ),

            const SizedBox(height: 24),

            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton.icon(
                onPressed: () { Navigator.pop(context); setState(() => _currentStep = 1); },
                icon: const Icon(Icons.arrow_forward, size: 24),
                label: const Text('Continuar', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green.shade600,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
              ),
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
              width: 80, height: 80,
              decoration: BoxDecoration(color: Colors.orange.shade50, shape: BoxShape.circle),
              child: Icon(Icons.search_off, color: Colors.orange.shade600, size: 40),
            ),
            const SizedBox(height: 20),
            const Text('Producto no encontrado', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(12)),
              child: Text(codigo, style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.bold, fontSize: 20, letterSpacing: 2)),
            ),
            const SizedBox(height: 16),
            Text('Ingresa los datos manualmente', style: TextStyle(color: Colors.grey.shade600, fontSize: 16), textAlign: TextAlign.center),
            const SizedBox(height: 24),

            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton.icon(
                onPressed: () { Navigator.pop(context); setState(() => _currentStep = 1); },
                icon: const Icon(Icons.edit, size: 24),
                label: const Text('Ingresar datos', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue.shade600,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _mostrarResultadoIA(ProductoDetectado producto) {
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
            Icon(Icons.auto_awesome, color: Colors.purple.shade400, size: 56),
            const SizedBox(height: 16),
            const Text('✨ IA identificó el producto', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(16)),
              child: Column(
                children: [
                  if (producto.nombre != null) _buildInfoRow('📦', producto.nombre!),
                  if (producto.marca != null) ...[const SizedBox(height: 12), _buildInfoRow('🏷️', producto.marca!)],
                  if (producto.peso != null) ...[const SizedBox(height: 12), _buildInfoRow('⚖️', producto.peso!)],
                ],
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: () { Navigator.pop(context); setState(() => _currentStep = 1); },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.purple.shade600,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: const Text('Continuar', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
              ),
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
        SizedBox(width: 110, child: Text(label, style: TextStyle(color: Colors.grey.shade600, fontSize: 16))),
        Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 17))),
      ],
    );
  }

  void _preguntarOtraFoto() {
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
            SizedBox(
              height: 100,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: _fotos.length,
                itemBuilder: (_, i) => Container(
                  width: 100, height: 100,
                  margin: const EdgeInsets.only(right: 12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    image: DecorationImage(image: FileImage(_fotos[i]), fit: BoxFit.cover),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text('${_fotos.length} foto${_fotos.length > 1 ? 's' : ''} capturada${_fotos.length > 1 ? 's' : ''}', 
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 18)),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 56,
                    child: OutlinedButton.icon(
                      onPressed: () { Navigator.pop(context); setState(() => _currentStep = 1); },
                      icon: const Icon(Icons.check),
                      label: const Text('Listo', style: TextStyle(fontSize: 16)),
                      style: OutlinedButton.styleFrom(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: SizedBox(
                    height: 56,
                    child: ElevatedButton.icon(
                      onPressed: () { Navigator.pop(context); _tomarFoto(); },
                      icon: const Icon(Icons.add_a_photo),
                      label: const Text('Otra', style: TextStyle(fontSize: 16)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue.shade600,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
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

  void _eliminarFoto(int index) => setState(() => _fotos.removeAt(index));

  Future<void> _guardarProducto() async {
    final nombre = _nombreController.text.trim();
    if (nombre.isEmpty) return _mostrarError('Ingresa el nombre');

    setState(() => _isLoading = true);

    final result = await ApiService.crearProducto(nombre: nombre);

    setState(() => _isLoading = false);

    if (result.isSuccess && mounted) {
      HapticFeedback.heavyImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ $nombre registrado correctamente', style: const TextStyle(fontSize: 16)),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
        ),
      );
      Navigator.pop(context, true);
    } else {
      _mostrarError(result.error ?? 'Error al guardar');
    }
  }

  /// Guardar y continuar escaneando (modo rápido para inventario)
  Future<void> _guardarYContinuar() async {
    final nombre = _nombreController.text.trim();

    if (nombre.isEmpty) return _mostrarError('Ingresa el nombre');

    setState(() => _isLoading = true);

    final result = await ApiService.crearProducto(nombre: nombre);

    setState(() => _isLoading = false);

    if (result.isSuccess && mounted) {
      HapticFeedback.heavyImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ $nombre registrado', style: const TextStyle(fontSize: 16)),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 1),
          behavior: SnackBarBehavior.floating,
        ),
      );
      
      // Limpiar y volver a escanear
      _limpiarFormulario();
    } else {
      _mostrarError(result.error ?? 'Error al guardar');
    }
  }

  void _limpiarFormulario() {
    setState(() {
      _codigoBarras = null;
      _fotos.clear();
      _productoDetectado = null;
      _nombreController.clear();
      _precioController.clear();
      _stockController.text = '0';
      _codigoManualController.clear();
      _currentStep = 0;
      _scannerActivo = true;
      _buscandoProducto = false;
    });
    
    _sunmiScanner.clearBuffer();
    
    // Enfocar el campo de código para recibir el siguiente escaneo
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) {
        _codigoFocusNode.requestFocus();
      }
    });
  }

  void _mostrarError(String msg) {
    HapticFeedback.vibrate();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(fontSize: 16)),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Mostrar loading mientras detecta el dispositivo
    if (!_dispositivoDetectado) {
      return Scaffold(
        backgroundColor: Colors.grey.shade900,
        body: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: Colors.white),
              SizedBox(height: 20),
              Text('Detectando dispositivo...', style: TextStyle(color: Colors.white70, fontSize: 16)),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: _currentStep == 0 ? Colors.grey.shade900 : Colors.grey.shade100,
      appBar: AppBar(
        title: Text(
          _currentStep == 0 ? 'Escanear Producto' : 'Datos del Producto',
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
        ),
        backgroundColor: _currentStep == 0 ? Colors.grey.shade900 : Colors.blue.shade600,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, size: 28), 
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (_currentStep == 0)
            TextButton(
              onPressed: () => setState(() => _currentStep = 1),
              child: const Text('Saltar', style: TextStyle(color: Colors.white70, fontSize: 16)),
            ),
        ],
      ),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        behavior: HitTestBehavior.translucent,
        child: _currentStep == 0
          ? _buildHardwareScannerStep()
          : _buildDataStep(),
      ),
    );
  }

  /// UI para escáner de hardware (Sunmi) - PANTALLA PRINCIPAL
  Widget _buildHardwareScannerStep() {
    return Container(
      color: Colors.grey.shade900,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            children: [
              const Spacer(),
              
              // Icono grande
              Container(
                width: 160,
                height: 160,
                decoration: BoxDecoration(
                  color: Colors.blue.shade600.withOpacity(0.15),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.blue.shade400.withOpacity(0.3), width: 3),
                ),
                child: Icon(
                  Icons.qr_code_scanner,
                  size: 80,
                  color: Colors.blue.shade400,
                ),
              ),
              
              const SizedBox(height: 40),
              
              // Título
              const Text(
                '📦 Escanea el producto',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              
              const SizedBox(height: 16),
              
              // Subtítulo
              Text(
                'Usa la pistola escáner o ingresa\nel código manualmente',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.6),
                  fontSize: 18,
                ),
                textAlign: TextAlign.center,
              ),
              
              const SizedBox(height: 48),
              
              // Campo para código (recibe input de la pistola)
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.blue.shade400.withOpacity(0.3),
                      blurRadius: 20,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: TextField(
                  controller: _codigoManualController,
                  focusNode: _codigoFocusNode,
                  style: const TextStyle(
                    fontSize: 24,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.bold,
                    letterSpacing: 3,
                  ),
                  textAlign: TextAlign.center,
                  decoration: InputDecoration(
                    hintText: 'Código de barras',
                    hintStyle: TextStyle(
                      color: Colors.grey.shade400,
                      fontSize: 20,
                      letterSpacing: 1,
                    ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
                    suffixIcon: IconButton(
                      onPressed: _codigoManualController.text.isNotEmpty ? _buscarCodigoManual : null,
                      icon: Icon(Icons.search, color: Colors.blue.shade600, size: 32),
                    ),
                  ),
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _buscarCodigoManual(),
                  autofocus: true,
                ),
              ),
              
              // Código detectado
              if (_codigoBarras != null) ...[
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                  decoration: BoxDecoration(
                    color: Colors.green,
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.check_circle, color: Colors.white, size: 24),
                      const SizedBox(width: 10),
                      Text(
                        _codigoBarras!,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 20,
                          fontFamily: 'monospace',
                          letterSpacing: 2,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              
              const Spacer(),
              
              // Botón continuar si hay código
              if (_codigoBarras != null) ...[
                SizedBox(
                  width: double.infinity,
                  height: 60,
                  child: ElevatedButton.icon(
                    onPressed: () => setState(() => _currentStep = 1),
                    icon: const Icon(Icons.arrow_forward, size: 24),
                    label: const Text('Continuar', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue.shade600,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              
              // Botón para usar cámara como alternativa
              TextButton.icon(
                onPressed: () {
                  setState(() => _usarEscanerHardware = false);
                  _initScannerController();
                },
                icon: Icon(Icons.camera_alt, color: Colors.white.withOpacity(0.5)),
                label: Text(
                  'Usar cámara como alternativa',
                  style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 14),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDataStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Info del producto detectado
          if (_productoDetectado != null)
            Container(
              margin: const EdgeInsets.only(bottom: 20),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.green.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.auto_awesome, color: Colors.green.shade600, size: 28),
                  const SizedBox(width: 12),
                  Expanded(child: Text('✓ Identificado automáticamente', 
                    style: TextStyle(color: Colors.green.shade700, fontWeight: FontWeight.w600, fontSize: 16))),
                ],
              ),
            ),

          // Código de barras
          if (_codigoBarras != null)
            Container(
              margin: const EdgeInsets.only(bottom: 20),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(16)),
              child: Row(
                children: [
                  Icon(Icons.qr_code, color: Colors.blue.shade600, size: 32),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Código de barras', style: TextStyle(fontSize: 14, color: Colors.blue.shade600)),
                        const SizedBox(height: 4),
                        Text(_codigoBarras!, style: TextStyle(
                          fontWeight: FontWeight.bold, 
                          fontFamily: 'monospace', 
                          fontSize: 20, 
                          color: Colors.blue.shade800,
                          letterSpacing: 2,
                        )),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: _limpiarFormulario,
                    icon: Icon(Icons.refresh, color: Colors.blue.shade600, size: 28),
                    tooltip: 'Escanear otro',
                  ),
                ],
              ),
            ),

          // Fotos
          if (_fotos.isNotEmpty) ...[
            const Text('Fotos', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 18)),
            const SizedBox(height: 12),
            SizedBox(
              height: 100,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: _fotos.length + 1,
                itemBuilder: (_, i) {
                  if (i == _fotos.length) {
                    return GestureDetector(
                      onTap: _tomarFoto,
                      child: Container(
                        width: 100, height: 100,
                        decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(16)),
                        child: Icon(Icons.add_a_photo, color: Colors.grey.shade400, size: 36),
                      ),
                    );
                  }
                  return Stack(
                    children: [
                      Container(
                        width: 100, height: 100,
                        margin: const EdgeInsets.only(right: 12),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16), 
                          image: DecorationImage(image: FileImage(_fotos[i]), fit: BoxFit.cover),
                        ),
                      ),
                      Positioned(
                        top: 6, right: 18,
                        child: GestureDetector(
                          onTap: () => _eliminarFoto(i),
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                            child: const Icon(Icons.close, color: Colors.white, size: 16),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            const SizedBox(height: 24),
          ],

          // Campo: Nombre
          const Text('Nombre del producto *', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 18)),
          const SizedBox(height: 10),
          TextField(
            controller: _nombreController,
            textCapitalization: TextCapitalization.words,
            style: const TextStyle(fontSize: 20),
            decoration: InputDecoration(
              hintText: 'Ej: Café Premium 250g',
              filled: true, fillColor: Colors.white,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: Colors.grey.shade300)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: Colors.grey.shade300)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: Colors.blue.shade600, width: 2)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
            ),
          ),

          const SizedBox(height: 24),
          
          // Campo: Precio
          const Text('Precio *', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 18)),
          const SizedBox(height: 10),
          TextField(
            controller: _precioController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            decoration: InputDecoration(
              hintText: '0.00', 
              prefixText: 'S/ ',
              prefixStyle: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.grey.shade700),
              filled: true, fillColor: Colors.white,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: Colors.grey.shade300)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: Colors.grey.shade300)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: Colors.blue.shade600, width: 2)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
            ),
          ),

          const SizedBox(height: 24),
          
          // Campo: Stock
          const Text('Stock inicial', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 18)),
          const SizedBox(height: 10),
          TextField(
            controller: _stockController,
            keyboardType: TextInputType.number,
            style: const TextStyle(fontSize: 20),
            decoration: InputDecoration(
              hintText: '0', suffixText: 'unidades',
              filled: true, fillColor: Colors.white,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: Colors.grey.shade300)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: Colors.grey.shade300)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: Colors.blue.shade600, width: 2)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
            ),
          ),

          const SizedBox(height: 40),
          
          // Botones de acción
          Row(
            children: [
              // Guardar y continuar (modo rápido)
              Expanded(
                child: SizedBox(
                  height: 60,
                  child: OutlinedButton.icon(
                    onPressed: _isLoading ? null : _guardarYContinuar,
                    icon: const Icon(Icons.add, size: 24),
                    label: const Text('Guardar y seguir', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    style: OutlinedButton.styleFrom(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      side: BorderSide(color: Colors.blue.shade600, width: 2),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              // Guardar y salir
              Expanded(
                child: SizedBox(
                  height: 60,
                  child: ElevatedButton.icon(
                    onPressed: _isLoading ? null : _guardarProducto,
                    icon: _isLoading 
                        ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) 
                        : const Icon(Icons.save, size: 24),
                    label: Text(_isLoading ? 'Guardando...' : 'Guardar', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
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
          
          const SizedBox(height: 16),
          Center(
            child: TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar', style: TextStyle(fontSize: 16)),
            ),
          ),
          
          const SizedBox(height: 20),
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
    _codigoManualController.dispose();
    _codigoFocusNode.dispose();
    _scanSubscription?.cancel();
    super.dispose();
  }
}
