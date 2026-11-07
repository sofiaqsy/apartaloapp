import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/api_service.dart';
import '../services/comprobante_service.dart';
import 'tabs/pedidos/helpers/estado_pago_helper.dart';
import 'tabs/pedidos/widgets/detalle_pedido/seccion_pago_widget.dart' show ResumenPagoPedido, CampoMontoPago;

/// Registrar pago de un pedido empezando por el comprobante (General Manager, 6 nov 2026): la foto se lee en el
/// teléfono, el monto se propone (la persona lo confirma o lo cambia) y al Guardar se guardan el pago y su
/// comprobante juntos. Sin foto también se puede, como antes. Nada se sube ni se guarda antes de Guardar.
class RegistrarPagoComprobanteScreen extends StatefulWidget {
  const RegistrarPagoComprobanteScreen({
    super.key,
    required this.pedido,
    required this.montoPagado,
    required this.guardar,
    this.imagen,
    this.leido,
    this.borrarImagenAlSalir = true,
  });

  final Map<String, dynamic> pedido;
  final double montoPagado;

  /// Una imagen que ya llegó (compartida desde WhatsApp); si no, la persona toma o elige una.
  final String? imagen;

  /// Lo ya leído de [imagen], para no leerla dos veces.
  final ComprobanteLeido? leido;

  /// La copia temporal de [imagen] se borra al salir; false cuando la pantalla anterior la sigue usando.
  final bool borrarImagenAlSalir;

  /// Guarda el pago (y el comprobante, si hay). Devuelve el error para mostrar, o null si se guardó.
  final Future<String?> Function(double monto, File? imagen, String? operacion) guardar;

  @override
  State<RegistrarPagoComprobanteScreen> createState() => _RegistrarPagoComprobanteScreenState();
}

class _RegistrarPagoComprobanteScreenState extends State<RegistrarPagoComprobanteScreen> {
  final _monto = TextEditingController();
  final _picker = ImagePicker();
  String? _imagen;
  ComprobanteLeido? _leido;
  bool _leyendo = false;
  bool _guardando = false;
  String? _error;
  // Copias temporales de esta pantalla: se borran al salir, se haya guardado o no.
  final _temporales = <String>{};

  double get _total => ((widget.pedido['total'] ?? 0) as num).toDouble();
  double get _falta => (_total - widget.montoPagado).clamp(0, double.infinity).toDouble();
  bool get _esPrimerPago => widget.montoPagado == 0;

  @override
  void initState() {
    super.initState();
    _monto.text = _falta > 0 ? _falta.toStringAsFixed(2) : '';
    final inicial = widget.imagen;
    if (inicial != null) {
      _imagen = inicial;
      if (widget.borrarImagenAlSalir) _temporales.add(inicial);
      if (widget.leido != null) {
        _usarLeido(widget.leido!);
      } else {
        _leer(inicial);
      }
    }
  }

  @override
  void dispose() {
    for (final t in _temporales) {
      ComprobanteService.borrarTemporal(t);
    }
    _monto.dispose();
    super.dispose();
  }

  Future<void> _leer(String ruta) async {
    setState(() => _leyendo = true);
    final leido = await ComprobanteService.leer(ruta);
    if (!mounted || _imagen != ruta) return;
    setState(() => _leyendo = false);
    _usarLeido(leido);
  }

  void _usarLeido(ComprobanteLeido leido) {
    setState(() {
      _leido = leido;
      if (leido.monto != null) _monto.text = leido.monto!.toStringAsFixed(2);
    });
  }

  Future<void> _elegir(ImageSource origen) async {
    final x = await _picker.pickImage(source: origen, maxWidth: 2000, maxHeight: 2000, imageQuality: 90);
    if (x == null || !mounted) return;
    setState(() {
      _imagen = x.path;
      _leido = null;
      _error = null;
    });
    _temporales.add(x.path);
    _leer(x.path);
  }

