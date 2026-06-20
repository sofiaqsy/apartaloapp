import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../services/api_service.dart';

class DetalleProductoScreen extends StatefulWidget {
  final Map<String, dynamic> producto;

  const DetalleProductoScreen({super.key, required this.producto});

  @override
  State<DetalleProductoScreen> createState() => _DetalleProductoScreenState();
}

class _DetalleProductoScreenState extends State<DetalleProductoScreen> {
  late TextEditingController _nombreController;
  late TextEditingController _descripcionController;

  String? _imagenUrlExistente;
  File? _nuevaFoto;
  bool _isLoading = false;
  bool _hasChanges = false;
  // Presentaciones
  List<Presentacion> _presentaciones = [];
  bool _loadingPresentaciones = false;
  double? _availableKg;                        // kg de eventos completados (null = sin lotes)
  double _roastedKg = 0;                       // total kg de lotes completados
  List<LoteCompletado> _completedLots = const []; // detalle por lote
  double _nextEventKg = 0;                     // kg del próximo evento (no disponibles aún)
  String? _nextEventDate;                      // fecha ISO del próximo evento
  String? _nextEventStatus;                    // 'planned' | 'in_progress'
  String? _nextEventLotCode;                   // código de lote
  double? _greenKg;                            // kg disponibles de lote verde
  String? _greenLotCode;                       // código del lote verde
  bool _isGreenCoffee = false;                 // true si tiene green_lot_id

  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _cargarDatos();
    _cargarPresentaciones();
  }

  Future<void> _cargarPresentaciones() async {
    final productId = widget.producto['codigo']?.toString() ?? '';
    if (productId.isEmpty) return;
    if (mounted) setState(() => _loadingPresentaciones = true);
    final result = await ApiService.getPresentaciones(productId);
    if (mounted) setState(() {
      _presentaciones    = result.isSuccess ? (result.data?.presentaciones  ?? [])    : [];
      _availableKg       = result.isSuccess ? result.data?.availableKg                : null;
      _roastedKg         = result.isSuccess ? (result.data?.roastedKg       ?? 0)    : 0;
      _completedLots     = result.isSuccess ? (result.data?.completedLots   ?? [])   : [];
      _nextEventKg       = result.isSuccess ? (result.data?.nextEventKg     ?? 0)    : 0;
      _nextEventDate     = result.isSuccess ? result.data?.nextEventDate              : null;
      _nextEventStatus   = result.isSuccess ? result.data?.nextEventStatus            : null;
      _nextEventLotCode  = result.isSuccess ? result.data?.nextEventLotCode           : null;
      _greenKg           = result.isSuccess ? result.data?.greenKg                    : null;
      _greenLotCode      = result.isSuccess ? result.data?.greenLotCode               : null;
      _isGreenCoffee     = result.isSuccess ? (result.data?.isGreenCoffee  ?? false) : false;
      _loadingPresentaciones = false;
    });
  }


  void _cargarDatos() {
    final p = widget.producto;
    _nombreController = TextEditingController(text: p['nombre'] ?? '');
    _descripcionController = TextEditingController(text: p['descripcion'] ?? '');
    _imagenUrlExistente = p['imagenUrl'];
    _nombreController.addListener(_onChanged);
    _descripcionController.addListener(_onChanged);
  }

  void _onChanged() {
    if (!_hasChanges) {
      setState(() => _hasChanges = true);
    }
  }

  Future<void> _tomarFoto() async {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Tomar foto'),
              onTap: () async {
                Navigator.pop(context);
                final foto = await _picker.pickImage(
                  source: ImageSource.camera,
                  maxWidth: 1024,
                  maxHeight: 1024,
                  imageQuality: 85,
                );
                if (foto != null) {
                  setState(() {
                    _nuevaFoto = File(foto.path);
                    _hasChanges = true;
                  });
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Elegir de galería'),
              onTap: () async {
                Navigator.pop(context);
                final foto = await _picker.pickImage(
                  source: ImageSource.gallery,
                  maxWidth: 1024,
                  maxHeight: 1024,
                  imageQuality: 85,
                );
                if (foto != null) {
                  setState(() {
                    _nuevaFoto = File(foto.path);
                    _hasChanges = true;
                  });
                }
              },
            ),
            if (_imagenUrlExistente != null || _nuevaFoto != null)
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
                title: const Text('Eliminar imagen', style: TextStyle(color: Colors.red)),
                onTap: () {
                  Navigator.pop(context);
                  setState(() {
                    _nuevaFoto = null;
                    _imagenUrlExistente = null;
                    _hasChanges = true;
                  });
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _guardarCambios() async {
    final nombre = _nombreController.text.trim();
    if (nombre.isEmpty) {
      _mostrarError('Ingresa el nombre');
      return;
    }

    setState(() => _isLoading = true);

    String? imagenUrl = _imagenUrlExistente;
    if (_nuevaFoto != null) {
      _mostrarSnackBar('📤 Subiendo foto...', Colors.blue);
      final uploadResult = await ApiService.uploadImage(_nuevaFoto!);
      if (uploadResult.isSuccess) imagenUrl = uploadResult.data;
    }

    final descripcion = _descripcionController.text.trim();

    final result = await ApiService.actualizarProducto(
      codigo: widget.producto['codigo'],
      nombre: nombre,
      descripcion: descripcion.isNotEmpty ? descripcion : null,
      imagenUrl: imagenUrl,
    );

    setState(() => _isLoading = false);

    if (result.isSuccess && mounted) {
      _mostrarSnackBar('✅ Producto actualizado', Colors.green);
      Navigator.pop(context, true);
    } else {
      _mostrarError(result.error ?? 'Error al guardar');
    }
  }


  void _mostrarConvertirSheet() {
    final cantidadUsarCtrl = TextEditingController(text: '1');
    final unidadesProduceCtrl = TextEditingController(text: '1');
    String? productoDestinoId;
    List<Map<String, dynamic>> productosSheet = [];
    bool loadingSheet = true;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final productoOrigen = widget.producto;
          final stockActual = (productoOrigen['stock'] as num?)?.toInt() ?? 0;

          // Load products inside the sheet on first build
          if (loadingSheet) {
            loadingSheet = false;
            ApiService.getProductos(limite: 200).then((result) {
              if (result.isSuccess) {
                final codigoActual = productoOrigen['codigo'] ?? '';
                setSheetState(() {
                  productosSheet = (result.data?.productos ?? [])
                      .where((p) => p['codigo'] != codigoActual)
                      .toList();
                });
              } else {
                setSheetState(() => productosSheet = []);
              }
            });
          }

          Future<void> confirmarConversion() async {
            final cantUsar = int.tryParse(cantidadUsarCtrl.text.trim()) ?? 0;
            final cantProduce = int.tryParse(unidadesProduceCtrl.text.trim()) ?? 0;

            if (cantUsar <= 0 || cantProduce <= 0 || productoDestinoId == null) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Completa todos los campos'), backgroundColor: Colors.orange),
              );
              return;
            }
            if (cantUsar > stockActual) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Stock insuficiente (disponible: $stockActual)'), backgroundColor: Colors.red),
              );
              return;
            }

            Navigator.pop(ctx);
            setState(() => _isLoading = true);

            // 1. Restar del producto origen
            final restarResult = await ApiService.actualizarStock(
              codigo: productoOrigen['codigo'],
              cantidad: cantUsar,
              operacion: 'restar',
            );

            if (!restarResult.isSuccess) {
              setState(() => _isLoading = false);
              _mostrarError(restarResult.error ?? 'Error al descontar stock origen');
              return;
            }

            // 2. Agregar al producto destino
            final agregarResult = await ApiService.actualizarStock(
              codigo: productoDestinoId!,
              cantidad: cantProduce,
              operacion: 'agregar',
            );

            setState(() => _isLoading = false);

            if (agregarResult.isSuccess) {
              _cargarPresentaciones();
              final destinoNombre = productosSheet
                  .firstWhere((p) => p['codigo'] == productoDestinoId, orElse: () => {'nombre': productoDestinoId!})['nombre'];
              _mostrarSnackBar(
                '✅ -$cantUsar ${productoOrigen['nombre']} → +$cantProduce $destinoNombre',
                Colors.teal,
              );
            } else {
              // Conversion failed midway — revert source stock
              await ApiService.actualizarStock(
                codigo: productoOrigen['codigo'],
                cantidad: cantUsar,
                operacion: 'agregar',
              );
              _mostrarError('Error al agregar stock destino. Se revirtió el origen.');
            }
          }

          return Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            padding: EdgeInsets.only(
              left: 20, right: 20, top: 20,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
            ),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Handle
                  Center(
                    child: Container(
                      width: 40, height: 4,
                      decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Title
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(color: Colors.teal.shade50, shape: BoxShape.circle),
                        child: Icon(Icons.transform_rounded, color: Colors.teal.shade600, size: 20),
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Convertir / Envasar', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                            Text('Transforma unidades de un producto en otro', style: TextStyle(fontSize: 12, color: Colors.grey)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Origen
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.teal.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.teal.shade100),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.inventory_2_outlined, color: Colors.teal.shade600, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Origen', style: TextStyle(fontSize: 11, color: Colors.teal.shade700, fontWeight: FontWeight.w600)),
                              Text(productoOrigen['nombre'] ?? '', style: const TextStyle(fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(color: Colors.teal.shade100, borderRadius: BorderRadius.circular(20)),
                          child: Text('Stock: $stockActual', style: TextStyle(fontSize: 12, color: Colors.teal.shade800, fontWeight: FontWeight.w600)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Cantidad a usar
                  const Text('¿Cuántas unidades usarás?', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: cantidadUsarCtrl,
                    keyboardType: TextInputType.number,
                    onChanged: (_) => setSheetState(() {}),
                    decoration: InputDecoration(
                      hintText: 'Ej: 1',
                      suffixText: productoOrigen['unidad'] ?? 'uds',
                      filled: true, fillColor: Colors.grey.shade50,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Arrow
                  Center(
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(color: Colors.grey.shade100, shape: BoxShape.circle),
                      child: Icon(Icons.arrow_downward_rounded, color: Colors.grey.shade500, size: 20),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Producto destino
                  const Text('Producto destino', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  const SizedBox(height: 6),
                  productosSheet.isEmpty
                      ? const Center(child: Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ))
                      : DropdownButtonFormField<String>(
                          value: productoDestinoId,
                          isExpanded: true,
                          hint: const Text('Selecciona el producto destino', overflow: TextOverflow.ellipsis),
                          decoration: InputDecoration(
                            filled: true, fillColor: Colors.grey.shade50,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                          ),
                          items: productosSheet.map((p) => DropdownMenuItem(
                            value: p['codigo'] as String,
                            child: Text(
                              '${p['nombre']} · Stock: ${p['stock'] ?? 0}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          )).toList(),
                          onChanged: (val) => setSheetState(() => productoDestinoId = val),
                        ),
                  const SizedBox(height: 16),

                  // Unidades que produce
                  const Text('¿Cuántas unidades produce?', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: unidadesProduceCtrl,
                    keyboardType: TextInputType.number,
                    onChanged: (_) => setSheetState(() {}),
                    decoration: InputDecoration(
                      hintText: 'Ej: 4',
                      filled: true, fillColor: Colors.grey.shade50,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    ),
                  ),

                  // Preview
                  if ((int.tryParse(cantidadUsarCtrl.text) ?? 0) > 0 && (int.tryParse(unidadesProduceCtrl.text) ?? 0) > 0 && productoDestinoId != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.blue.shade100),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline, size: 16, color: Colors.blue.shade600),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Se restará ${cantidadUsarCtrl.text} de "${productoOrigen['nombre']}" '
                              'y se añadirá ${unidadesProduceCtrl.text} a "${productosSheet.firstWhere((p) => p['codigo'] == productoDestinoId, orElse: () => {'nombre': '?'})['nombre']}"',
                              style: TextStyle(fontSize: 12, color: Colors.blue.shade700),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: confirmarConversion,
                      icon: const Icon(Icons.transform_rounded),
                      label: const Text('Confirmar conversión', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.teal,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
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

  void _mostrarError(String msg) => _mostrarSnackBar(msg, Colors.red);

  void _mostrarSnackBar(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: color),
    );
  }

  Future<void> _confirmPop() async {
    if (!_hasChanges) {
      if (mounted) Navigator.of(context).pop();
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Descartar cambios?'),
        content: const Text('Tienes cambios sin guardar. ¿Deseas descartarlos?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Descartar', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if ((ok ?? false) && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final codigo = widget.producto['codigo'] ?? '';

    return PopScope(
      canPop: !_hasChanges,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmPop();
      },
      child: Scaffold(
        backgroundColor: Colors.grey.shade100,
        appBar: AppBar(
          title: const Text('Detalle del Producto'),
          backgroundColor: Colors.blue.shade600,
          foregroundColor: Colors.white,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _confirmPop,
          ),
          actions: [
            if (_hasChanges)
              TextButton(
                onPressed: _isLoading ? null : _guardarCambios,
                child: const Text('Guardar', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
              ),
          ],
        ),
        body: GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(),
          behavior: HitTestBehavior.translucent,
          child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                child: Column(
                  children: [
                    // Imagen
                    GestureDetector(
                      onTap: _tomarFoto,
                      child: Container(
                        width: double.infinity,
                        height: 250,
                        color: Colors.grey.shade200,
                        child: _buildImagen(),
                      ),
                    ),

                    // Código de barras
                    if (codigo.isNotEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        color: Colors.grey.shade800,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.qr_code, color: Colors.white70, size: 20),
                            const SizedBox(width: 8),
                            Text(
                              codigo,
                              style: const TextStyle(
                                color: Colors.white,
                                fontFamily: 'monospace',
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),

                    // ── Presentaciones ──────────────────────────────────
                    Container(
                      padding: const EdgeInsets.all(16),
                      color: Colors.white,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Icon(Icons.layers_outlined, size: 18, color: Colors.indigo.shade600),
                            const SizedBox(width: 8),
                            Expanded(child: Text('Presentaciones',
                              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: Colors.indigo.shade700))),
                            if (_loadingPresentaciones)
                              const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                            else ...[
                              GestureDetector(
                                onTap: _cargarPresentaciones,
                                child: Padding(
                                  padding: const EdgeInsets.only(right: 10),
                                  child: Icon(Icons.refresh_rounded, size: 18, color: Colors.grey.shade400),
                                ),
                              ),
                              GestureDetector(
                                onTap: _mostrarFormPresentacion,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.indigo.shade50,
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                                    Icon(Icons.add, size: 14, color: Colors.indigo.shade600),
                                    const SizedBox(width: 4),
                                    Text('Agregar', style: TextStyle(fontSize: 12, color: Colors.indigo.shade600, fontWeight: FontWeight.w600)),
                                  ]),
                                ),
                              ),
                            ],
                          ]),
                          const SizedBox(height: 6),
                          if (!_loadingPresentaciones) ...[
                            _buildStockBreakdown(),
                            const SizedBox(height: 8),
                          ],
                          Text(
                            'Cada presentación tiene su propio precio, stock y tipo de molienda.',
                            style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                          ),
                          const SizedBox(height: 12),
                          if (_loadingPresentaciones)
                            const Center(child: Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator(strokeWidth: 2)))
                          else if (_presentaciones.isEmpty)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Text('Sin presentaciones. Agrega una para que el producto aparezca con precio.',
                                style: TextStyle(fontSize: 12, color: Colors.orange.shade600)),
                            )
                          else
                            ..._presentaciones.map(_buildPresentacionTile),
                        ],
                      ),
                    ),

                    const SizedBox(height: 8),

                    // Formulario
                    Container(
                      padding: const EdgeInsets.all(16),
                      color: Colors.white,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildCampo(
                            label: 'Nombre del producto *',
                            controller: _nombreController,
                            hint: 'Ej: Café Blend',
                          ),
                          const SizedBox(height: 16),
                          _buildCampo(
                            label: 'Descripción (opcional)',
                            controller: _descripcionController,
                            hint: 'Descripción del producto...',
                            maxLines: 3,
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Botón guardar
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: SizedBox(
                        width: double.infinity,
                        height: 54,
                        child: ElevatedButton.icon(
                          onPressed: _isLoading || !_hasChanges ? null : _guardarCambios,
                          icon: const Icon(Icons.save),
                          label: const Text('Guardar Cambios', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue.shade600,
                            foregroundColor: Colors.white,
                            disabledBackgroundColor: Colors.grey.shade300,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 32),
                  ],
                ),
              ),
          ),
      ),
    );
  }

  Widget _buildImagen() {
    // Nueva foto tomada
    if (_nuevaFoto != null) {
      return Stack(
        fit: StackFit.expand,
        children: [
          Image.file(_nuevaFoto!, fit: BoxFit.cover),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.all(12),
              color: Colors.black54,
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.photo_camera, color: Colors.white, size: 20),
                  SizedBox(width: 8),
                  Text('Nueva foto - Toca para cambiar', style: TextStyle(color: Colors.white)),
                ],
              ),
            ),
          ),
          Positioned(
            top: 8,
            right: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.blue,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text('Nueva', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      );
    }

    // Imagen existente de Drive
    if (_imagenUrlExistente != null && _imagenUrlExistente!.isNotEmpty) {
      return Stack(
        fit: StackFit.expand,
        children: [
          Image.network(
            _imagenUrlExistente!,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _buildPlaceholderImagen(),
            loadingBuilder: (context, child, loadingProgress) {
              if (loadingProgress == null) return child;
              return Center(
                child: CircularProgressIndicator(
                  value: loadingProgress.expectedTotalBytes != null
                      ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
                      : null,
                ),
              );
            },
          ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.all(12),
              color: Colors.black54,
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.photo_camera, color: Colors.white, size: 20),
                  SizedBox(width: 8),
                  Text('Toca para cambiar imagen', style: TextStyle(color: Colors.white)),
                ],
              ),
            ),
          ),
        ],
      );
    }

    // Sin imagen
    return _buildPlaceholderImagen();
  }

  Widget _buildPlaceholderImagen() {
    return Container(
      color: Colors.grey.shade200,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.add_a_photo, size: 64, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          Text(
            'Toca para agregar foto',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 16),
          ),
        ],
      ),
    );
  }

  Widget _buildBotonAccion({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: color.withOpacity(0.1),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: _isLoading ? null : onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(width: 8),
              Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCampo({
    required String label,
    required TextEditingController controller,
    String? hint,
    String? prefix,
    String? suffix,
    TextInputType? keyboardType,
    int maxLines = 1,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          maxLines: maxLines,
          decoration: InputDecoration(
            hintText: hint,
            prefixText: prefix,
            suffixText: suffix,
            filled: true,
            fillColor: Colors.grey.shade50,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.blue.shade400, width: 2),
            ),
          ),
        ),
      ],
    );
  }

  // ── Presentaciones helpers ───────────────────────────────────

  String _fmtKg(double kg) =>
      '${kg % 1 == 0 ? kg.toInt() : kg.toStringAsFixed(2)} kg';

  /// Formatea fecha ISO → "12 Jun 2025"
  String _fmtDate(String? iso) {
    if (iso == null) return '';
    try {
      final dt = DateTime.parse(iso).toLocal();
      const months = ['Ene','Feb','Mar','Abr','May','Jun','Jul','Ago','Sep','Oct','Nov','Dic'];
      return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
    } catch (_) { return ''; }
  }

  Future<void> _mostrarCrearEvento() async {
    final productId = widget.producto['codigo']?.toString() ?? '';
    if (productId.isEmpty) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _CrearEventoSheet(
        productId: productId,
        defaultLoteId: widget.producto['green_lot_id'] as String?,
        onCreado: () {
          if (mounted) _cargarPresentaciones();
        },
      ),
    );
  }

  Widget _buildStockBreakdown() {
    final hasNextEvent = _nextEventKg > 0 && _nextEventStatus != null;
    final roastedTotal = _roastedKg;
    final greenTotal   = _greenKg ?? 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Sección Tostado ────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.orange.shade50,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.orange.shade200),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Encabezado tostado
            Row(children: [
              Icon(Icons.local_fire_department_outlined, size: 15, color: Colors.orange.shade700),
              const SizedBox(width: 6),
              Text('Total disponible tostado',
                  style: TextStyle(fontSize: 12, color: Colors.orange.shade800, fontWeight: FontWeight.w700)),
              const Spacer(),
              Text(_fmtKg(roastedTotal),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: roastedTotal > 0 ? Colors.orange.shade800 : Colors.grey.shade400,
                  )),
            ]),
            // Detalle por lote completado
            if (_completedLots.where((l) => l.kg > 0).isNotEmpty) ...[
              const SizedBox(height: 6),
              ..._completedLots.where((l) => l.kg > 0).map((lote) => Padding(
                padding: const EdgeInsets.only(left: 19, top: 3),
                child: Row(children: [
                  Container(
                    width: 4, height: 4,
                    decoration: BoxDecoration(color: Colors.orange.shade300, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 6),
                  if (lote.lotCode != null && lote.lotCode!.isNotEmpty) ...[
                    Text(lote.lotCode!, style: TextStyle(fontSize: 10, color: Colors.grey.shade600, fontWeight: FontWeight.w600)),
                    Text(' · ', style: TextStyle(fontSize: 10, color: Colors.grey.shade400)),
                  ],
                  if (lote.roastedAt != null)
                    Text(_fmtDate(lote.roastedAt), style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
                  const Spacer(),
                  Text(_fmtKg(lote.kg), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.orange.shade600)),
                ]),
              )),
            ] else ...[
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.only(left: 19),
                child: Text('Sin lotes tostados disponibles',
                    style: TextStyle(fontSize: 10, color: Colors.grey.shade400)),
              ),
            ],
            // Botón crear evento
            const SizedBox(height: 10),
            Divider(height: 1, color: Colors.orange.shade100),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () => _mostrarCrearEvento(),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add_circle_outline, size: 14, color: Colors.orange.shade700),
                  const SizedBox(width: 6),
                  Text('Crear evento de tueste',
                      style: TextStyle(fontSize: 12, color: Colors.orange.shade700, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            // Siguiente stock (próximo evento)
            if (hasNextEvent) ...[
              const SizedBox(height: 8),
              Divider(height: 1, color: Colors.orange.shade100),
              const SizedBox(height: 8),
              Row(children: [
                Icon(Icons.event_outlined, size: 13, color: Colors.deepPurple.shade400),
                const SizedBox(width: 6),
                Text('Siguiente stock', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                const Spacer(),
                Text(_fmtKg(_nextEventKg),
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.deepPurple.shade600)),
              ]),
              const SizedBox(height: 4),
              Row(children: [
                const SizedBox(width: 19),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: _nextEventStatus == 'in_progress'
                        ? Colors.orange.shade50
                        : Colors.deepPurple.shade50,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: _nextEventStatus == 'in_progress'
                        ? Colors.orange.shade200
                        : Colors.deepPurple.shade100),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(
                      _nextEventStatus == 'in_progress' ? Icons.local_fire_department : Icons.schedule,
                      size: 10,
                      color: _nextEventStatus == 'in_progress' ? Colors.orange.shade700 : Colors.deepPurple.shade400,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      [
                        if (_nextEventLotCode != null && _nextEventLotCode!.isNotEmpty) _nextEventLotCode!,
                        if (_nextEventDate != null) _fmtDate(_nextEventDate),
                        if (_nextEventStatus == 'in_progress') 'En tueste' else 'Planificado',
                      ].join(' · '),
                      style: TextStyle(
                        fontSize: 10,
                        color: _nextEventStatus == 'in_progress' ? Colors.orange.shade800 : Colors.deepPurple.shade600,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ]),
                ),
              ]),
            ],
          ]),
        ),

        // ── Sección Verde ──────────────────────────────────────────────
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.green.shade50,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.green.shade200),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Encabezado verde
            Row(children: [
              Icon(Icons.eco_outlined, size: 15, color: Colors.green.shade700),
              const SizedBox(width: 6),
              Text('Total disponible verde',
                  style: TextStyle(fontSize: 12, color: Colors.green.shade800, fontWeight: FontWeight.w700)),
              const Spacer(),
              Text(_fmtKg(greenTotal),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: greenTotal > 0 ? Colors.green.shade800 : Colors.grey.shade400,
                  )),
            ]),
            // Detalle del lote verde
            if (_isGreenCoffee && _greenKg != null) ...[
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.only(left: 19),
                child: Row(children: [
                  Container(
                    width: 4, height: 4,
                    decoration: BoxDecoration(color: Colors.green.shade400, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 6),
                  if (_greenLotCode != null && _greenLotCode!.isNotEmpty) ...[
                    Text(_greenLotCode!, style: TextStyle(fontSize: 10, color: Colors.grey.shade600, fontWeight: FontWeight.w600)),
                    Text(' · ', style: TextStyle(fontSize: 10, color: Colors.grey.shade400)),
                  ],
                  Text('Lote verde', style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
                  const Spacer(),
                  Text(_fmtKg(greenTotal),
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.green.shade600)),
                ]),
              ),
            ] else ...[
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.only(left: 19),
                child: Text('Sin lote verde vinculado',
                    style: TextStyle(fontSize: 10, color: Colors.grey.shade400)),
              ),
            ],
          ]),
        ),
      ],
    );
  }

  Widget _buildPresentacionTile(Presentacion p) {
    final moliendaLabels = {'ground': 'Molido', 'whole': 'Grano', 'green': 'Verde'};
    final moliendaStr = p.molienda.map((m) => moliendaLabels[m] ?? m).join(', ');

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.indigo.shade100),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 4, offset: const Offset(0, 2))],
      ),
      child: Column(
        children: [
          // Header row: image + label + price + actions
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 8),
            child: Row(children: [
              if (p.imageUrl != null && p.imageUrl!.isNotEmpty) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: CachedNetworkImage(
                    imageUrl: p.imageUrl!,
                    width: 48, height: 48,
                    fit: BoxFit.cover,
                    memCacheWidth: 96,
                    placeholder: (_, __) => Container(
                      width: 48, height: 48,
                      color: Colors.grey.shade100,
                      child: Center(
                        child: SizedBox(
                          width: 16, height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.5,
                            color: Colors.grey.shade300,
                          ),
                        ),
                      ),
                    ),
                    errorWidget: (_, __, ___) => const SizedBox.shrink(),
                  ),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  if (p.predeterminada) ...[
                    Icon(Icons.star, size: 13, color: Colors.amber.shade600),
                    const SizedBox(width: 4),
                  ],
                  Text(p.etiqueta, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                ]),
                const SizedBox(height: 2),
                Row(children: [
                  Text('S/ ${p.precio.toStringAsFixed(2)}',
                      style: TextStyle(fontSize: 14, color: Colors.green.shade700, fontWeight: FontWeight.w700)),
                  if (p.precioB2b != null) ...[
                    const SizedBox(width: 8),
                    Text('B2B: S/ ${p.precioB2b!.toStringAsFixed(2)}',
                        style: TextStyle(fontSize: 11, color: Colors.blue.shade600)),
                  ],
                  if (moliendaStr.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Text(moliendaStr, style: TextStyle(fontSize: 11, color: Colors.brown.shade500)),
                  ],
                ]),
              ])),
              GestureDetector(
                onTap: () => _mostrarFormPresentacion(presentacion: p),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Icon(Icons.edit_outlined, size: 18, color: Colors.indigo.shade400),
                ),
              ),
              GestureDetector(
                onTap: () => _eliminarPresentacion(p),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                  child: Icon(Icons.delete_outline, size: 18, color: Colors.red.shade300),
                ),
              ),
            ]),
          ),
          // Stock (solo lectura — se deriva del lote disponible)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
              border: Border(top: BorderSide(color: Colors.indigo.shade50)),
            ),
            child: Row(children: [
              Icon(Icons.inventory_outlined, size: 14, color: Colors.grey.shade500),
              const SizedBox(width: 6),
              Text('Stock: ', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              Text('${p.stock}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.grey.shade700)),
              const SizedBox(width: 4),
              Text('unidades', style: TextStyle(fontSize: 11, color: Colors.grey.shade400)),
            ]),
          ),
        ],
      ),
    );
  }

  Future<void> _eliminarPresentacion(Presentacion p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar presentación'),
        content: Text('¿Eliminar la presentación "${p.etiqueta}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (ok != true) return;
    final productId = widget.producto['codigo']?.toString() ?? '';
    final result = await ApiService.eliminarPresentacion(productId: productId, presentationId: p.id);
    if (result.isSuccess) {
      _cargarPresentaciones();
      if (mounted) _mostrarSnackBar('Presentación eliminada', Colors.green);
    } else {
      if (mounted) _mostrarSnackBar(result.error ?? 'Error eliminando', Colors.red);
    }
  }

  void _mostrarFormPresentacion({Presentacion? presentacion}) {
    final productId = widget.producto['codigo']?.toString() ?? '';
    final esEdicion = presentacion != null;

    final contenidoCtrl = TextEditingController(
        text: esEdicion ? '${presentacion.contenido % 1 == 0 ? presentacion.contenido.toInt() : presentacion.contenido}' : '');
    final precioCtrl = TextEditingController(
        text: esEdicion ? presentacion.precio.toStringAsFixed(2) : '');
    final precioB2bCtrl = TextEditingController(
        text: esEdicion && presentacion.precioB2b != null ? presentacion.precioB2b!.toStringAsFixed(2) : '');
    final cantidadB2bCtrl = TextEditingController(
        text: esEdicion && presentacion.cantidadB2b != null ? presentacion.cantidadB2b.toString() : '');
    final pedidoMinimoCtrl = TextEditingController(
        text: esEdicion ? presentacion.pedidoMinimo.toString() : '1');

    String unidad = esEdicion ? presentacion.unidad : 'g';
    bool predeterminada = esEdicion ? presentacion.predeterminada : false;
    List<String> molienda = esEdicion ? List<String>.from(presentacion.molienda) : [];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(builder: (ctx, ss) {
        Future<void> guardar() async {
          final contenidoVal = double.tryParse(contenidoCtrl.text.trim()) ?? 0;
          final precioVal = double.tryParse(precioCtrl.text.trim()) ?? 0;
          if (contenidoVal <= 0 || precioVal <= 0) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Contenido y precio son obligatorios'), backgroundColor: Colors.orange));
            return;
          }
          final b2b = precioB2bCtrl.text.trim().isNotEmpty ? double.tryParse(precioB2bCtrl.text.trim()) : null;
          final cantB2b = cantidadB2bCtrl.text.trim().isNotEmpty ? int.tryParse(cantidadB2bCtrl.text.trim()) : null;
          final stock = esEdicion ? presentacion.stock : 0; // stock no se edita aquí
          final pedidoMinimo = int.tryParse(pedidoMinimoCtrl.text.trim()) ?? 1;

          Navigator.pop(ctx);

          ApiResponse<dynamic> result;
          if (esEdicion) {
            result = await ApiService.actualizarPresentacion(
              productId: productId,
              presentationId: presentacion.id,
              contenido: contenidoVal,
              unidad: unidad,
              precio: precioVal,
              precioB2b: b2b,
              cantidadB2b: cantB2b,
              stock: stock,
              pedidoMinimo: pedidoMinimo,
              predeterminada: predeterminada,
              molienda: molienda,
            );
          } else {
            result = await ApiService.crearPresentacion(
              productId: productId,
              contenido: contenidoVal,
              unidad: unidad,
              precio: precioVal,
              precioB2b: b2b,
              cantidadB2b: cantB2b,
              stock: stock,
              pedidoMinimo: pedidoMinimo,
              predeterminada: predeterminada,
              molienda: molienda,
            );
          }

          if (result.isSuccess) {
            _cargarPresentaciones();
            if (mounted) _mostrarSnackBar(
              esEdicion ? '✅ Presentación actualizada' : '✅ Presentación creada', Colors.green);
          } else {
            if (mounted) _mostrarSnackBar(result.error ?? 'Error', Colors.red);
          }
        }

        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: EdgeInsets.only(
            left: 20, right: 20, top: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: SingleChildScrollView(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(child: Container(width: 40, height: 4,
                decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 16),
              Row(children: [
                Container(padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: Colors.indigo.shade50, shape: BoxShape.circle),
                  child: Icon(Icons.layers_outlined, color: Colors.indigo.shade600, size: 20)),
                const SizedBox(width: 10),
                Text(esEdicion ? 'Editar presentación' : 'Nueva presentación',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              ]),
              const SizedBox(height: 20),

              // Contenido + unidad
              const Text('Contenido', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              const SizedBox(height: 6),
              Row(children: [
                Expanded(child: TextField(
                  controller: contenidoCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    hintText: 'Ej: 250',
                    filled: true, fillColor: Colors.grey.shade50,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  ),
                )),
                const SizedBox(width: 10),
                DropdownButton<String>(
                  value: unidad,
                  items: const [
                    DropdownMenuItem(value: 'g', child: Text('g')),
                    DropdownMenuItem(value: 'kg', child: Text('kg')),
                    DropdownMenuItem(value: 'und', child: Text('und')),
                  ],
                  onChanged: (v) => ss(() => unidad = v ?? unidad),
                ),
              ]),
              const SizedBox(height: 16),

              // Precio + B2B
              Row(children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Precio *', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: precioCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      prefixText: 'S/ ',
                      hintText: '0.00',
                      filled: true, fillColor: Colors.green.shade50,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    ),
                  ),
                ])),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Precio B2B', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: precioB2bCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      prefixText: 'S/ ',
                      hintText: 'Opcional',
                      filled: true, fillColor: Colors.grey.shade50,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    ),
                  ),
                ])),
              ]),
              const SizedBox(height: 12),

              // Cantidad mínima para B2B
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Cant. mínima para precio B2B', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(height: 6),
                TextField(
                  controller: cantidadB2bCtrl,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    hintText: 'Ej: 6 (opcional)',
                    filled: true, fillColor: Colors.blue.shade50,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  ),
                ),
              ]),
              const SizedBox(height: 16),

              // Pedido mínimo
              const Text('Pedido mínimo', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              const SizedBox(height: 6),
              TextField(
                controller: pedidoMinimoCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  hintText: '1',
                  filled: true, fillColor: Colors.grey.shade50,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
              ),
              const SizedBox(height: 16),

              // Molienda
              const Text('Tipo de molienda', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              const SizedBox(height: 8),
              Wrap(spacing: 8, children: [
                for (final entry in {'ground': 'Molido', 'whole': 'Grano', 'green': 'Verde'}.entries)
                  FilterChip(
                    label: Text(entry.value),
                    selected: molienda.contains(entry.key),
                    onSelected: (v) => ss(() {
                      if (v) {
                        molienda.add(entry.key);
                      } else {
                        molienda.remove(entry.key);
                      }
                    }),
                    selectedColor: Colors.brown.shade100,
                    checkmarkColor: Colors.brown.shade700,
                    labelStyle: TextStyle(
                      color: molienda.contains(entry.key) ? Colors.brown.shade700 : Colors.grey.shade700,
                    ),
                  ),
              ]),
              const SizedBox(height: 16),

              // Predeterminada
              SwitchListTile(
                value: predeterminada,
                onChanged: (v) => ss(() => predeterminada = v),
                title: const Text('Presentación predeterminada', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                subtitle: const Text('Se usará como precio base del producto', style: TextStyle(fontSize: 11)),
                contentPadding: EdgeInsets.zero,
                activeColor: Colors.indigo,
              ),
              const SizedBox(height: 20),

              SizedBox(width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: guardar,
                  icon: const Icon(Icons.save_rounded),
                  label: Text(esEdicion ? 'Guardar cambios' : 'Crear presentación',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.indigo,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                )),
            ],
          )),
        );
      }),
    );
  }

  @override
  void dispose() {
    _nombreController.dispose();
    _descripcionController.dispose();
    super.dispose();
  }
}

