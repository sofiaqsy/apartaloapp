import '../widgets/fincas_widgets.dart';
import '../theme/fincas_tokens.dart';
import '../widgets/presentacion_tile.dart';
import '../widgets/producto_info_general.dart';
import '../widgets/producto_presentaciones_ajustes.dart';
import '../models/producto_info.dart';
import 'dart:async';
import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../providers/printer_provider.dart';
import '../services/api_service.dart';
import '../services/printer_service.dart';

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
  bool _infoDirty = false; // cambios sin guardar en "Información general"
  bool _ajustesDirty = false; // cambios sin guardar en los ajustes de presentaciones
  bool _stockManual = false; // el stock de cada presentación se escribe a mano
  String _simboloMoneda = 'S/'; // símbolo de la moneda del producto
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
  List<ProximoEvento> _upcomingEvents = const [];
  final Set<String> _uploadingEvents = {};
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
      _upcomingEvents    = result.isSuccess ? (result.data?.upcomingEvents  ?? [])   : [];
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

  /// "Información general" ya guardó: se actualizan el título y los datos del producto de la lista
  /// sin contar el cambio como pendiente.
  void _infoGuardada(ProductoInfo info) {
    _nombreController.removeListener(_onChanged);
    _descripcionController.removeListener(_onChanged);
    _nombreController.text = info.nombre;
    _descripcionController.text = info.descripcionBreve;
    _nombreController.addListener(_onChanged);
    _descripcionController.addListener(_onChanged);
    widget.producto['nombre'] = info.nombre;
    widget.producto['descripcion'] = info.descripcionBreve;
    if (mounted) setState(() {});
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
    if (!_hasChanges && !_infoDirty && !_ajustesDirty) {
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

  // ── Redesigned build: tab-based layout ─────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: PopScope(
        canPop: !_hasChanges && !_infoDirty && !_ajustesDirty,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _confirmPop();
        },
        child: Scaffold(
          backgroundColor: const Color(0xFFF5F4F0),
          appBar: AppBar(
            backgroundColor: const Color(0xFF231e14),
            foregroundColor: Colors.white,
            elevation: 0,
            leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: _confirmPop),
            title: Text(
              _nombreController.text.isNotEmpty
                  ? _nombreController.text
                  : (widget.producto['nombre'] ?? 'Producto'),
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            actions: [
              if (_hasChanges)
                TextButton(
                  onPressed: _isLoading ? null : _guardarCambios,
                  child: const Text('Guardar', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                ),
              IconButton(
                icon: const Icon(Icons.print_rounded, size: 22),
                tooltip: 'Imprimir muestra',
                onPressed: _abrirHojaMuestra,
              ),
              if ((widget.producto['codigo'] ?? '').toString().isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.qr_code_rounded, size: 22),
                  tooltip: widget.producto['codigo'],
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(widget.producto['codigo'].toString()),
                        duration: const Duration(seconds: 3),
                      ),
                    );
                  },
                ),
            ],
            bottom: const TabBar(
              indicatorColor: Colors.white,
              indicatorWeight: 3,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white54,
              labelStyle: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
              tabs: [
                Tab(text: 'Presentaciones'),
                Tab(text: 'Lotes'),
                Tab(text: 'Tuestes'),
              ],
            ),
          ),
          body: Column(
            children: [
              _buildProductHeader(),
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : TabBarView(
                        children: [
                          _buildPresentacionesTab(),
                          _buildLotesTab(),
                          _buildTuestesTab(),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Tab: product header strip (image + inventory summary) ───────────────────
  Widget _buildProductHeader() {
    final roastedTotal = _roastedKg;
    final greenTotal = _greenKg ?? 0.0;

    return Container(
        color: const Color(0xFF2d2720),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
        child: Row(
          children: [
            // Product image thumbnail (simple — no text overlays)
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: 68,
                height: 68,
                child: _nuevaFoto != null
                    ? Image.file(_nuevaFoto!, fit: BoxFit.cover)
                    : (_imagenUrlExistente != null && _imagenUrlExistente!.isNotEmpty)
                        ? Image.network(
                            _imagenUrlExistente!,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              color: Colors.grey.shade300,
                              child: Icon(Icons.image_not_supported_outlined,
                                  color: Colors.grey.shade500, size: 28),
                            ),
                          )
                        : Container(
                            color: Colors.grey.shade700,
                            child: Icon(Icons.add_a_photo_outlined,
                                color: Colors.grey.shade400, size: 28),
                          ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.producto['descripcion']?.toString().isNotEmpty == true
                        ? widget.producto['descripcion']
                        : 'Sin descripción',
                    style: const TextStyle(fontSize: 12, color: Colors.white54),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  Row(children: [
                    _inventoryChip(Icons.eco_outlined, 'Verde', _fmtKg(greenTotal), Colors.green.shade400),
                    const SizedBox(width: 8),
                    _inventoryChip(Icons.local_fire_department_outlined, 'Tostado', _fmtKg(roastedTotal), Colors.orange.shade400),
                  ]),
                ],
              ),
            ),
          ],
        ),
    );
  }

  Widget _inventoryChip(IconData icon, String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 4),
        Text(value, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w700)),
      ]),
    );
  }

  // ── Tab: Lotes ─────────────────────────────────────────────────────────────
  Widget _buildLotesTab() {
    if (_loadingPresentaciones) {
      return const Center(child: CircularProgressIndicator());
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Green lot card
        _buildGreenLotCard(),
        const SizedBox(height: 12),
        // Completed (roasted) lots card
        _buildRoastedLotsCard(),
        const SizedBox(height: 32),
      ],
    );
  }

  Widget _buildGreenLotCard() {
    final greenTotal = _greenKg ?? 0.0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.green.shade200),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(color: Colors.green.shade50, shape: BoxShape.circle),
            child: Icon(Icons.eco_outlined, size: 16, color: Colors.green.shade700),
          ),
          const SizedBox(width: 10),
          Text('Café verde disponible',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.green.shade800)),
          const Spacer(),
          Text(_fmtKg(greenTotal),
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: greenTotal > 0 ? Colors.green.shade700 : Colors.grey.shade400,
              )),
        ]),
        if (_isGreenCoffee && _greenKg != null) ...[
          const SizedBox(height: 8),
          Divider(height: 1, color: Colors.green.shade100),
          const SizedBox(height: 8),
          Row(children: [
            Container(width: 5, height: 5,
                decoration: BoxDecoration(color: Colors.green.shade400, shape: BoxShape.circle)),
            const SizedBox(width: 8),
            if (_greenLotCode != null && _greenLotCode!.isNotEmpty)
              Text(_greenLotCode!,
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
            const SizedBox(width: 6),
            Text('Lote verde vinculado',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
            const Spacer(),
            Text(_fmtKg(greenTotal),
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.green.shade600)),
          ]),
        ] else ...[
          const SizedBox(height: 8),
          Text('Sin lote verde vinculado',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade400)),
        ],
      ]),
    );
  }

  Widget _buildRoastedLotsCard() {
    final roastedTotal = _roastedKg;
    final lotsWithKg = _completedLots.where((l) => l.kg > 0).toList();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.shade200),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(color: Colors.orange.shade50, shape: BoxShape.circle),
            child: Icon(Icons.local_fire_department_outlined, size: 16, color: Colors.orange.shade700),
          ),
          const SizedBox(width: 10),
          Text('Café tostado disponible',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.orange.shade800)),
          const Spacer(),
          Text(_fmtKg(roastedTotal),
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: roastedTotal > 0 ? Colors.orange.shade700 : Colors.grey.shade400,
              )),
        ]),
        if (lotsWithKg.isNotEmpty) ...[
          const SizedBox(height: 8),
          Divider(height: 1, color: Colors.orange.shade100),
          const SizedBox(height: 6),
          ...lotsWithKg.map((lote) => Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Row(children: [
              Container(width: 5, height: 5,
                  decoration: BoxDecoration(color: Colors.orange.shade300, shape: BoxShape.circle)),
              const SizedBox(width: 8),
              if (lote.lotCode != null && lote.lotCode!.isNotEmpty)
                Text(lote.lotCode!,
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
              if (lote.roastedAt != null) ...[
                Text('  ·  ', style: TextStyle(fontSize: 11, color: Colors.grey.shade300)),
                Text(_fmtDate(lote.roastedAt),
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
              ],
              const Spacer(),
              Text(_fmtKg(lote.kg),
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.orange.shade600)),
            ]),
          )),
        ] else ...[
          const SizedBox(height: 8),
          Text('Sin lotes tostados disponibles',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade400)),
        ],
      ]),
    );
  }

  // ── Tab: Tuestes ───────────────────────────────────────────────────────────
  Widget _buildTuestesTab() {
    if (_loadingPresentaciones) {
      return const Center(child: CircularProgressIndicator());
    }

    final inProgressEvents = _upcomingEvents.where((e) => e.status == 'in_progress').toList();
    final plannedEvents    = _upcomingEvents.where((e) => e.status == 'planned').toList();

    // Active roast view when there is an in-progress event
    if (inProgressEvents.isNotEmpty) {
      final ev = inProgressEvents.first;
      return _buildActiveRoastView(ev, plannedEvents);
    }

    // Default: planned events list + create button
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (plannedEvents.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 40),
                  child: Column(children: [
                    Icon(Icons.local_fire_department_outlined, size: 52, color: Colors.grey.shade300),
                    const SizedBox(height: 12),
                    Text('Sin tuestes programados', style: TextStyle(fontSize: 14, color: Colors.grey.shade500)),
                    const SizedBox(height: 4),
                    Text('Usa el botón de abajo para programar uno',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade400), textAlign: TextAlign.center),
                  ]),
                )
              else ...[
                _sectionLabel('Planificados', Icons.schedule_rounded, Colors.deepPurple.shade600),
                const SizedBox(height: 8),
                ...plannedEvents.map(_buildEventoTuesteCard),
              ],
            ],
          ),
        ),
        // Sticky bottom CTA
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
          child: SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton.icon(
              onPressed: _mostrarCrearEvento,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Programar tueste', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange.shade600,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildActiveRoastView(ProximoEvento ev, List<ProximoEvento> planned) {
    final startDate = ev.date != null ? DateTime.tryParse(ev.date!) : null;

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // ── EN CURSO card ──────────────────────────────────────
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.orange.shade300, width: 1.5),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Icon(Icons.local_fire_department, color: Colors.orange.shade700, size: 20),
                    const SizedBox(width: 8),
                    Text('EN CURSO',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800,
                            color: Colors.orange.shade800, letterSpacing: 1)),
                    const Spacer(),
                    if (ev.lotCode != null && ev.lotCode!.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade100,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(ev.lotCode!,
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                                color: Colors.orange.shade800)),
                      ),
                  ]),
                  const SizedBox(height: 10),
                  Row(children: [
                    Icon(Icons.eco_outlined, size: 15, color: Colors.green.shade600),
                    const SizedBox(width: 4),
                    Text('${_fmtKg(ev.kg)} verde',
                        style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Icon(Icons.arrow_forward_rounded, size: 14, color: Colors.grey.shade400),
                    ),
                    Icon(Icons.local_fire_department_outlined, size: 15, color: Colors.orange.shade600),
                    const SizedBox(width: 4),
                    Text('tostado', style: TextStyle(fontSize: 13, color: Colors.orange.shade700,
                        fontWeight: FontWeight.w600)),
                  ]),
                ]),
              ),

              const SizedBox(height: 12),

              // ── Timer card ─────────────────────────────────────────
              Container(
                padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Column(children: [
                  Text('TIEMPO DE TUESTE',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                          color: Colors.grey.shade400, letterSpacing: 1.5)),
                  const SizedBox(height: 12),
                  if (startDate != null)
                    _RoastTimerDisplay(startDate: startDate)
                  else
                    Text('—', style: TextStyle(fontSize: 48, color: Colors.grey.shade300,
                        fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  if (startDate != null)
                    Text(
                      'Iniciado ${startDate.toLocal().hour.toString().padLeft(2, '0')}:${startDate.toLocal().minute.toString().padLeft(2, '0')} del ${startDate.toLocal().day} ${['ene','feb','mar','abr','may','jun','jul','ago','sep','oct','nov','dic'][startDate.toLocal().month - 1]}',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                    ),
                ]),
              ),

              const SizedBox(height: 20),

              // ── Evidencia del tueste ───────────────────────────────
              Text('EVIDENCIA DEL TUESTE',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                      color: Colors.grey.shade500, letterSpacing: 1.2)),
              const SizedBox(height: 10),

              // Existing media grid
              if (ev.mediaUrls.isNotEmpty) ...[
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3, crossAxisSpacing: 6, mainAxisSpacing: 6,
                  ),
                  itemCount: ev.mediaUrls.length,
                  itemBuilder: (_, i) {
                    final url = ev.mediaUrls[i];
                    final isVideo = url.contains('.mp4') || url.contains('.mov');
                    return GestureDetector(
                      onLongPress: () async {
                        final del = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('¿Eliminar archivo?'),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
                              TextButton(onPressed: () => Navigator.pop(ctx, true),
                                  style: TextButton.styleFrom(foregroundColor: Colors.red),
                                  child: const Text('Eliminar')),
                            ],
                          ),
                        );
                        if (del == true) _deleteEventMedia(ev.eventId!, url);
                      },
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: isVideo
                            ? Container(
                                color: Colors.orange.shade100,
                                child: Icon(Icons.play_circle_fill_rounded,
                                    color: Colors.orange.shade600, size: 36))
                            : Image.network(url, fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Container(
                                  color: Colors.grey.shade200,
                                  child: Icon(Icons.broken_image, color: Colors.grey.shade400),
                                )),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 10),
              ],

              // Add media button
              if (ev.eventId != null)
                GestureDetector(
                  onTap: () => _showMediaPickerSheet(ev.eventId!),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Row(children: [
                      Container(
                        width: 44, height: 44,
                        decoration: BoxDecoration(
                          color: Colors.orange.shade50,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: _uploadingEvents.contains(ev.eventId)
                            ? Padding(
                                padding: const EdgeInsets.all(10),
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.orange.shade600))
                            : Icon(Icons.add_a_photo_rounded, color: Colors.orange.shade600, size: 22),
                      ),
                      const SizedBox(width: 14),
                      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(
                          _uploadingEvents.contains(ev.eventId) ? 'Subiendo...' : 'Agregar foto o video',
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                        ),
                        Text('Camara o galeria',
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                      ]),
                    ]),
                  ),
                ),

              const SizedBox(height: 20),

              // Other planned events (collapsed)
              if (planned.isNotEmpty) ...[
                _sectionLabel('Planificados', Icons.schedule_rounded, Colors.deepPurple.shade600),
                const SizedBox(height: 8),
                ...planned.map(_buildEventoTuesteCard),
              ],

              const SizedBox(height: 8),
            ],
          ),
        ),

        // ── Sticky bottom: Finalizar Tueste ────────────────────────
        if (ev.eventId != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
            child: SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton.icon(
                onPressed: () => _mostrarFinalizarTueste(ev.eventId!, ev.kg),
                icon: const Icon(Icons.check_rounded, size: 22),
                label: const Text('Finalizar Tueste',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green.shade600,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _sectionLabel(String text, IconData icon, Color color) {
    return Row(children: [
      Icon(icon, size: 14, color: color),
      const SizedBox(width: 6),
      Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color, letterSpacing: 0.4)),
    ]);
  }

  // ── Tab: Presentaciones ────────────────────────────────────────────────────
  Widget _buildPresentacionesTab() {
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      behavior: HitTestBehavior.translucent,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Sección "Presentaciones": encabezado, ajustes (stock manual, lote verde, moneda) y la lista
          FincasCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Presentaciones', style: FincasText.sectionTitle),
                          Text('Variantes con su precio, stock y B2B', style: FincasText.metadata),
                        ],
                      ),
                    ),
                    if (_loadingPresentaciones)
                      const Padding(
                        padding: EdgeInsets.all(FincasSpacing.m),
                        child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5)),
                      )
                    else
                      IconButton(tooltip: 'Actualizar presentaciones', onPressed: _cargarPresentaciones, icon: const Icon(Icons.refresh_rounded)),
                  ],
                ),
                const Divider(),
                const SizedBox(height: FincasSpacing.s),
                ProductoPresentacionesAjustes(
                  productId: widget.producto['codigo']?.toString() ?? '',
                  onAjustes: (a) {
                    if (mounted && (a.stockManual != _stockManual || a.simboloMoneda != _simboloMoneda)) {
                      setState(() { _stockManual = a.stockManual; _simboloMoneda = a.simboloMoneda; });
                    }
                  },
                  onDirtyChanged: (sucio) {
                    if (mounted && _ajustesDirty != sucio) setState(() => _ajustesDirty = sucio);
                  },
                ),
                if (_loadingPresentaciones)
                  const Padding(padding: EdgeInsets.all(FincasSpacing.l), child: Center(child: FincasLoader(message: 'Cargando presentaciones...')))
                else if (_presentaciones.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: FincasSpacing.m),
                    child: FincasMessageState(
                      title: 'Sin presentaciones',
                      message: 'Agrega una para que el producto aparezca con precio.',
                    ),
                  )
                else
                  ..._presentaciones.map((p) => PresentacionTile(
                        presentacion: p,
                        simboloMoneda: _simboloMoneda,
                        stockManual: _stockManual,
                        onEditar: () => _mostrarFormPresentacion(presentacion: p),
                        onEliminar: () => _eliminarPresentacion(p),
                      )),
                const SizedBox(height: FincasSpacing.s),
                FincasSecondaryButton(label: 'Agregar presentación', onPressed: _mostrarFormPresentacion),
              ],
            ),
          ),

          const SizedBox(height: FincasSpacing.l),

          // Información general: nombre, descripciones, categoría y atributos del café
          ProductoInfoGeneral(
            productId: widget.producto['codigo']?.toString() ?? '',
            onDirtyChanged: (sucio) {
              if (mounted && _infoDirty != sucio) setState(() => _infoDirty = sucio);
            },
            onGuardado: _infoGuardada,
          ),
          const SizedBox(height: 32),
        ],
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
        // El mapa del producto no trae green_lot_id; el código de lote sí
        // llega fresco desde el endpoint de presentaciones.
        defaultLoteId: widget.producto['green_lot_id'] as String?,
        defaultLoteCode: _greenLotCode,
        onCreado: () {
          if (mounted) _cargarPresentaciones();
        },
      ),
    );
  }

  // ── Evento tueste card con acciones ─────────────────────────────────────────
  Widget _buildEventoTuesteCard(ProximoEvento ev) {
    final isInProgress = ev.status == 'in_progress';
    final color  = isInProgress ? Colors.orange : Colors.deepPurple;
    final icon   = isInProgress ? Icons.local_fire_department : Icons.schedule_rounded;
    final label  = isInProgress ? 'En tueste' : 'Planificado';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.shade200),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, size: 13, color: color.shade700),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              [
                if (ev.lotCode != null && ev.lotCode!.isNotEmpty) ev.lotCode!,
                if (ev.date != null) _fmtDate(ev.date),
                label,
              ].join(' · '),
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color.shade800),
            ),
          ),
          Text(_fmtKg(ev.kg),
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color.shade700)),
        ]),
        if (ev.eventId != null) ...[
          const SizedBox(height: 10),
          // Media gallery
          if (ev.mediaUrls.isNotEmpty) ...[
            SizedBox(
              height: 72,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: ev.mediaUrls.length,
                itemBuilder: (_, i) {
                  final url = ev.mediaUrls[i];
                  final isVideo = url.contains('.mp4') || url.contains('.mov');
                  return GestureDetector(
                    onLongPress: () async {
                      final del = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('¿Eliminar archivo?'),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
                            TextButton(onPressed: () => Navigator.pop(ctx, true),
                                style: TextButton.styleFrom(foregroundColor: Colors.red),
                                child: const Text('Eliminar')),
                          ],
                        ),
                      );
                      if (del == true) _deleteEventMedia(ev.eventId!, url);
                    },
                    child: Container(
                      width: 72, height: 72,
                      margin: const EdgeInsets.only(right: 6),
                      decoration: BoxDecoration(
                        color: color.shade100,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: color.shade200),
                      ),
                      child: isVideo
                          ? Icon(Icons.play_circle_outline, color: color.shade600, size: 32)
                          : ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.network(url, fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => Icon(Icons.broken_image, color: color.shade400)),
                            ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
          ],
          // Add media button
          GestureDetector(
            onTap: () => _showMediaPickerSheet(ev.eventId!),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
              decoration: BoxDecoration(
                color: color.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: color.shade200),
              ),
              child: Row(children: [
                _uploadingEvents.contains(ev.eventId)
                    ? SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: color.shade600))
                    : Icon(Icons.add_a_photo_rounded, size: 14, color: color.shade600),
                const SizedBox(width: 6),
                Text(
                  _uploadingEvents.contains(ev.eventId) ? 'Subiendo...' : 'Agregar foto / video  ${ev.mediaUrls.isNotEmpty ? "(${ev.mediaUrls.length})" : ""}',
                  style: TextStyle(fontSize: 11, color: color.shade700, fontWeight: FontWeight.w600),
                ),
              ]),
            ),
          ),
          const SizedBox(height: 8),
          if (isInProgress)
            _btnTueste(
              label: 'Finalizar tueste',
              icon: Icons.check_circle_outline_rounded,
              color: Colors.green,
              onTap: () => _mostrarFinalizarTueste(ev.eventId!, ev.kg),
            )
          else if (ApiService.isTostador)
            _btnTueste(
              label: 'Iniciar tueste',
              icon: Icons.play_circle_outline_rounded,
              color: Colors.deepPurple,
              onTap: () => _iniciarTueste(ev.eventId!),
            ),
        ],
      ]),
    );
  }

  Widget _btnTueste({required String label, required IconData icon, required MaterialColor color, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 7),
        decoration: BoxDecoration(
          color: color.shade600,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, size: 15, color: Colors.white),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white)),
        ]),
      ),
    );
  }

  Future<void> _pickAndUploadMedia(String eventId, {bool video = false}) async {
    XFile? file;
    try {
      if (video) {
        // No maxDuration — avoids "Failed to find a valid fallback video configuration"
        // on triple-lens iPhones when a duration constraint forces an unsupported mode.
        file = await _picker.pickVideo(source: ImageSource.camera);
      } else {
        file = await _picker.pickImage(source: ImageSource.camera, imageQuality: 80);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No se pudo abrir la cámara: ${e.toString().split('\n').first}'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }
    if (file == null || !mounted) return;

    setState(() => _uploadingEvents.add(eventId));
    try {
      final url = await ApiService.uploadEventMedia(eventId, File(file.path));
      if (url != null && mounted) {
        setState(() {
          _upcomingEvents = _upcomingEvents.map((ev) {
            if (ev.eventId != eventId) return ev;
            return ProximoEvento(
              kg: ev.kg, date: ev.date, status: ev.status,
              lotCode: ev.lotCode, eventId: ev.eventId,
              mediaUrls: [...ev.mediaUrls, url],
            );
          }).toList();
        });
      }
    } finally {
      if (mounted) setState(() => _uploadingEvents.remove(eventId));
    }
  }

  Future<void> _pickFromGallery(String eventId, {bool video = false}) async {
    XFile? file;
    try {
      file = video
          ? await _picker.pickVideo(source: ImageSource.gallery)
          : await _picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No se pudo abrir la galería: ${e.toString().split('\n').first}'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }
    if (file == null || !mounted) return;

    setState(() => _uploadingEvents.add(eventId));
    try {
      final url = await ApiService.uploadEventMedia(eventId, File(file.path));
      if (url != null && mounted) {
        setState(() {
          _upcomingEvents = _upcomingEvents.map((ev) {
            if (ev.eventId != eventId) return ev;
            return ProximoEvento(
              kg: ev.kg, date: ev.date, status: ev.status,
              lotCode: ev.lotCode, eventId: ev.eventId,
              mediaUrls: [...ev.mediaUrls, url],
            );
          }).toList();
        });
      }
    } finally {
      if (mounted) setState(() => _uploadingEvents.remove(eventId));
    }
  }

  Future<void> _deleteEventMedia(String eventId, String url) async {
    final newUrls = await ApiService.deleteEventMedia(eventId, url);
    if (newUrls != null && mounted) {
      setState(() {
        _upcomingEvents = _upcomingEvents.map((ev) {
          if (ev.eventId != eventId) return ev;
          return ProximoEvento(
            kg: ev.kg, date: ev.date, status: ev.status,
            lotCode: ev.lotCode, eventId: ev.eventId,
            mediaUrls: newUrls,
          );
        }).toList();
      });
    }
  }

  void _showMediaPickerSheet(String eventId) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(margin: const EdgeInsets.symmetric(vertical: 10), width: 36, height: 4,
                decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
            ListTile(leading: const Icon(Icons.photo_camera_rounded), title: const Text('Tomar foto'),
                onTap: () { Navigator.pop(ctx); _pickAndUploadMedia(eventId); }),
            ListTile(leading: const Icon(Icons.videocam_rounded), title: const Text('Grabar video'),
                onTap: () { Navigator.pop(ctx); _pickAndUploadMedia(eventId, video: true); }),
            ListTile(leading: const Icon(Icons.photo_library_rounded), title: const Text('Galería de fotos'),
                onTap: () { Navigator.pop(ctx); _pickFromGallery(eventId); }),
            ListTile(leading: const Icon(Icons.video_library_rounded), title: const Text('Galería de videos'),
                onTap: () { Navigator.pop(ctx); _pickFromGallery(eventId, video: true); }),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _iniciarTueste(String eventId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Iniciar tueste?'),
        content: const Text('Se marcará el evento como en curso. ¿Continuar?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Iniciar'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    final res = await ApiService.iniciarTueste(eventId);
    if (!mounted) return;
    if (res.isSuccess) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tueste iniciado'), backgroundColor: Colors.deepPurple),
      );
      _cargarPresentaciones();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(res.error ?? 'Error iniciando tueste'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _mostrarFinalizarTueste(String eventId, double inKg) async {
    final kgController = TextEditingController(text: inKg.toStringAsFixed(1));
    final notasController = TextEditingController();

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom, left: 20, right: 20, top: 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Row(children: [
            Icon(Icons.check_circle_outline, color: Colors.green),
            SizedBox(width: 10),
            Text('Finalizar tueste', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ]),
          const SizedBox(height: 16),
          Text('Kg de café tostado obtenido', style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
          const SizedBox(height: 6),
          TextField(
            controller: kgController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              suffixText: 'kg',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
          ),
          const SizedBox(height: 12),
          Text('Notas (opcional)', style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
          const SizedBox(height: 6),
          TextField(
            controller: notasController,
            maxLines: 2,
            decoration: InputDecoration(
              hintText: 'Observaciones del tueste...',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green.shade600,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () async {
                final outKg = double.tryParse(kgController.text.replaceAll(',', '.'));
                if (outKg == null || outKg <= 0) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text('Ingresa los kg obtenidos')),
                  );
                  return;
                }
                Navigator.pop(ctx);
                setState(() => _loadingPresentaciones = true);
                final result = await ApiService.finalizarTueste(eventId, outKg, notas: notasController.text.trim());
                if (!mounted) return;
                if (result.isSuccess) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('✅ Tueste finalizado'), backgroundColor: Colors.green),
                  );
                  await _cargarPresentaciones();
                } else {
                  setState(() => _loadingPresentaciones = false);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('❌ ${result.error}'), backgroundColor: Colors.red),
                  );
                }
              },
              child: const Text('Confirmar finalización', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
            ),
          ),
          const SizedBox(height: 20),
        ]),
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
            // Eventos planificados / en curso con acciones
            if (_upcomingEvents.isNotEmpty) ...[
              const SizedBox(height: 10),
              Divider(height: 1, color: Colors.orange.shade100),
              const SizedBox(height: 10),
              Row(children: [
                Icon(Icons.local_fire_department, size: 13, color: Colors.orange.shade700),
                const SizedBox(width: 6),
                Text('Tuestes programados',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.orange.shade800)),
              ]),
              const SizedBox(height: 8),
              ..._upcomingEvents.map((ev) => _buildEventoTuesteCard(ev)),
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
    final stockCtrl = TextEditingController(text: esEdicion ? presentacion.stock.toString() : '0');

    String unidad = esEdicion ? presentacion.unidad : 'g';
    bool predeterminada = esEdicion ? presentacion.predeterminada : false;
    bool visible = esEdicion ? presentacion.visible : true; // visible en tienda
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
          // Con stock manual el stock se escribe aquí; si no, lo calcula el sistema desde los tuestes.
          final stock = _stockManual ? (int.tryParse(stockCtrl.text.trim()) ?? 0) : (esEdicion ? presentacion.stock : 0);
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
              visible: visible,
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
              visible: visible,
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
                    DropdownMenuItem(value: 'ml', child: Text('ml')),
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

              // Stock (solo cuando el producto usa stock manual)
              if (_stockManual) ...[
                const Text('Stock', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(height: 6),
                TextField(
                  controller: stockCtrl,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    hintText: '0',
                    filled: true, fillColor: Colors.grey.shade50,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  ),
                ),
                const SizedBox(height: 16),
              ],

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
              SwitchListTile(
                value: visible,
                onChanged: (v) => ss(() => visible = v),
                title: const Text('Visible en tienda', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                subtitle: const Text('Si la apagas, esta presentación no aparece en la tienda', style: TextStyle(fontSize: 11)),
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


  // ── Impresión de etiqueta de muestra ────────────────────────────────────────

  /// Arma la ficha técnica desde el producto cargado.
  /// Los campos que el API todavía no envía quedan en null y su fila se omite.
  MuestraPrint _construirMuestra() {
    final p = widget.producto;

    String? txt(String clave) {
      final v = p[clave];
      if (v == null) return null;
      final s = v.toString().trim();
      return s.isEmpty ? null : s;
    }

    // sensory_notes llega como lista; se une por comas.
    // NO se cae a 'descripcion': ese campo es un párrafo largo y la etiqueta
    // es una ficha de datos, no un texto corrido.
    String? notas;
    final rawNotas = p['sensoryNotes'] ?? p['sensory_notes'];
    if (rawNotas is List && rawNotas.isNotEmpty) {
      notas = rawNotas.join(', ');
    }

    final altura = p['altitudeMasl'] ?? p['altitude_masl'];

    return MuestraPrint(
      nombre:     _nombreController.text.trim().isNotEmpty
                    ? _nombreController.text.trim()
                    : (txt('nombre') ?? 'Producto'),
      altura:     altura != null ? '$altura msnm' : null,
      variedad:   txt('variedad')  ?? txt('variety'),
      proceso:    txt('proceso')   ?? txt('process'),
      tostado:    txt('tostado')   ?? txt('roastLevel'),
      finca:      txt('finca')     ?? txt('farmName'),
      productor:  txt('productor') ?? txt('producerName'),
      tostador:   txt('tostador')  ?? txt('roasterName'),
      notas:      notas,
      puntajeSca: txt('scaScore')  ?? txt('sca_score'),
      whatsapp:   '51946259052',
      web:        'https://fincarosal.com/',
    );
  }

  void _abrirHojaMuestra() {
    int copias = 1;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final printer   = ctx.watch<PrinterProvider>();
          final conectada = printer.isConnected;
          final muestra   = _construirMuestra();

          // Campos que quedarían en blanco en la etiqueta.
          final faltantes = <String>[
            if (muestra.notas == null)      'notas sensoriales',
            if (muestra.proceso == null)    'proceso',
            if (muestra.puntajeSca == null) 'puntaje SCA',
          ];

          return Padding(
            padding: EdgeInsets.fromLTRB(
              20, 16, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40, height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text('Imprimir muestra',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(muestra.nombre,
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
                const SizedBox(height: 20),

                if (!conectada)
                  _avisoMuestra(
                    Icons.print_disabled_rounded,
                    'No hay impresora conectada',
                    'Conectala en Ajustes > Impresora',
                    Colors.red,
                  )
                else if (faltantes.isNotEmpty)
                  _avisoMuestra(
                    Icons.info_outline_rounded,
                    'La etiqueta saldra sin ${faltantes.join(", ")}',
                    'Esos campos estan vacios en este producto',
                    Colors.orange,
                  ),

                const SizedBox(height: 16),
                Row(
                  children: [
                    const Text('Cantidad de etiquetas',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline),
                      onPressed: copias > 1
                          ? () => setSheetState(() => copias--)
                          : null,
                    ),
                    Text('$copias',
                        style: const TextStyle(
                            fontSize: 17, fontWeight: FontWeight.w700)),
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline),
                      onPressed: copias < 20
                          ? () => setSheetState(() => copias++)
                          : null,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    icon: printer.isPrinting
                        ? const SizedBox(
                            width: 16, height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.print_rounded),
                    label: Text(printer.isPrinting ? 'Imprimiendo...' : 'Imprimir'),
                    onPressed: (!conectada || printer.isPrinting)
                        ? null
                        : () async {
                            final ok = await ctx
                                .read<PrinterProvider>()
                                .printMuestra(muestra, ApiService.businessName,
                                    copias: copias);
                            if (!ctx.mounted) return;
                            Navigator.pop(ctx);
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(ok
                                    ? '🏷️ $copias etiqueta(s) enviada(s)'
                                    : 'No se pudo imprimir'),
                                backgroundColor: ok ? Colors.green : Colors.red,
                              ),
                            );
                          },
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _avisoMuestra(IconData icono, String titulo, String detalle, MaterialColor color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.shade50,
        border: Border.all(color: color.shade200),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icono, size: 18, color: color.shade700),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(titulo,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: color.shade900)),
                Text(detalle,
                    style: TextStyle(fontSize: 11, color: color.shade800)),
              ],
            ),
          ),
        ],
      ),
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