  double? get _montoEscrito => ComprobanteLeido.numero(_monto.text.replaceAll('S/', ''));

  Future<void> _guardarPago() async {
    final monto = _montoEscrito;
    if (monto == null || monto <= 0) {
      setState(() => _error = 'Escribe el monto del pago.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _guardando = true;
      _error = null;
    });
    final error = await widget.guardar(monto, _imagen == null ? null : File(_imagen!), _leido?.operacion);
    if (!mounted) return;
    if (error == null) {
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _guardando = false;
        _error = error;
      });
    }
  }

  String _soles(double v) => 'S/ ${v.toStringAsFixed(2)}';

  /// Qué deja este pago: completa el pedido, falta algo, o es más de lo que falta.
  String? get _queDeja {
    final m = _montoEscrito;
    if (m == null || m <= 0) return null;
    final resta = _falta - m;
    if (resta.abs() < 0.005) return 'Completa el pedido';
    if (resta > 0) return 'Falta ${_soles(resta)} después de este pago';
    return 'Es ${_soles(-resta)} más de lo que falta';
  }

  @override
  Widget build(BuildContext context) {
    final cliente = '${widget.pedido['cliente'] ?? widget.pedido['nombreCliente'] ?? ''}'.trim();
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.close), tooltip: 'Cerrar', onPressed: () => Navigator.of(context).maybePop()),
        // El mismo título que el diálogo de Registrar pago del pedido (General Manager, 7 nov 2026: reusar el diseño).
        title: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.payments, color: Colors.green.shade600),
          const SizedBox(width: 12),
          Flexible(child: Text(_esPrimerPago ? 'Registrar Pago' : 'Registrar Abono', overflow: TextOverflow.ellipsis)),
        ]),
      ),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.all(16),
          children: [
            Text([widget.pedido['id'], if (cliente.isNotEmpty) cliente].join(' · '), style: TextStyle(color: Colors.grey.shade700)),
            const SizedBox(height: 12),
            _comprobante(),
            const SizedBox(height: 16),
            ResumenPagoPedido(total: _total, montoPagado: widget.montoPagado),
            const SizedBox(height: 16),
            CampoMontoPago(
              controller: _monto,
              esPrimerPago: _esPrimerPago,
              saldoRestante: _falta,
              ayuda: _leido?.monto != null ? 'Leído del comprobante: revísalo' : null,
              onChanged: () => setState(() => _error = null),
            ),
            if (_queDeja != null) ...[
              const SizedBox(height: 8),
              Text(_queDeja!, style: TextStyle(color: Colors.grey.shade800, fontWeight: FontWeight.w600)),
            ],
          ],
        ),
      ),
      // Confirmar queda visible sobre el teclado; el error va justo encima.
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 12 + MediaQuery.of(context).viewInsets.bottom),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(_error!, style: TextStyle(color: Colors.red.shade700, fontWeight: FontWeight.w600)),
              ),
            ElevatedButton.icon(
              onPressed: _guardando ? null : _guardarPago,
              icon: _guardando
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.check),
              label: Text(_guardando ? 'Guardando…' : 'Confirmar'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(48),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  /// El comprobante: sin foto, dos botones; con foto, la imagen, lo que se leyó y Cambiar foto.
  Widget _comprobante() {
    final ruta = _imagen;
    if (ruta == null) {
      // El mismo recuadro gris que el resumen del pago.
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Comprobante', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text('Con la foto, el monto se llena solo.', style: TextStyle(color: Colors.grey.shade700)),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(onPressed: () => _elegir(ImageSource.camera), icon: const Icon(Icons.photo_camera_outlined), label: const Text('Tomar foto')),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton.icon(onPressed: () => _elegir(ImageSource.gallery), icon: const Icon(Icons.photo_outlined), label: const Text('Elegir foto')),
          ),
        ]),
      ]),
      );
    }
    final leido = _leido;
    final linea = _leyendo
        ? 'Leyendo el comprobante…'
        : leido == null
            ? null
            : leido.monto == null && leido.operacion == null
                ? 'No se pudo leer: escribe el monto.'
                : [
                    if (leido.monto != null) 'Monto ${_soles(leido.monto!)}',
                    if (leido.operacion != null) 'Nº de operación ${leido.operacion}',
                  ].join(' · ');
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Container(
          color: Colors.grey.shade200,
          height: 220,
          width: double.infinity,
          child: Image.file(File(ruta), fit: BoxFit.contain, errorBuilder: (_, __, ___) => const Center(child: Icon(Icons.broken_image_outlined))),
        ),
      ),
      const SizedBox(height: 8),
      Row(children: [
        if (_leyendo) const Padding(padding: EdgeInsets.only(right: 8), child: CupertinoActivityIndicator()),
        if (linea != null) Expanded(child: Text(linea, style: TextStyle(color: Colors.grey.shade800))) else const Spacer(),
        TextButton(onPressed: _guardando ? null : () => _elegir(ImageSource.gallery), child: const Text('Cambiar foto')),
      ]),
    ]);
  }
}