// ─────────────────────────────────────────────────────────────
// Inline stock stepper — no modal, auto-saves after 800 ms idle
// ─────────────────────────────────────────────────────────────
class _StockStepper extends StatefulWidget {
  final Presentacion presentacion;
  final String productId;
  final VoidCallback onUpdated;

  const _StockStepper({
    required this.presentacion,
    required this.productId,
    required this.onUpdated,
  });

  @override
  State<_StockStepper> createState() => _StockStepperState();
}

class _StockStepperState extends State<_StockStepper> {
  late int _stock;
  bool _saving = false;
  bool _editing = false;
  late TextEditingController _ctrl;
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _stock = widget.presentacion.stock;
    _ctrl = TextEditingController(text: '$_stock');
    _focus.addListener(() {
      if (!_focus.hasFocus && _editing) _commitEdit();
    });
  }

  @override
  void didUpdateWidget(_StockStepper old) {
    super.didUpdateWidget(old);
    if (!_editing) {
      _stock = widget.presentacion.stock;
      _ctrl.text = '$_stock';
    }
  }

  void _startEdit() {
    _ctrl.text = '$_stock';
    _ctrl.selection = TextSelection(baseOffset: 0, extentOffset: _ctrl.text.length);
    _focus.requestFocus();
    setState(() => _editing = true);
  }

  void _commitEdit() {
    final v = int.tryParse(_ctrl.text.trim());
    setState(() {
      _editing = false;
      if (v != null && v >= 0) _stock = v.clamp(0, 99999);
      _ctrl.text = '$_stock';
    });
  }

  Future<void> _save() async {
    if (_editing) _commitEdit();
    if (_saving) return;
    setState(() => _saving = true);
    final p = widget.presentacion;
    final result = await ApiService.actualizarPresentacion(
      productId: widget.productId,
      presentationId: p.id,
      contenido: p.contenido.toDouble(),
      unidad: p.unidad,
      precio: p.precio,
      precioB2b: p.precioB2b,
      cantidadB2b: p.cantidadB2b,
      stock: _stock,
      pedidoMinimo: p.pedidoMinimo,
      predeterminada: p.predeterminada,
      molienda: p.molienda,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (result.isSuccess) {
      widget.onUpdated();
    } else {
      setState(() { _stock = widget.presentacion.stock; _ctrl.text = '$_stock'; });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.error ?? 'Error al guardar'), backgroundColor: Colors.red));
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final stockBajo = _stock < 5;
    final bg = stockBajo ? Colors.red.shade50 : Colors.indigo.shade50;
    final fg = stockBajo ? Colors.red.shade700 : Colors.indigo.shade700;

    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(children: [
        Icon(Icons.inventory_2_outlined, size: 14, color: fg.withOpacity(0.6)),
        const SizedBox(width: 6),
        Text('Stock:', style: TextStyle(fontSize: 12, color: fg.withOpacity(0.7))),
        const SizedBox(width: 8),
        // Editable number
        Expanded(
          child: GestureDetector(
            onTap: _editing ? null : _startEdit,
            child: _editing
                ? TextField(
                    controller: _ctrl,
                    focusNode: _focus,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.start,
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: fg),
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                      isDense: true,
                    ),
                    onSubmitted: (_) => _commitEdit(),
                  )
                : Text(
                    '$_stock',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: fg),
                  ),
          ),
        ),
        // Guardar — always visible
        TextButton(
          onPressed: _saving ? null : _save,
          style: TextButton.styleFrom(
            backgroundColor: fg,
            foregroundColor: Colors.white,
            minimumSize: const Size(72, 34),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          child: _saving
              ? const SizedBox(width: 16, height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Guardar', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
        ),
      ]),
    );
  }
}