// ── Live roast timer ─────────────────────────────────────────────────────────
class _RoastTimerDisplay extends StatefulWidget {
  final DateTime startDate;
  const _RoastTimerDisplay({required this.startDate});

  @override
  State<_RoastTimerDisplay> createState() => _RoastTimerDisplayState();
}

class _RoastTimerDisplayState extends State<_RoastTimerDisplay> {
  late Duration _elapsed;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _elapsed = DateTime.now().difference(widget.startDate);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _elapsed = DateTime.now().difference(widget.startDate));
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String get _timerStr {
    final h = _elapsed.inHours;
    final m = _elapsed.inMinutes % 60;
    final s = _elapsed.inSeconds % 60;
    if (h > 0) {
      return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      _timerStr,
      style: TextStyle(
        fontSize: 52,
        fontWeight: FontWeight.w800,
        color: Colors.orange.shade700,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }
}

// ── Bottom sheet: crear evento de tueste ──────────────────────────────────────
class _CrearEventoSheet extends StatefulWidget {
  final String productId;
  final String? defaultLoteId;
  final String? defaultLoteCode;
  final VoidCallback onCreado;

  const _CrearEventoSheet({
    required this.productId,
    this.defaultLoteId,
    this.defaultLoteCode,
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

  /// Id del lote asignado al producto, si está entre los disponibles.
  String? _loteProductoId;

  /// El producto tiene lote asignado pero no aparece entre los disponibles
  /// (agotado o archivado).
  bool _loteProductoNoDisponible = false;

  @override
  void initState() {
    super.initState();
    _loteId = null;
    _kgCtrl.addListener(() => setState(() {}));
    _cargarLotes();
  }

  Future<void> _cargarLotes() async {
    final res = await ApiService.getLotesVerdes();
    if (!mounted) return;
    final lotes = res.data ?? [];

    // Se busca el lote del producto por id o por código. Antes, sin esa
    // coincidencia, se preseleccionaba el lote más nuevo de la finca, que
    // podía ser el de otro café.
    Map<String, dynamic>? delProducto;
    for (final l in lotes) {
      final idOk = widget.defaultLoteId != null && l['id'] == widget.defaultLoteId;
      final codeOk = (widget.defaultLoteCode ?? '').isNotEmpty &&
          l['lot_code'] == widget.defaultLoteCode;
      if (idOk || codeOk) { delProducto = l; break; }
    }

    final tieneLoteAsignado = (widget.defaultLoteId ?? '').isNotEmpty ||
        (widget.defaultLoteCode ?? '').isNotEmpty;

    setState(() {
      _lotes = lotes;
      _loadingLotes = false;
      _loteProductoId = delProducto?['id'] as String?;
      _loteId = _loteProductoId;  // sin coincidencia → el usuario elige
      _loteProductoNoDisponible = tieneLoteAsignado && delProducto == null;
    });
  }

  Map<String, dynamic>? get _loteSel {
    for (final l in _lotes) {
      if (l['id'] == _loteId) return l;
    }
    return null;
  }

  double get _kgDisponibles =>
      double.tryParse('${_loteSel?['current_kg'] ?? ''}') ?? 0;

  double? get _kgIngresados => double.tryParse(_kgCtrl.text.trim());

  /// Hay kg escritos y superan lo que queda en el lote elegido.
  bool get _excedeLote =>
      _loteSel != null && (_kgIngresados ?? 0) > _kgDisponibles;

  @override
  void dispose() {
    _kgCtrl.dispose();
    _kgSalidaCtrl.dispose();
    super.dispose();
  }

  static String _fmtKgLote(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

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
    // Si no hay kg suficientes, el tueste falla después al finalizarlo
    // (el trigger no puede descontar del lote).
    if (kg > _kgDisponibles) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('El lote ${_loteSel?['lot_code'] ?? ''} solo tiene '
            '${_fmtKgLote(_kgDisponibles)} kg disponibles'),
        backgroundColor: Colors.red,
      ));
      return;
    }
    if (_loteProductoId != null && _loteId != _loteProductoId) {
      final seguir = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Lote distinto al del producto'),
          content: Text('Este producto usa el lote '
              '${widget.defaultLoteCode ?? ''}. Vas a tostar con '
              '${_loteSel?['lot_code'] ?? ''}. ¿Continuar?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar')),
            TextButton(onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Continuar')),
          ],
        ),
      );
      if (seguir != true || !mounted) return;
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
                    if (l['id'] == _loteProductoId) 'lote del producto',
                  ].join(' · ');
                  return DropdownMenuItem<String>(
                    value: l['id'] as String,
                    child: Text(label, style: const TextStyle(fontSize: 13)),
                  );
                }).toList(),
                onChanged: (v) => setState(() => _loteId = v),
              ),
            if (!_loadingLotes && _loteProductoNoDisponible)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'El lote del producto (${widget.defaultLoteCode ?? ''}) no '
                  'tiene stock disponible. Elige otro lote.',
                  style: TextStyle(fontSize: 12, color: Colors.red.shade700),
                ),
              )
            else if (!_loadingLotes && _loteProductoId == null && _lotes.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('Este producto no tiene lote asignado. Elige uno.',
                    style: TextStyle(fontSize: 12, color: Colors.orange.shade800)),
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
                helperText: _loteSel == null
                    ? null
                    : 'Disponible en ${_loteSel!['lot_code']}: '
                      '${_fmtKgLote(_kgDisponibles)} kg',
                errorText: _excedeLote
                    ? 'Supera lo disponible (${_fmtKgLote(_kgDisponibles)} kg)'
                    : null,
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
                onPressed: (_submitting || _excedeLote) ? null : _submit,
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
