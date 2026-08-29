import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart' show PdfPageFormat;
import 'package:printing/printing.dart' show PdfPreview, PdfPreviewAction, Printing;
import '../../../../../services/api_service.dart';
import '../../../../../services/printer_service.dart';
import '../../../../../providers/printer_provider.dart';
import '../../helpers/estado_pago_helper.dart';
import '../../helpers/producto_parser.dart';
import 'seccion_pago_widget.dart';
import 'seccion_atencion_widget.dart';
import 'header_pedido_widget.dart';
import 'info_basica_widget.dart';
import 'lista_productos_widget.dart';
import '../../../../../services/pedido_pdf_service.dart';
import '../../../../detalle_cliente_screen.dart';

/// Widget principal del detalle de un pedido
/// Muestra toda la información del pedido y permite actualizaciones
class DetallePedidoSheet extends StatefulWidget {
  final Map<String, dynamic> pedido;
  final VoidCallback onActualizado;
  final String? businessName;

  const DetallePedidoSheet({
    super.key,
    required this.pedido,
    required this.onActualizado,
    this.businessName,
  });

  @override
  State<DetallePedidoSheet> createState() => _DetallePedidoSheetState();
}

class _DetallePedidoSheetState extends State<DetallePedidoSheet> {
  bool _actualizando = false;
  bool _subiendoEvidencia = false;
  late List<Map<String, dynamic>> _evidencias;
  late List<Map<String, dynamic>> _pagos;
  late String _estadoPago;
  late double _montoPagado;
  int _tabIndex = 0; // 0=PEDIDO, 1=ENTREGA, 2=PAGO
  final ImagePicker _picker = ImagePicker();

  // Productos enriquecidos con presentaciones
  List<Map<String, dynamic>>? _productosEnriquecidos;

  // Delivery data
  Map<String, dynamic>? _delivery;
  bool _loadingDelivery = false;
  bool _deliveryLoaded  = false;