class _StepBtn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _StepBtn({required this.icon, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: 56,
          height: 52,
          child: Icon(icon, size: 26, color: color),
        ),
      ),
    );
  }
}

// ── Bottom sheet: crear evento de tueste ──────────────────────────────────────
class _CrearEventoSheet extends StatefulWidget {
  final String productId;
  final String? defaultLoteId;
  final VoidCallback onCreado;

  const _CrearEventoSheet({
    required this.productId,
    this.defaultLoteId,
    required this.onCreado,
  });

  @override
  State<_CrearEventoSheet> createState() => _CrearEventoSheetState();
}

class _CrearEventoSheetState extends State<_CrearEventoSheet> {
  final _kgCtrl       = TextEditingController();
  final _kgSalidaCtrl = TextEditingController();
  late String? _loteId;
  DateTime _fechaHora    = DateTime.now().add(const Duration(hours: 1));
  bool _submitting       = false;
  bool _loadingLotes     = true;
  List<Map<String, dynamic>> _lotes = [];

  @override
  void initState() {
    super.initState();
    _loteId = widget.defaultLoteId;
    _cargarLotes();
  }

  Future<void> _cargarLotes() async {
    final res = await ApiService.getLotesVerdes();
    if (!mounted) return;
    setState(() {
      _lotes = res.data ?? [];
      _loadingLotes = false;
      if (_loteId == null && _lotes.isNotEmpty) {
        _loteId = _lotes.first['id'] as String?;
      }
    });
  }

