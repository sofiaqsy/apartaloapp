import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/comprobante_service.dart';
import 'registrar_pago_comprobante_screen.dart';
import 'tabs/pedidos/widgets/pedido_card.dart';

/// Un comprobante compartido (WhatsApp → Compartir → Finca Rosal): se lee y se elige su pedido entre los que esperan
/// pago; los que coinciden con el monto leído van primero. Al elegir, se abre el mismo Registrar pago de siempre con
/// la imagen y el monto. Cerrar sin guardar borra la copia temporal (General Manager, 6 nov 2026).
class ElegirPedidoComprobanteScreen extends StatefulWidget {
  const ElegirPedidoComprobanteScreen({super.key, required this.imagen});
  final String imagen;

  @override
  State<ElegirPedidoComprobanteScreen> createState() => _ElegirPedidoComprobanteScreenState();
}

class _ElegirPedidoComprobanteScreenState extends State<ElegirPedidoComprobanteScreen> {
  ComprobanteLeido? _leido;
  final _pedidos = <Map<String, dynamic>>[];
  int _pagina = 0;
  bool _hayMas = true;
  bool _cargando = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    ComprobanteService.leer(widget.imagen).then((l) {
      if (mounted) setState(() => _leido = l);
    });
    _mas();
  }

  @override
  void dispose() {
    ComprobanteService.borrarTemporal(widget.imagen); // guardada o no, la copia temporal no queda
    super.dispose();
  }

  /// Los pedidos por cobrar, 20 a la vez desde el servidor.
  Future<void> _mas() async {
    if (_cargando || !_hayMas) return;
    setState(() => _cargando = true);
    final r = await ApiService.getPedidos(vista: 'POR_COBRAR', pagina: _pagina + 1, limite: 20);
    if (!mounted) return;
    setState(() {
      _cargando = false;
      if (r.isSuccess && r.data != null) {
        _pagina++;
        _pedidos.addAll(r.data!.pedidos);
        _hayMas = _pagina < r.data!.totalPaginas;
      } else {
        _error = r.error ?? 'No se pudieron traer los pedidos: revisa la señal.';
        _hayMas = false;
      }
    });
  }

  double _falta(Map<String, dynamic> p) =>
      (((p['total'] ?? 0) as num).toDouble() - ((p['montoPagado'] ?? 0) as num).toDouble()).clamp(0, double.infinity).toDouble();

  bool _coincide(Map<String, dynamic> p) {
    final m = _leido?.monto;
    return m != null && (_falta(p) - m).abs() < 0.005;
  }

  Future<void> _elegir(Map<String, dynamic> pedido) async {
    final montoPagado = ((pedido['montoPagado'] ?? 0) as num).toDouble();
    final pagos = ((pedido['pagos'] as List?) ?? []).map((p) => Map<String, dynamic>.from(p as Map)).toList();
    final guardado = await Navigator.of(context).push<bool>(CupertinoPageRoute(
      builder: (_) => RegistrarPagoComprobanteScreen(
        pedido: pedido,
        montoPagado: montoPagado,
        imagen: widget.imagen,
        leido: _leido,
        borrarImagenAlSalir: false, // si vuelve sin guardar, puede elegir otro pedido
        guardar: (monto, imagen, operacion) async {
          final (error, _) = await registrarPagoPedido(
              pedido: pedido, montoPagado: montoPagado, pagosAntes: pagos, monto: monto, imagen: imagen, operacion: operacion);
          return error;
        },
      ),
    ));
    if (guardado == true && mounted) Navigator.of(context).pop(true);
  }

  String _soles(double v) => 'S/ ${v.toStringAsFixed(2)}';

  @override
  Widget build(BuildContext context) {
    final orden = [..._pedidos]..sort((a, b) => (_coincide(b) ? 1 : 0) - (_coincide(a) ? 1 : 0));
    final leido = _leido;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.close), tooltip: 'Cerrar', onPressed: () => Navigator.of(context).maybePop()),
        title: const Text('¿De qué pedido es?'),
      ),
      body: NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (n.metrics.extentAfter < 300) _mas();
          return false;
        },
        child: ListView(padding: const EdgeInsets.symmetric(vertical: 16), children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.file(File(widget.imagen), width: 72, height: 96, fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox(width: 72, height: 96, child: Icon(Icons.broken_image_outlined))),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                leido == null
                    ? 'Leyendo el comprobante…'
                    : leido.monto == null
                        ? 'No se leyó el monto: elige el pedido y escríbelo.'
                        : 'Comprobante de ${_soles(leido.monto!)}${leido.operacion != null ? '\nNº de operación ${leido.operacion}' : ''}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ]),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text('Pedidos por cobrar', style: TextStyle(color: Colors.grey.shade700, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(height: 8),
          // La misma tarjeta que Pedidos → Por cobrar (General Manager, 7 nov 2026: reusar el diseño de la app).
          for (final p in orden) ...[
            if (_coincide(p))
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                child: Row(children: [
                  Icon(Icons.check_circle, size: 16, color: Colors.green.shade700),
                  const SizedBox(width: 6),
                  Text('Coincide el monto', style: TextStyle(color: Colors.green.shade700, fontWeight: FontWeight.w600)),
                ]),
              ),
            PedidoCard(pedido: p, onTap: () => _elegir(p), mostrarAlertaPago: true),
          ],
          if (_error != null)
            Padding(padding: const EdgeInsets.all(16), child: Text(_error!, textAlign: TextAlign.center))
          else if (_cargando || _hayMas)
            const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()))
          else if (_pedidos.isEmpty)
            Text('No hay pedidos por cobrar.', style: TextStyle(color: Colors.grey.shade600)),
        ]),
      ),
    );
  }
}