/// Guarda un pago de pedido con su comprobante, en el orden que no deja nada a medias: primero sube la imagen (sin
/// registro, nada cambia si falla), después el pago (con el Nº de operación leído en la nota) y al final une el
/// comprobante a ese pago (se reintenta una vez). Usa las mismas llamadas que Registrar pago y Agregar comprobante.
/// Devuelve null y la respuesta del pago, o el error para mostrar.
Future<(String?, Map<String, dynamic>?)> registrarPagoPedido({
  required Map<String, dynamic> pedido,
  required double montoPagado,
  required List<Map<String, dynamic>> pagosAntes,
  required double monto,
  File? imagen,
  String? operacion,
}) async {
  final pedidoId = '${pedido['id'] ?? ''}';
  final total = ((pedido['total'] ?? 0) as num).toDouble();
  String? url;
  if (imagen != null) {
    final subida = await ApiService.uploadImage(imagen);
    if (!subida.isSuccess || subida.data == null) {
      return ('No se subió el comprobante: revisa la señal e inténtalo de nuevo. No se guardó nada.', null);
    }
    url = subida.data;
  }
  final estado = montoPagado + monto >= total - 0.005 ? EstadoPagoHelper.PAGADO : EstadoPagoHelper.PARCIAL;
  final pago = await ApiService.actualizarEstadoPago(
    pedidoId: pedidoId,
    estadoPago: estado,
    nuevoPago: monto,
    notaPago: operacion == null ? null : 'Nº de operación $operacion (leído del comprobante)',
  );
  if (!pago.isSuccess) return ('No se guardó el pago: ${pago.error ?? 'revisa la señal e inténtalo de nuevo'}.', null);
  final datos = Map<String, dynamic>.from(pago.data ?? {});
  if (url == null) return (null, datos);

  final antes = pagosAntes.map((p) => '${p['id']}').toSet();
  final pagos = ((datos['pagos'] as List?) ?? []).map((p) => Map<String, dynamic>.from(p as Map)).toList();
  final nuevo = pagos.where((p) => !antes.contains('${p['id']}')).toList();
  final pagoId = nuevo.isNotEmpty ? '${nuevo.last['id']}' : (pagos.isNotEmpty ? '${pagos.last['id']}' : null);
  final evidencia = {
    'url': url,
    'tipo': 'APP',
    'fecha': DateTime.now().toIso8601String(),
    'descripcion': operacion == null ? 'Comprobante agregado al registrar el pago' : 'Comprobante · Nº de operación $operacion',
  };
  for (var intento = 0; intento < 2; intento++) {
    final r = await ApiService.agregarEvidenciaPago(pedidoId: pedidoId, evidencia: evidencia, paymentId: pagoId);
    if (r.isSuccess) {
      datos['evidenciaNueva'] = r.data;
      return (null, datos);
    }
  }
  datos['sinComprobante'] = true;
  return (null, datos);
}