  @override
  void dispose() {
    _kgCtrl.dispose();
    _kgSalidaCtrl.dispose();
    super.dispose();
  }

  String _fmtFecha(DateTime dt) =>
      '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}'
      '  ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

  Future<void> _pickFechaHora() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _fechaHora,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_fechaHora),
    );
    if (time == null || !mounted) return;
    setState(() => _fechaHora =
        DateTime(date.year, date.month, date.day, time.hour, time.minute));
  }

  Future<void> _submit() async {
    if (_loteId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Selecciona un lote verde')));
      return;
    }
    final kg = double.tryParse(_kgCtrl.text.trim());
    if (kg == null || kg <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ingresa los kg a tostar')));
      return;
    }
    setState(() => _submitting = true);
    final kgSalida = double.tryParse(_kgSalidaCtrl.text.trim());
    final res = await ApiService.crearEventoTueste(
      greenLotId:    _loteId!,
      greenInKg:     kg,
      roastedAt:     _fechaHora.toUtc().toIso8601String(),
      productId:     widget.productId,
      roastedOutKg:  kgSalida,
    );
    if (!mounted) return;
    if (res.isSuccess) {
      Navigator.pop(context);
      widget.onCreado();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: const Text('Evento creado exitosamente'),
            backgroundColor: Colors.green.shade600),
      );
    } else {
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(res.error ?? 'Error'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20, right: 20, top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Text('Nuevo evento de tueste',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700,
                      color: Colors.orange.shade800)),
              const Spacer(),
              IconButton(icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context)),
            ]),
            const SizedBox(height: 16),

            Text('Lote verde',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            if (_loadingLotes)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Center(child: SizedBox(height: 20, width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))),
              )
            else if (_lotes.isEmpty)
              Text('Sin lotes verdes disponibles',
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade400))
            else
              DropdownButtonFormField<String>(
                value: _loteId,
                decoration: InputDecoration(
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  isDense: true,
                ),
                hint: const Text('Selecciona un lote'),
                items: _lotes.map((l) {
                  final variety = (l['variety'] as Map?)?['name'] as String?;
                  final label = [
                    l['lot_code'] as String? ?? '',
                    if (variety != null && variety.isNotEmpty) variety,
                    if (l['harvest_year'] != null) '${l['harvest_year']}',
                    '${l['current_kg']} kg',
                  ].join(' · ');
                  return DropdownMenuItem<String>(
                    value: l['id'] as String,
                    child: Text(label, style: const TextStyle(fontSize: 13)),
                  );
                }).toList(),
                onChanged: (v) => setState(() => _loteId = v),
              ),
            const SizedBox(height: 14),

            Text('Kg de verde a tostar',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            TextField(
              controller: _kgCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                hintText: 'Ej: 65',
                hintStyle: TextStyle(color: Colors.grey.shade300),
                suffixText: 'kg',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                isDense: true,
              ),
            ),
            const SizedBox(height: 14),

            Text('Estimado de salida (opcional)',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            TextField(
              controller: _kgSalidaCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                hintText: 'Ej: 52',
                hintStyle: TextStyle(color: Colors.grey.shade300),
                suffixText: 'kg',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                isDense: true,
              ),
            ),
            const SizedBox(height: 14),

            Text('Fecha / hora',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            GestureDetector(
              onTap: _pickFechaHora,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade400),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(children: [
                  Icon(Icons.calendar_today_outlined, size: 16,
                      color: Colors.grey.shade500),
                  const SizedBox(width: 8),
                  Text(_fmtFecha(_fechaHora), style: const TextStyle(fontSize: 13)),
                ]),
              ),
            ),
            const SizedBox(height: 20),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange.shade700,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: _submitting ? null : _submit,
                child: _submitting
                    ? const SizedBox(height: 18, width: 18,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text('Crear evento',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