  @override
  void initState() {
    super.initState();
    // Deduplicar por URL para evitar duplicados visuales en la carga inicial
    final rawEv = (widget.pedido['evidencias'] as List? ?? []).cast<Map<String, dynamic>>();
    final seenUrls = <String>{};
    _evidencias = rawEv.where((e) => seenUrls.add(e['url']?.toString() ?? '')).toList();
    _estadoPago = EstadoPagoHelper.determinarEstadoPago(widget.pedido);
    _montoPagado = (widget.pedido['montoPagado'] ?? 0).toDouble();
    final rawPagos = widget.pedido['pagos'];
    _pagos = rawPagos is List
        ? List<Map<String, dynamic>>.from(rawPagos.map((p) => Map<String, dynamic>.from(p as Map)))
        : [];

    // Pre-seleccionar tab según estado del pedido
    final estado = (widget.pedido['estado'] ?? 'PENDIENTE').toString().toUpperCase();
    if (estado == 'CONFIRMADO' || estado == 'ENVIADO') {
      _tabIndex = 1; // ENTREGA
    } else if (estado == 'ENTREGADO' || estado == 'COMPLETADO') {
      _tabIndex = 2; // PAGO
    } else {
      _tabIndex = 0; // PEDIDO
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _enriquecerProductos();
      if (_tabIndex == 1) _loadDelivery();
    });
  }

  // ==================== ENRIQUECIMIENTO DE PRESENTACIONES ====================

  List<Map<String, dynamic>> _parseBase() {
    final rawDetalle = widget.pedido['productosDetalle'];
    return (rawDetalle is List && rawDetalle.isNotEmpty)
        ? parseProductos(rawDetalle)
        : parseProductos(widget.pedido['productos']);
  }

  Future<void> _enriquecerProductos() async {
    final base = _parseBase();
    if (base.isEmpty) return;

    final enriquecidos = base.map((p) => Map<String, dynamic>.from(p)).toList();

    // Recopilar los codigos que necesitan enriquecerse:
    // - siempre si tiene presentacionId (para obtener molienda aunque unit ya esté seteado)
    // - si unit está vacío o es 'unidad' (para obtener label y molienda)
    final codigosNecesarios = <String>{};
    for (final p in enriquecidos) {
      final presentacionId = (p['presentacionId'] ?? '').toString().trim();
      final unit = (p['unit'] ?? '').toString().trim();
      final needsEnrich = presentacionId.isNotEmpty || unit.isEmpty || unit == 'unidad';
      if (!needsEnrich) continue;
      final codigo = (p['codigo'] ?? p['id'] ?? '').toString().trim();
      if (codigo.isNotEmpty) codigosNecesarios.add(codigo);
    }

    if (codigosNecesarios.isEmpty) {
      if (mounted) setState(() => _productosEnriquecidos = enriquecidos);
      return;
    }

    // Cargar todas las presentaciones en paralelo
    final resultados = await Future.wait(
      codigosNecesarios.map((c) => ApiService.getPresentaciones(c)),
    );
    final presMap = <String, List<Presentacion>>{};
    int idx = 0;
    for (final codigo in codigosNecesarios) {
      final r = resultados[idx++];
      presMap[codigo] = (r.isSuccess ? r.data?.presentaciones : null) ?? [];
    }

    for (int i = 0; i < enriquecidos.length; i++) {
      final p = enriquecidos[i];
      final presentacionId = (p['presentacionId'] ?? '').toString().trim();
      final unit = (p['unit'] ?? '').toString().trim();
      final needsEnrich = presentacionId.isNotEmpty || unit.isEmpty || unit == 'unidad';
      if (!needsEnrich) continue;

      final codigo = (p['codigo'] ?? p['id'] ?? '').toString().trim();
      final presentaciones = presMap[codigo] ?? [];
      if (presentaciones.isEmpty) continue;

      Presentacion? match;

      // 1. Por ID directo
      if (presentacionId.isNotEmpty) {
        try { match = presentaciones.firstWhere((pr) => pr.id == presentacionId); } catch (_) {}
      }
      // 2. Por precio
      if (match == null) {
        final precio = (p['precio'] as num?)?.toDouble() ?? 0.0;
        if (precio > 0) {
          try { match = presentaciones.firstWhere((pr) => (pr.precio - precio).abs() < 0.02); } catch (_) {}
        }
      }
      // 3. Una sola presentación
      match ??= presentaciones.length == 1 ? presentaciones.first : null;

      if (match != null) {
        enriquecidos[i] = {
          ...p,
          if (unit.isEmpty || unit == 'unidad') 'unit': match.etiqueta,
          'molienda': match.molienda,
          if (match.imageUrl != null && match.imageUrl!.isNotEmpty)
            'imageUrl': match.imageUrl,
        };
      }
    }

    if (mounted) setState(() => _productosEnriquecidos = enriquecidos);
  }

  // ==================== DELIVERY ====================

  Future<void> _loadDelivery() async {
    if (_deliveryLoaded || _loadingDelivery) return;
    final pedidoId = widget.pedido['id']?.toString() ?? '';
    if (pedidoId.isEmpty) return;
    setState(() => _loadingDelivery = true);
    final result = await ApiService.getDelivery(pedidoId);
    if (mounted) {
      setState(() {
        _delivery       = result;
        _deliveryLoaded = true;
        _loadingDelivery = false;
      });
    }
  }

  // ==================== MÉTODOS DE ACTUALIZACIÓN ====================

  Future<void> _cambiarEstado(String nuevoEstado) async {
    final pedidoId = widget.pedido['id']?.toString() ?? '';
    if (pedidoId.isEmpty) return;

    setState(() => _actualizando = true);
    final result = await ApiService.actualizarPedido(pedidoId: pedidoId, estado: nuevoEstado);
    setState(() => _actualizando = false);

    if (result.isSuccess) {
      widget.onActualizado();
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Pedido actualizado a $nuevoEstado'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } else if (mounted) {
      _mostrarErrorAccion(result.error ?? 'Error actualizando pedido', code: result.code);
    }
  }

  /// Muestra un dialog prominente cuando una acción está bloqueada (código conocido)
  /// o un snackbar rojo para errores genéricos.
  void _mostrarErrorAccion(String mensaje, {String? code}) {
    // Códigos conocidos que merecen un dialog explicativo
    const codigosDialog = {'PREVENTA_STATUS_LOCKED', 'STOCK_INSUFICIENTE'};
    final icono = <String, IconData>{
      'PREVENTA_STATUS_LOCKED': Icons.lock_clock,
      'STOCK_INSUFICIENTE':     Icons.inventory_2_outlined,
    };
    final titulo = <String, String>{
      'PREVENTA_STATUS_LOCKED': 'Acción no permitida',
      'STOCK_INSUFICIENTE':     'Sin stock disponible',
    };

    if (code != null && codigosDialog.contains(code)) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: Icon(icono[code] ?? Icons.info_outline, color: Colors.orange, size: 36),
          title: Text(titulo[code] ?? 'No se puede realizar esta acción'),
          content: Text(mensaje, style: const TextStyle(fontSize: 14)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Entendido'),
            ),
          ],
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(mensaje),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  /// [esNuevoPago] = true → acumula el monto en el historial de pagos.
  /// [esNuevoPago] = false → reemplaza directamente (usado para revertir con monto:0).
  Future<void> _cambiarEstadoPago(
    String nuevoEstadoPago, {
    double? monto,
    bool? esNuevoPago,
  }) async {
    final pedidoId = widget.pedido['id']?.toString() ?? '';
    if (pedidoId.isEmpty) return;

    final bool acumular = esNuevoPago ?? true;

    setState(() => _actualizando = true);

    final result = await ApiService.actualizarEstadoPago(
      pedidoId: pedidoId,
      estadoPago: nuevoEstadoPago,
      nuevoPago: acumular ? monto : null,
      montoPagado: acumular ? null : monto,
    );

    setState(() => _actualizando = false);

    if (result.isSuccess) {
      final data = result.data;
      setState(() {
        _estadoPago = (data?['estadoPago'] as String?) ?? nuevoEstadoPago;
        _montoPagado = (data?['montoPagado'] as num?)?.toDouble()
            ?? (acumular ? _montoPagado + (monto ?? 0) : monto ?? 0);
        if (data?['pagos'] != null) {
          _pagos = (data!['pagos'] as List)
              .map((p) => Map<String, dynamic>.from(p as Map))
              .toList();
        } else if (acumular && monto != null && monto > 0) {
          _montoPagado += monto;
        } else if (!acumular && (monto ?? 0) == 0) {
          _pagos.clear();
        }
        if (data?['evidencias'] != null) {
          final rawEv = (data!['evidencias'] as List).cast<Map<String, dynamic>>();
          final seenUrls = <String>{};
          _evidencias = rawEv.where((e) => seenUrls.add(e['url']?.toString() ?? '')).toList();
        }
      });
      widget.onActualizado();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              nuevoEstadoPago == EstadoPagoHelper.PAGADO
                  ? '✅ Pago completado'
                  : acumular
                      ? '✅ Abono registrado: S/ ${monto?.toStringAsFixed(2)}'
                      : 'Estado de pago actualizado',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: ${result.error}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // ==================== ELIMINAR PAGO ====================

  Future<void> _eliminarPago(String pagoId) async {
    final pedidoId = widget.pedido['id']?.toString() ?? '';
    if (pedidoId.isEmpty) return;

    setState(() => _actualizando = true);
    final result = await ApiService.eliminarPago(pedidoId: pedidoId, pagoId: pagoId);
    setState(() => _actualizando = false);

    if (result.isSuccess && result.data != null) {
      final data = result.data!;
      setState(() {
        _estadoPago  = data['estadoPago']?.toString() ?? EstadoPagoHelper.PENDIENTE_PAGO;
        _montoPagado = (data['montoPagado'] as num?)?.toDouble() ?? 0.0;
        _pagos = (data['pagos'] as List? ?? [])
            .map((p) => Map<String, dynamic>.from(p as Map))
            .toList();
        _evidencias = (data['evidencias'] as List? ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      });
      widget.onActualizado();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Pago eliminado correctamente'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: ${result.error}'), backgroundColor: Colors.red),
      );
    }
  }

  // ==================== MÉTODOS DE EVIDENCIAS ====================

  Future<void> _agregarEvidencia(ImageSource source, {String? paymentId}) async {
    try {
      final XFile? imagen = await _picker.pickImage(
        source: source,
        maxWidth: 1200,
        maxHeight: 1200,
        imageQuality: 85,
      );

      if (imagen == null) return;

      setState(() => _subiendoEvidencia = true);

      final result = await ApiService.uploadImage(File(imagen.path));

      if (result.isSuccess && result.data != null) {
        final nuevaEvidencia = {
          'url': result.data,
          'tipo': 'APP',
          'fecha': DateTime.now().toIso8601String(),
          'descripcion': 'Comprobante agregado desde la app',
          if (paymentId != null) 'paymentId': paymentId,
        };

        final pedidoId = widget.pedido['id']?.toString() ?? '';
        final saveResult = await ApiService.agregarEvidenciaPago(
          pedidoId: pedidoId,
          evidencia: nuevaEvidencia,
          paymentId: paymentId,
        );

        if (saveResult.isSuccess && saveResult.data != null) {
          // Usar el objeto retornado por la API (tiene `id` para poder eliminarlo)
          final evidenciaGuardada = saveResult.data!;
          setState(() {
            final url = evidenciaGuardada['url']?.toString() ?? '';
            if (url.isEmpty || !_evidencias.any((e) => e['url'] == url)) {
              _evidencias.add(evidenciaGuardada);
            }
          });
          widget.onActualizado();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('✅ Comprobante agregado correctamente'),
                backgroundColor: Colors.green,
              ),
            );
          }
        } else {
          _mostrarError('Error guardando: ${saveResult.error}');
        }
      } else {
        _mostrarError('Error subiendo imagen: ${result.error}');
      }
    } catch (e) {
      _mostrarError('Error: $e');
    } finally {
      if (mounted) setState(() => _subiendoEvidencia = false);
    }
  }

  void _mostrarError(String mensaje) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(mensaje),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  Future<void> _eliminarEvidencia(Map<String, dynamic> ev) async {
    final evidenciaId = ev['id']?.toString() ?? '';
    final url         = ev['url']?.toString() ?? '';
    if (evidenciaId.isEmpty) {
      _mostrarError('No se puede eliminar: comprobante sin ID');
      return;
    }
    final pedidoId = widget.pedido['id']?.toString() ?? '';
    final result = await ApiService.eliminarEvidenciaPago(
      pedidoId: pedidoId,
      evidenciaId: evidenciaId,
    );
    if (result.isSuccess) {
      // Intentar borrar el archivo de Storage (best-effort)
      if (url.contains('/storage/v1/object/public/farm-assets/')) {
        final storagePath = url.split('/storage/v1/object/public/farm-assets/').last;
        final businessId  = ApiService.businessId;
        ApiService.eliminarArchivoStorage(businessId: businessId, storagePath: storagePath)
            .catchError((_) {});
      }
      setState(() => _evidencias.removeWhere((e) => e['id']?.toString() == evidenciaId));
      widget.onActualizado();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('🗑️ Comprobante eliminado'), backgroundColor: Colors.orange),
        );
      }
    } else {
      _mostrarError('Error eliminando: ${result.error}');
    }
  }

  // ==================== CAMBIO DE ESTADO ====================

  void _mostrarConfirmacionCancelar() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('⚠️ Cancelar Pedido'),
        content: const Text(
          '¿Estás seguro de que deseas cancelar este pedido?\n\n'
          'Esta acción no se puede deshacer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('No, volver'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _cambiarEstado('CANCELADO');
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Sí, cancelar'),
          ),
        ],
      ),
    );
  }

  // ==================== EDITAR PEDIDO ====================

  Future<void> _editarPedido() async {
    final ctrlDireccion = TextEditingController(
        text: widget.pedido['direccion']?.toString() ?? '');
    final ctrlObs = TextEditingController(
        text: widget.pedido['observaciones']?.toString() ?? '');

    final confirm = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
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
              const Text('Editar pedido',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              TextField(
                controller: ctrlDireccion,
                decoration: InputDecoration(
                  labelText: 'Dirección',
                  prefixIcon: const Icon(Icons.location_on_outlined),
                  filled: true,
                  fillColor: Colors.grey.shade50,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade300)),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade300)),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: ctrlObs,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: 'Observaciones',
                  prefixIcon: const Icon(Icons.notes_outlined),
                  filled: true,
                  fillColor: Colors.grey.shade50,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade300)),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade300)),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue.shade600,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Guardar cambios',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (confirm != true) return;

    final pedidoId = widget.pedido['id']?.toString() ?? '';
    final newDir = ctrlDireccion.text.trim();
    final newObs = ctrlObs.text.trim();

    setState(() => _actualizando = true);
    final result = await ApiService.actualizarPedido(
      pedidoId: pedidoId,
      direccion: newDir.isNotEmpty ? newDir : null,
      observaciones: newObs,
    );
    setState(() => _actualizando = false);

    if (result.isSuccess) {
      widget.onActualizado();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Pedido actualizado'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: ${result.error}'), backgroundColor: Colors.red),
      );
    }
  }

  // ==================== MENÚ DE OPCIONES ====================

  void _mostrarMenuOpciones() {
    final estado = (widget.pedido['estado'] ?? 'PENDIENTE').toString().toUpperCase();
    
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.75,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Título
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              child: Text(
                'Acciones del Pedido',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey.shade800,
                ),
              ),
            ),
            const Divider(),
            
            // Lista scrolleable de opciones
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Imprimir Ticket
                    _buildOpcionMenu(
              icon: Icons.print,
              titulo: 'Imprimir ticket',
              subtitulo: 'Impresión térmica',
              color: Colors.indigo,
              onTap: () {
                Navigator.pop(context);
                _imprimirTicket();
              },
            ),
            
            // Descargar PDF
            _buildOpcionMenu(
              icon: Icons.picture_as_pdf_outlined,
              titulo: 'Descargar PDF',
              subtitulo: 'Orden de pedido en PDF',
              color: const Color(0xFF5C3317),
              onTap: () {
                Navigator.pop(context);
                _descargarPdf();
              },
            ),
            
            // Separador entre impresión y cambios de estado
            if (!['ENTREGADO', 'COMPLETADO', 'CANCELADO'].contains(estado)) const Divider(),

            // Editar pedido (solo PENDIENTE)
            if (estado == 'PENDIENTE') ...[
              _buildOpcionMenu(
                icon: Icons.edit_outlined,
                titulo: 'Editar pedido',
                subtitulo: 'Modificar dirección u observaciones',
                color: Colors.blueGrey,
                onTap: () {
                  Navigator.pop(context);
                  _editarPedido();
                },
              ),
              const Divider(),
            ],

            // Avance de estado — un paso a la vez
            if (estado == 'PENDIENTE')
              _buildOpcionMenu(
                icon: Icons.check_circle_outline,
                titulo: 'Confirmar pedido',
                subtitulo: 'Pasar a estado Confirmado',
                color: Colors.blue,
                onTap: () { Navigator.pop(context); _cambiarEstado('CONFIRMADO'); },
              ),
            if (estado == 'CONFIRMADO')
              _buildOpcionMenu(
                icon: Icons.inventory_2_outlined,
                titulo: 'Iniciar preparación',
                subtitulo: 'Pasar a En Preparación',
                color: Colors.orange,
                onTap: () { Navigator.pop(context); _cambiarEstado('EN_PREPARACION'); },
              ),
            if (estado == 'EN_PREPARACION')
              _buildOpcionMenu(
                icon: Icons.local_shipping_outlined,
                titulo: 'Marcar como Enviado',
                subtitulo: 'Pedido en camino al cliente',
                color: Colors.purple,
                onTap: () { Navigator.pop(context); _cambiarEstado('ENVIADO'); },
              ),
            if (estado == 'ENVIADO')
              _buildOpcionMenu(
                icon: Icons.done_all,
                titulo: 'Marcar como Entregado',
                subtitulo: 'Cliente recibió el pedido',
                color: Colors.green,
                onTap: () { Navigator.pop(context); _cambiarEstado('ENTREGADO'); },
              ),

            // Cancelar pedido
            if (!['ENTREGADO', 'COMPLETADO', 'CANCELADO'].contains(estado)) ...[
              const Divider(),
              _buildOpcionMenu(
                icon: Icons.cancel_outlined,
                titulo: 'Cancelar pedido',
                subtitulo: 'Marcar como cancelado',
                color: Colors.red,
                onTap: () {
                  Navigator.pop(context);
                  _mostrarConfirmacionCancelar();
                },
              ),
            ],
                    
                    const SizedBox(height: 10),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOpcionMenu({
    required IconData icon,
    required String titulo,
    required String subtitulo,
    required Color color,
    required VoidCallback onTap,
    bool enabled = true,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: (enabled ? color : Colors.grey).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  color: enabled ? color : Colors.grey,
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titulo,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: enabled ? Colors.grey.shade800 : Colors.grey.shade400,
                      ),
                    ),
                    Text(
                      subtitulo,
                      style: TextStyle(
                        fontSize: 13,
                        color: enabled ? Colors.grey.shade600 : Colors.grey.shade400,
                      ),
                    ),
                  ],
                ),
              ),
              if (enabled)
                Icon(
                  Icons.arrow_forward_ios,
                  size: 16,
                  color: Colors.grey.shade400,
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ==================== PDF ====================

  Future<void> _descargarPdf() async {
    final productos  = _productosEnriquecidos ?? _parseBase();
    final pedidoId   = widget.pedido['id']?.toString() ?? 'pedido';
    final pedido     = widget.pedido;
    final bName      = widget.businessName;

    if (!mounted) return;

    // Mostrar loader mientras se genera
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _PdfLoadingDialog(),
    );

    try {
      final bytes = await PedidoPdfService.generarBytes(
        pedido: pedido,
        productos: productos,
        businessName: bName,
      );
      if (!mounted) return;
      Navigator.of(context).pop(); // cerrar loader
      Navigator.of(context).push(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => _PdfPreviewPage(
            title: 'Pedido #$pedidoId',
            bytes: bytes,
            filename: 'pedido_$pedidoId.pdf',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop(); // cerrar loader
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error generando PDF: $e')),
      );
    }
  }

  // ==================== IMPRESIÓN ====================

  Future<void> _imprimirTicket() async {
    final printerProvider = Provider.of<PrinterProvider>(context, listen: false);

    // Verificar si hay impresora conectada
    if (!printerProvider.isConnected) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('⚠️ No hay impresora conectada'),
            action: SnackBarAction(
              label: 'Configurar',
              onPressed: () {
                // Navegar a configuración de impresora
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Ve a Configuración > Impresora para conectar'),
                  ),
                );
              },
            ),
          ),
        );
      }
      return;
    }

    // Preparar datos del pedido
    try {
      final pedidoId = widget.pedido['id']?.toString() ?? 'SIN-ID';

      // El pedido mapeado tiene 'fecha' y 'hora' ya formateados.
      // Como fallback usamos tracking.creadoEn (ISO UTC) o DateTime.now().
      String fecha = widget.pedido['fecha']?.toString() ?? '';
      String hora  = widget.pedido['hora']?.toString()  ?? '';
      if (fecha.isEmpty || hora.isEmpty) {
        final rawDate = (widget.pedido['tracking'] as Map<String, dynamic>?)?['creadoEn']?.toString()
            ?? widget.pedido['fechaCreacion']?.toString();
        final dt = rawDate != null ? DateTime.tryParse(rawDate)?.toLocal() : null;
        if (dt != null) {
          fecha = DateFormat('dd/MM/yyyy').format(dt);
          hora  = DateFormat('HH:mm').format(dt);
        } else {
          final now = DateTime.now();
          fecha = DateFormat('dd/MM/yyyy').format(now);
          hora  = DateFormat('HH:mm').format(now);
        }
      }

      final cliente  = widget.pedido['cliente']?.toString()  ?? 'Sin nombre';
      final telefono = widget.pedido['whatsapp']?.toString()  ?? 'Sin teléfono';
      final direccion = widget.pedido['direccion']?.toString() ?? '';
      final total    = (widget.pedido['total'] ?? 0).toDouble();

      // Procesar productos — preferir productosDetalle (lista enriquecida)
      String productosStr;
      final detalle = widget.pedido['productosDetalle'];
      final productos = widget.pedido['productos'];
      if (detalle is List && detalle.isNotEmpty) {
        productosStr = jsonEncode(detalle);
      } else if (productos is List) {
        productosStr = jsonEncode(productos);
      } else if (productos is String) {
        productosStr = productos;
      } else {
        productosStr = '[]';
      }

      final pedidoPrint = PedidoPrint(
        id: pedidoId,
        fecha: fecha,
        hora: hora,
        cliente: cliente,
        telefono: telefono,
        direccion: direccion,
        productos: productosStr,
        total: total,
        departamento: widget.pedido['departamento']?.toString(),
        ciudad: widget.pedido['ciudad']?.toString(),
        businessWhatsapp: widget.businessName,
        businessId: ApiService.businessId,
      );

      // Mostrar indicador de carga
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                ),
                SizedBox(width: 12),
                Text('🖨️ Imprimiendo ticket...'),
              ],
            ),
            duration: Duration(seconds: 3),
          ),
        );
      }

      // Imprimir
      final resultado = await printerProvider.printPedido(
        pedidoPrint,
        widget.businessName ?? 'Fincas',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              resultado
                  ? '✅ Ticket impreso correctamente'
                  : '❌ Error al imprimir ticket',
            ),
            backgroundColor: resultado ? Colors.green : Colors.red,
          ),
        );
      }
    } catch (e) {
      print('[IMPRESIÓN] Error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // ==================== WHATSAPP ====================

  String _generarMensajeSugerido() {
    final cliente = widget.pedido['cliente'] ?? 'cliente';
    final pedidoId = widget.pedido['id'] ?? '';
    final estado = (widget.pedido['estado'] ?? 'PENDIENTE').toString().toUpperCase();
    final total = (widget.pedido['total'] ?? 0).toDouble();
    
    // Mensajes según el estado del pedido y pago
    if (estado == 'COMPLETADO') {
      if (_estadoPago == EstadoPagoHelper.PENDIENTE_PAGO) {
        final diasSinPago = EstadoPagoHelper.calcularDiasSinPago(widget.pedido);
        if (diasSinPago > 7) {
          return 'Hola $cliente! \n\n'
                 'Esperamos que hayas recibido tu pedido en buen estado. \n\n'
                 'Te recordamos que aún tienes un *pago pendiente* de S/ ${total.toStringAsFixed(2)}.\n\n'
                 'Gracias!';
        } else {
          return 'Hola $cliente! \n\n'
                 'Tu pedido ya fue entregado. ¿Todo llegó bien? n\n'
                 'Te recordamos que el pago pendiente es de S/ ${total.toStringAsFixed(2)}.\n\n'
                 'Gracias!';
        }
      } else if (_estadoPago == EstadoPagoHelper.PARCIAL) {
        final pendiente = total - _montoPagado;
        return 'Hola $cliente! \n\n'
               'Sobre tu pedido *$pedidoId*:\n\n'
               'Total: S/ ${total.toStringAsFixed(2)}\n'
               'Pagado: S/ ${_montoPagado.toStringAsFixed(2)}\n'
               'Pendiente: S/ ${pendiente.toStringAsFixed(2)}\n\n'
               '¿Cuándo podrías completar el pago? \n\n'
               'Gracias!';
      } else {
        return 'Hola $cliente! \n\n'
               '¡Gracias por tu compra! \n\n'
               'Tu pedido ya fue entregado y el pago está completo. \n\n'
               '¿Todo llegó en perfectas condiciones? Cuéntanos tu experiencia!';
      }
    } else if (estado == 'PENDIENTE') {
      return 'Hola $cliente!\n\n'
             'Hemos recibido tu pedido por un total de S/ ${total.toStringAsFixed(2)}.\n\n'
             'Te avisaremos cuando esté listo. ¡Gracias por tu preferencia!';
    } else if (estado == 'CONFIRMADO') {
      return 'Hola $cliente!\n\n'
             '✅ Tu pedido *$pedidoId* ha sido confirmado.\n\n'
             'Total: S/ ${total.toStringAsFixed(2)}\n\n'
             'En breve comenzamos la preparación. ¡Gracias!';
    } else if (estado == 'EN_PREPARACION') {
      return 'Hola $cliente!\n\n'
             '📦 Tu pedido *$pedidoId* está en preparación.\n\n'
             'Te avisaremos cuando esté listo para envío. ¡Gracias!';
    } else if (estado == 'ENVIADO') {
      return 'Hola $cliente!\n\n'
             '🚚 ¡Tu pedido *$pedidoId* ya está en camino!\n\n'
             'Total: S/ ${total.toStringAsFixed(2)}\n\n'
             'Pronto llegará a su destino. Cualquier consulta, estamos aquí. 😊';
    } else if (estado == 'ENTREGADO') {
      return 'Hola $cliente!\n\n'
             '✅ Tu pedido *$pedidoId* ha sido entregado.\n\n'
             'Total a pagar: S/ ${total.toStringAsFixed(2)}\n\n'
             '¿Todo llegó en perfectas condiciones? ¡Gracias por tu compra!';
    } else if (estado == 'CANCELADO') {
      return 'Hola $cliente! \n\n'
             'Lamentamos informarte que tu pedido fue cancelado.\n\n'
             '¿Hay algo en lo que podamos ayudarte? Estamos para servirte.';
    } else {
      return 'Hola $cliente! \n\n'
             'Sobre tu pedido *$pedidoId*:\n\n'
             'Total: S/ ${total.toStringAsFixed(2)}\n\n'
             '¿En qué podemos ayudarte?';
    }
  }

  Future<void> _abrirWhatsApp({String? mensaje}) async {
    final whatsapp = (widget.pedido['whatsapp'] ?? '').toString().replaceAll(RegExp(r'[^0-9]'), '');
    
    if (whatsapp.isEmpty) {
      _mostrarError('No hay número de WhatsApp');
      return;
    }

    final mensajeFinal = mensaje ?? _generarMensajeSugerido();
    final url = 'https://wa.me/$whatsapp?text=${Uri.encodeComponent(mensajeFinal)}';
    final uri = Uri.parse(url);
    
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      _mostrarError('No se pudo abrir WhatsApp');
    }
  }

  // ==================== BUILD ====================

  @override
  Widget build(BuildContext context) {
    final productos = _productosEnriquecidos ?? _parseBase();
    final estado = (widget.pedido['estado'] ?? 'PENDIENTE').toString().toUpperCase();
    final total = (widget.pedido['total'] ?? 0).toDouble();

    return Container(
      height: MediaQuery.of(context).size.height * 0.92,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Indicador de arrastre
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          
          // Header del pedido con botón de opciones
          HeaderPedidoWidget(
            pedido: widget.pedido,
            estadoPago: _estadoPago,
            onClose: () => Navigator.pop(context),
            onMenuTap: _mostrarMenuOpciones,
            onPdfTap: _descargarPdf,
            onClienteTap: () {
              final clienteId = widget.pedido['clienteId'];
              final clienteData = clienteId != null
                ? {'id': clienteId.toString()}
                : {
                    'id':                'guest',
                    'nombreResponsable': widget.pedido['cliente'] ?? '',
                    'whatsapp':          widget.pedido['whatsapp'] ?? '',
                    'telefono':          widget.pedido['whatsapp'] ?? '',
                    'email':             widget.pedido['email'] ?? '',
                    'direccionEnvio':    widget.pedido['direccion'] ?? '',
                    'distritoEnvio':     widget.pedido['ciudad'] ?? '',
                    'departamentoEnvio': widget.pedido['departamento'] ?? '',
                    'estado':            'INVITADO',
                    'notas':             'Cliente sin cuenta',
                  };
              Navigator.push(context, MaterialPageRoute(
                builder: (_) => DetalleClienteScreen(cliente: clienteData),
              ));
            },
          ),
          
          // Contenido scrolleable
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Información básica
                  InfoBasicaWidget(pedido: widget.pedido),

                  const SizedBox(height: 20),

                  // Lista de productos
                  ListaProductosWidget(
                    productos: productos,
                    editable: estado == 'PENDIENTE',
                    onEditTap: estado == 'PENDIENTE' ? _editarProducto : null,
                  ),

                  const SizedBox(height: 20),

                  // Resumen de costos
                  _buildResumenCostos(total),

                  // ── Tabs: PEDIDO / PAGO / ENTREGA ─────────────────
                  if (estado != 'CANCELADO') ...[
                    const SizedBox(height: 20),
                    _buildTabBar(),
                    const SizedBox(height: 16),
                    _buildTabContent(estado),
                  ],

                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Tab bar ────────────────────────────────────────────────

  Widget _buildTabBar() {
    final tabs = [
      (icon: Icons.inventory_2_outlined,    label: 'PEDIDO'),
      (icon: Icons.local_shipping_outlined, label: 'ENTREGA'),
      (icon: Icons.credit_card_outlined,    label: 'PAGO'),
    ];

    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: List.generate(tabs.length, (i) {
          final selected = _tabIndex == i;
          return Expanded(
            child: GestureDetector(
              onTap: () {
                setState(() => _tabIndex = i);
                if (i == 1) _loadDelivery();
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: selected ? Colors.white : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: selected
                      ? [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 6, offset: const Offset(0, 2))]
                      : [],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(tabs[i].icon,
                      size: 22,
                      color: selected ? Colors.deepOrange.shade600 : Colors.grey.shade400),
                    const SizedBox(height: 4),
                    Text(tabs[i].label,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                        color: selected ? Colors.deepOrange.shade600 : Colors.grey.shade400,
                      )),
                    if (selected)
                      Container(
                        margin: const EdgeInsets.only(top: 4),
                        height: 2,
                        width: 20,
                        decoration: BoxDecoration(
                          color: Colors.deepOrange.shade400,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildTabContent(String estado) {
    switch (_tabIndex) {
      case 0:
        // PEDIDO — Stock & production management
        return SeccionAtencionWidget(
          pedido: widget.pedido,
          onStockActualizado: widget.onActualizado,
        );

      case 1:
        // ENTREGA — Delivery info + QR tracking
        return _buildTabEntrega();

      case 2:
        // PAGO — Payment status + evidences + WhatsApp
        return Column(
          children: [
            SeccionPagoWidget(
              pedido: widget.pedido,
              estadoPago: _estadoPago,
              montoPagado: _montoPagado,
              pagos: _pagos,
              evidencias: _evidencias,
              actualizando: _actualizando,
              subiendoEvidencia: _subiendoEvidencia,
              onCambiarEstadoPago: _cambiarEstadoPago,
              onAgregarComprobante: _agregarEvidencia,
              onEliminarPago: _eliminarPago,
              onEliminarEvidencia: _eliminarEvidencia,
            ),
            if ((widget.pedido['whatsapp'] ?? '').toString().isNotEmpty) ...[
              const SizedBox(height: 16),
              _buildBotonWhatsApp(),
            ],
          ],
        );

      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildTabEntrega() {
    // ── Preferir datos de la hoja Delivery, fallback al pedido ──────────────
    final d = _delivery; // puede ser null si aún no cargó o no tiene registro

    final tipoEnvio    = (d?['tipoEnvio']        ?? widget.pedido['tipoEnvio']    ?? '').toString().toUpperCase();
    final empresaEnvio = (d?['empresaEnvio']      ?? widget.pedido['empresaEnvio'] ?? '').toString();
    final estadoDel    = (d?['estadoDelivery']    ?? '').toString();

    // Origen
    final origenNombre    = (d?['origenNombre']    ?? widget.businessName ?? ApiService.businessName).toString();
    final origenDireccion = (d?['origenDireccion'] ?? ApiService.businessDireccion).toString();
    final origenCiudad    = (d?['origenCiudad']    ?? ApiService.businessCiudad).toString();

    // Destino — para recojo en tienda (pickup) usar pickupName/pickupAddress
    final destinoNombre    = ([
      d?['destinoNombre'],
      widget.pedido['pickupName'],
      widget.pedido['cliente'],
    ].firstWhere((v) => v != null && v.toString().isNotEmpty, orElse: () => '') ?? '').toString();
    final destinoReferencia = (d?['referencia'] ?? widget.pedido['referencia'] ?? '').toString();
    // Use delivery record value only when non-empty, fallback to order's shipping address fields
    final destinoDireccion = ([
      d?['destinoDireccion'],
      widget.pedido['pickupAddress'],
      widget.pedido['direccion'],
    ].firstWhere((v) => v != null && v.toString().isNotEmpty, orElse: () => '') ?? '').toString();
    final destinoCiudad    = ([
      d?['destinoCiudad'],
      widget.pedido['pickupCiudad'],
      [widget.pedido['ciudad'] ?? '', widget.pedido['departamento'] ?? ''].where((e) => e.isNotEmpty).join(', '),
    ].firstWhere((v) => v != null && v.toString().isNotEmpty, orElse: () => '') ?? '').toString();

    final pedidoId = widget.pedido['id']?.toString() ?? '';
    final bizId    = widget.pedido['businessId']?.toString()
                   ?? widget.pedido['negocioId']?.toString()
                   ?? ApiService.businessId;
    final trackUrl = 'https://apartalo-core-9d633cdb9e1a.herokuapp.com/track/$bizId/$pedidoId';
    final hasTrack = pedidoId.isNotEmpty && bizId.isNotEmpty;

    // Cargando delivery por primera vez
    if (_loadingDelivery) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Column(
      children: [

        // ── Información de entrega ──
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header con tipo de envío y estado delivery
              Row(children: [
                Icon(Icons.local_shipping_outlined, size: 18, color: Colors.blue.shade600),
                const SizedBox(width: 8),
                Text('Información de entrega',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: Colors.blue.shade700)),
                const Spacer(),
                if (tipoEnvio.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: _colorTipoEnvio(tipoEnvio).withOpacity(0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(tipoEnvio,
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                          color: _colorTipoEnvio(tipoEnvio))),
                  ),
              ]),

              // Estado delivery
              if (estadoDel.isNotEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: _colorEstadoDelivery(estadoDel).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: _colorEstadoDelivery(estadoDel).withOpacity(0.3)),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(_iconEstadoDelivery(estadoDel), size: 12, color: _colorEstadoDelivery(estadoDel)),
                    const SizedBox(width: 5),
                    Text(estadoDel.replaceAll('_', ' '),
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                          color: _colorEstadoDelivery(estadoDel))),
                  ]),
                ),
              ],

              const SizedBox(height: 14),
              Divider(height: 1, color: Colors.grey.shade100),
              const SizedBox(height: 14),

              // ── ORIGEN (negocio) ──
              _routeBlock(
                icon: Icons.store_outlined,
                iconColor: Colors.blue.shade600,
                bgColor: Colors.blue.shade50,
                label: 'ORIGEN',
                name: origenNombre,
                addr: origenDireccion,
                city: origenCiudad,
              ),

              // Conector visual (solo para LOCAL y NACIONAL)
              if (tipoEnvio != 'SEDE') ...[
                Padding(
                  padding: const EdgeInsets.only(left: 19),
                  child: Container(width: 2, height: 20, color: Colors.grey.shade200),
                ),
              ],

              // ── DESTINO ──
              if (tipoEnvio == 'SEDE')
                _routeBlock(
                  icon: Icons.store_mall_directory_outlined,
                  iconColor: Colors.teal.shade600,
                  bgColor: Colors.teal.shade50,
                  label: 'PUNTO DE RECOJO',
                  name: destinoNombre.isNotEmpty ? destinoNombre : (destinoDireccion.isNotEmpty ? destinoDireccion : 'Sin dirección'),
                  addr: '',
                  city: destinoCiudad,
                )
              else if (tipoEnvio == 'NACIONAL')
                _routeBlock(
                  icon: Icons.local_shipping_outlined,
                  iconColor: Colors.purple.shade600,
                  bgColor: Colors.purple.shade50,
                  label: 'AGENCIA COURIER',
                  name: empresaEnvio.isNotEmpty ? empresaEnvio : (destinoNombre.isNotEmpty ? destinoNombre : 'Courier'),
                  addr: destinoDireccion,
                  city: destinoCiudad,
                )
              else
                _routeBlock(
                  icon: Icons.pin_drop_outlined,
                  iconColor: Colors.green.shade600,
                  bgColor: Colors.green.shade50,
                  label: 'DESTINO',
                  name: destinoNombre.isNotEmpty ? destinoNombre : (destinoDireccion.isNotEmpty ? destinoDireccion : 'Sin dirección'),
                  addr: destinoNombre.isNotEmpty ? destinoDireccion : '',
                  city: destinoCiudad,
                ),

              // ── Referencia del destino ──
              if (destinoReferencia.isNotEmpty) ...[
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline, size: 14, color: Colors.grey.shade500),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          destinoReferencia,
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

            ],
          ),
        ),

        // ── Seguimiento QR ──
        if (hasTrack) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Icon(Icons.qr_code_2_rounded, size: 18, color: Colors.grey.shade700),
                  const SizedBox(width: 8),
                  Text('Seguimiento del pedido',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: Colors.grey.shade800)),
                ]),
                const SizedBox(height: 4),
                Text('El cliente puede escanear este QR para ver el estado en tiempo real.',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                const SizedBox(height: 14),

                // QR + info lateral
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // QR code
                    Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: QrImageView(
                        data: trackUrl,
                        version: QrVersions.auto,
                        size: 110,
                        padding: const EdgeInsets.all(8),
                        backgroundColor: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 14),

                    // URL + botón abrir
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Link de seguimiento',
                            style: TextStyle(fontSize: 11, color: Colors.grey.shade500,
                                fontWeight: FontWeight.w600)),
                          const SizedBox(height: 4),
                          Text(trackUrl,
                            style: TextStyle(fontSize: 10, color: Colors.grey.shade600,
                                height: 1.4),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis),
                          const SizedBox(height: 10),
                          GestureDetector(
                            onTap: () async {
                              final uri = Uri.parse(trackUrl);
                              if (await canLaunchUrl(uri)) {
                                await launchUrl(uri, mode: LaunchMode.externalApplication);
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                              decoration: BoxDecoration(
                                color: Colors.blue.shade600,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.open_in_new, size: 14, color: Colors.white),
                                  const SizedBox(width: 6),
                                  const Text('Abrir página',
                                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
                                        color: Colors.white)),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],

      ],
    );
  }

  Future<void> _editarProducto(Map<String, dynamic> producto) async {
    final nombre = producto['nombre'] ?? '';
    int cantidad = (producto['cantidad'] as num?)?.toInt() ?? 1;
    final precio = (producto['precio'] as num?)?.toDouble() ?? 0.0;
    final grindActual = (producto['grind'] ?? '').toString();
    String? grindSeleccionado = grindActual.isNotEmpty ? grindActual : null;

    final moliendaRaw = producto['molienda'];
    final opcionesGrind = moliendaRaw is List
        ? moliendaRaw.map((e) => e.toString()).where((e) => e.isNotEmpty).toList()
        : <String>[];

    String _grindLabel(String g) => switch (g) {
          'ground' => 'Molido',
          'whole'  => 'Grano',
          'green'  => 'Verde',
          _        => g,
        };

    bool _saving = false;

    final confirmar = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Container(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Handle
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
                Text(nombre,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.bold),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
                Text('S/ ${precio.toStringAsFixed(2)} c/u',
                    style:
                        TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                const SizedBox(height: 20),

                // Cantidad
                Text('Cantidad',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade700)),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _stepBtn(
                      icon: Icons.remove,
                      onTap: cantidad > 1
                          ? () => setS(() => cantidad--)
                          : null,
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () async {
                        final ctrl = TextEditingController(text: '$cantidad');
                        final v = await showDialog<int>(
                          context: ctx,
                          builder: (d) => AlertDialog(
                            title: const Text('Cantidad',
                                style: TextStyle(fontSize: 14)),
                            content: TextField(
                              controller: ctrl,
                              autofocus: true,
                              keyboardType: TextInputType.number,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                  fontSize: 22, fontWeight: FontWeight.bold),
                              decoration: InputDecoration(
                                filled: true,
                                fillColor: Colors.grey.shade100,
                                border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: BorderSide.none),
                              ),
                              onSubmitted: (_) => Navigator.pop(
                                  d, int.tryParse(ctrl.text)),
                            ),
                            actions: [
                              TextButton(
                                  onPressed: () => Navigator.pop(d),
                                  child: const Text('Cancelar')),
                              ElevatedButton(
                                  onPressed: () => Navigator.pop(
                                      d, int.tryParse(ctrl.text)),
                                  child: const Text('OK')),
                            ],
                          ),
                        );
                        if (v != null && v > 0) setS(() => cantidad = v);
                      },
                      child: Container(
                        constraints: const BoxConstraints(minWidth: 56),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text('$cantidad',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: Colors.blue.shade700)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _stepBtn(
                      icon: Icons.add,
                      onTap: () => setS(() => cantidad++),
                    ),
                    const Spacer(),
                    Text(
                      'S/ ${(precio * cantidad).toStringAsFixed(2)}',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.green.shade700),
                    ),
                  ],
                ),

                // Grind (si hay opciones)
                if (opcionesGrind.length > 1) ...[
                  const SizedBox(height: 20),
                  Text('Tipo de proceso',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade700)),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    children: opcionesGrind.map((g) {
                      final sel = grindSeleccionado == g;
                      return GestureDetector(
                        onTap: () => setS(() => grindSeleccionado = g),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(
                            color: sel
                                ? Colors.brown.shade600
                                : Colors.brown.shade50,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: sel
                                  ? Colors.brown.shade600
                                  : Colors.brown.shade200,
                            ),
                          ),
                          child: Text(_grindLabel(g),
                              style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: sel
                                      ? Colors.white
                                      : Colors.brown.shade700)),
                        ),
                      );
                    }).toList(),
                  ),
                ],

                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _saving ? null : () => Navigator.pop(ctx, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue.shade700,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Guardar cambios',
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (confirmar != true) return;

    // Actualizar localmente y llamar API
    final pedidoId = widget.pedido['id']?.toString() ?? '';
    final presentacionId = (producto['presentacionId'] ?? '').toString();
    final codigo = (producto['codigo'] ?? producto['id'] ?? '').toString();

    final res = await ApiService.actualizarItemPedido(
      pedidoId: pedidoId,
      presentacionId: presentacionId.isNotEmpty ? presentacionId : null,
      codigo: codigo,
      cantidad: cantidad,
      grind: grindSeleccionado,
    );

    if (!mounted) return;

    if (res.isSuccess) {
      // Actualizar localmente
      setState(() {
        final idx = _productosEnriquecidos?.indexWhere(
          (p) => p == producto ||
              (p['presentacionId'] == producto['presentacionId'] &&
                  p['codigo'] == producto['codigo']),
        );
        if (idx != null && idx >= 0 && _productosEnriquecidos != null) {
          final nuevoPrecio = precio;
          _productosEnriquecidos![idx] = {
            ..._productosEnriquecidos![idx],
            'cantidad': cantidad,
            'subtotal': nuevoPrecio * cantidad,
            if (grindSeleccionado != null) 'grind': grindSeleccionado,
          };
          // Recalcular total del pedido localmente
          final nuevoSubtotal = _productosEnriquecidos!
              .fold(0.0, (s, p) => s + ((p['subtotal'] as num?)?.toDouble() ?? 0));
          final costoEnvio = (widget.pedido['costoEnvio'] ?? 0).toDouble();
          widget.pedido['total'] = nuevoSubtotal + costoEnvio;
        }
      });
      widget.onActualizado();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(res.error ?? 'Error actualizando producto'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Widget _stepBtn({required IconData icon, VoidCallback? onTap}) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: onTap != null ? Colors.blue.shade50 : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: onTap != null
                    ? Colors.blue.shade200
                    : Colors.grey.shade200),
          ),
          child: Icon(icon,
              size: 20,
              color: onTap != null
                  ? Colors.blue.shade700
                  : Colors.grey.shade400),
        ),
      );

  Widget _buildResumenCostos(double total) {
    final costoEnvio = (widget.pedido['costoEnvio'] ?? 0).toDouble();
    final subtotal = total - costoEnvio;
    return Column(
      children: [
        // Subtotal — línea discreta
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(children: [
            Text('Subtotal', style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
            const Spacer(),
            Text('S/ ${subtotal.toStringAsFixed(2)}',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
          ]),
        ),
        const SizedBox(height: 8),

        // Delivery — tarjeta tappable grande
        GestureDetector(
          onTap: _editarCostoDelivery,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.blue.shade100),
            ),
            child: Row(children: [
              Icon(Icons.local_shipping_outlined, size: 20, color: Colors.blue.shade600),
              const SizedBox(width: 10),
              Text('Delivery',
                  style: TextStyle(fontSize: 14, color: Colors.blue.shade700, fontWeight: FontWeight.w500)),
              const Spacer(),
              Text('S/ ${costoEnvio.toStringAsFixed(2)}',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: costoEnvio > 0 ? Colors.blue.shade700 : Colors.grey.shade400)),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.blue.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.edit_outlined, size: 16, color: Colors.blue.shade700),
              ),
            ]),
          ),
        ),
        const SizedBox(height: 12),

        // Total — caja azul grande (igual que antes)
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [Colors.blue.shade700, Colors.blue.shade900]),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(children: [
            const Text('Total',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
            const Spacer(),
            Text('S/ ${total.toStringAsFixed(2)}',
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white)),
          ]),
        ),
      ],
    );
  }

  Widget _buildCostoDeliveryRow() {
    final costoEnvio = (widget.pedido['costoEnvio'] ?? 0).toDouble();
    return Row(
      children: [
        Icon(Icons.local_shipping_outlined, size: 16, color: Colors.grey.shade500),
        const SizedBox(width: 8),
        Text('Costo de delivery',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade700, fontWeight: FontWeight.w500)),
        const Spacer(),
        Text(
          'S/ ${costoEnvio.toStringAsFixed(2)}',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold,
              color: costoEnvio > 0 ? Colors.blue.shade700 : Colors.grey.shade400),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: _editarCostoDelivery,
          child: Icon(Icons.edit_outlined, size: 16, color: Colors.blue.shade400),
        ),
      ],
    );
  }

  Future<void> _editarCostoDelivery() async {
    final costoActual = (widget.pedido['costoEnvio'] ?? 0).toDouble();
    final ctrl = TextEditingController(text: costoActual > 0 ? costoActual.toStringAsFixed(2) : '');
    final resultado = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(children: [
          Icon(Icons.local_shipping_outlined, color: Colors.blue.shade600),
          const SizedBox(width: 8),
          const Text('Costo de delivery', style: TextStyle(fontSize: 15)),
        ]),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          decoration: InputDecoration(
            prefixText: 'S/ ',
            hintText: '0.00',
            filled: true,
            fillColor: Colors.grey.shade100,
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
          ),
          onSubmitted: (_) => Navigator.pop(ctx, double.tryParse(ctrl.text) ?? 0),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, double.tryParse(ctrl.text) ?? 0),
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue.shade600, foregroundColor: Colors.white),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    if (resultado == null) return;
    final pedidoId = widget.pedido['id']?.toString() ?? '';
    final res = await ApiService.actualizarCostoEnvio(pedidoId: pedidoId, costoEnvio: resultado);
    if (!mounted) return;
    if (res.isSuccess) {
      setState(() {
        final oldCosto = (widget.pedido['costoEnvio'] ?? 0).toDouble();
        final oldTotal = (widget.pedido['total'] ?? 0).toDouble();
        widget.pedido['costoEnvio'] = resultado;
        widget.pedido['total'] = oldTotal - oldCosto + resultado;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Delivery actualizado: S/ ${resultado.toStringAsFixed(2)}'),
          backgroundColor: Colors.green.shade600,
          duration: const Duration(seconds: 2),
        ),
      );
      widget.onActualizado();
    } else {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(res.error ?? 'Error'), backgroundColor: Colors.red));
    }
  }

  Color _colorEstadoDelivery(String estado) {
    switch (estado.toUpperCase()) {
      case 'INACTIVO':    return Colors.grey.shade500;
      case 'DISPONIBLE':  return Colors.orange.shade600;
      case 'ASIGNADO':    return Colors.blue.shade600;
      case 'EN_CAMINO':   return Colors.indigo.shade600;
      case 'ENTREGADO':   return Colors.green.shade600;
      case 'CANCELADO':   return Colors.red.shade600;
      default:            return Colors.grey.shade500;
    }
  }

  IconData _iconEstadoDelivery(String estado) {
    switch (estado.toUpperCase()) {
      case 'INACTIVO':    return Icons.pause_circle_outline;
      case 'DISPONIBLE':  return Icons.check_circle_outline;
      case 'ASIGNADO':    return Icons.person_pin_circle_outlined;
      case 'EN_CAMINO':   return Icons.directions_bike_outlined;
      case 'ENTREGADO':   return Icons.done_all;
      case 'CANCELADO':   return Icons.cancel_outlined;
      default:            return Icons.help_outline;
    }
  }

  Color _colorTipoEnvio(String tipo) {
    switch (tipo) {
      case 'LOCAL':    return Colors.blue.shade600;
      case 'NACIONAL': return Colors.purple.shade600;
      case 'SEDE':     return Colors.teal.shade600;
      default:         return Colors.grey.shade600;
    }
  }

  IconData _iconTipoEnvio(String tipo) {
    switch (tipo) {
      case 'LOCAL':    return Icons.home_outlined;
      case 'NACIONAL': return Icons.local_shipping_outlined;
      case 'SEDE':     return Icons.store_mall_directory_outlined;
      default:         return Icons.help_outline;
    }
  }

  Widget _routeBlock({
    required IconData icon,
    required Color iconColor,
    required Color bgColor,
    required String label,
    required String name,
    required String addr,
    required String city,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 40, height: 40,
          decoration: BoxDecoration(color: bgColor, shape: BoxShape.circle),
          child: Icon(icon, size: 20, color: iconColor),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700,
                    color: Colors.grey.shade500, letterSpacing: .8)),
              const SizedBox(height: 2),
              Text(name,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF111111))),
              if (addr.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(addr,
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
              ],
              if (city.isNotEmpty) ...[
                const SizedBox(height: 1),
                Text(city,
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
              ],
              const SizedBox(height: 4),
            ],
          ),
        ),
      ],
    );
  }

  // NUEVO: Widget del botón de WhatsApp
  Widget _buildBotonWhatsApp() {
    final estado = (widget.pedido['estado'] ?? 'PENDIENTE').toString().toUpperCase();
    Color colorBoton = Colors.green;
    IconData iconoBoton = Icons.chat;
    String textoBoton = 'Enviar mensaje';
    
    // Personalizar según el estado
    if (estado == 'COMPLETADO' && _estadoPago != EstadoPagoHelper.PAGADO) {
      colorBoton = Colors.orange;
      iconoBoton = Icons.payment;
      textoBoton = 'Recordar pago';
      
      final diasSinPago = EstadoPagoHelper.calcularDiasSinPago(widget.pedido);
      if (diasSinPago > 7) {
        colorBoton = Colors.red;
        textoBoton = 'Recordar pago urgente';
      }
    } else if (estado == 'PENDIENTE') {
      colorBoton = Colors.blue;
      iconoBoton = Icons.check_circle;
      textoBoton = 'Confirmar pedido';
    } else if (estado == 'CONFIRMADO') {
      colorBoton = Colors.purple;
      iconoBoton = Icons.schedule;
      textoBoton = 'Actualizar estado';
    } else if (estado == 'ENVIADO') {
      colorBoton = Colors.teal;
      iconoBoton = Icons.local_shipping;
      textoBoton = 'Seguimiento envío';
    }
    
    return Material(
      color: colorBoton.withOpacity(0.1),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: () => _abrirWhatsApp(),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: colorBoton,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  iconoBoton,
                  color: Colors.white,
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      textoBoton,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: colorBoton.withOpacity(0.9),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'WhatsApp al cliente',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios,
                size: 16,
                color: colorBoton.withOpacity(0.6),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Dialog de carga mientras se genera el PDF ─────────────────────────────────
class _PdfLoadingDialog extends StatelessWidget {
  const _PdfLoadingDialog();

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.12), blurRadius: 20),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 48, height: 48,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF5C3317)),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Generando PDF...',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              'Esto solo tarda un momento',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Pantalla de previsualización del PDF ────────────────────────────────────
class _PdfPreviewPage extends StatefulWidget {
  final String title;
  final Uint8List bytes;
  final String filename;

  const _PdfPreviewPage({
    required this.title,
    required this.bytes,
    required this.filename,
  });

  @override
  State<_PdfPreviewPage> createState() => _PdfPreviewPageState();
}

class _PdfPreviewPageState extends State<_PdfPreviewPage> {
  bool _sharing = false;

  Future<void> _share() async {
    if (_sharing) return;
    setState(() => _sharing = true);
    try {
      await Printing.sharePdf(bytes: widget.bytes, filename: widget.filename);
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: Text(widget.title,
            style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Color(0xFF2D1A0E))),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        iconTheme: const IconThemeData(color: Color(0xFF5C3317)),
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: Colors.grey.shade200),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: _sharing
                ? const Center(
                    child: SizedBox(
                      width: 22, height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF5C3317)),
                      ),
                    ),
                  )
                : IconButton(
                    icon: const Icon(Icons.share_rounded, color: Color(0xFF5C3317)),
                    onPressed: _share,
                  ),
          ),
        ],
      ),
      body: PdfPreview(
        build: (_) => Future.value(widget.bytes),
        allowSharing: false,
        allowPrinting: false,
        canChangeOrientation: false,
        canChangePageFormat: false,
        canDebug: false,
        initialPageFormat: PdfPageFormat.a4,
        pdfPreviewPageDecoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
      ),
    );
  }
}