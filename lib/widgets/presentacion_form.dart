import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../theme/fincas_tokens.dart';
import 'fincas_widgets.dart';

/// Datos de una presentación tal como se editan en el formulario.
class PresentacionDatos {
  final double contenido;
  final String unidad;
  final double precio;
  final double? precioB2b;
  final int? cantidadB2b;
  final int? stock; // solo cuando el stock es manual
  final int pedidoMinimo;
  final bool predeterminada;
  final bool visible;
  final List<String> molienda;

  const PresentacionDatos({
    required this.contenido,
    required this.unidad,
    required this.precio,
    this.precioB2b,
    this.cantidadB2b,
    this.stock,
    this.pedidoMinimo = 1,
    this.predeterminada = false,
    this.visible = true,
    this.molienda = const [],
  });
}

/// Formulario de una presentación, para crear una nueva o editar una existente (abierto dentro de su tarjeta).
/// [onGuardar] devuelve null si se guardó, o el mensaje de error.
class PresentacionForm extends StatefulWidget {
  const PresentacionForm({
    super.key,
    required this.onGuardar,
    this.presentacion,
    this.stockManual = false,
    this.simboloMoneda = 'S/',
    this.onCancelar,
  });

  final Presentacion? presentacion;
  final bool stockManual;
  final String simboloMoneda;
  final Future<String?> Function(PresentacionDatos datos) onGuardar;
  final VoidCallback? onCancelar;

  @override
  State<PresentacionForm> createState() => _PresentacionFormState();
}

class _PresentacionFormState extends State<PresentacionForm> {
  static const _unidades = ['g', 'kg', 'ml', 'und'];
  static const _moliendas = {'ground': 'Molido', 'whole': 'Grano', 'green': 'Verde'};

  late final TextEditingController _contenido;
  late final TextEditingController _precio;
  late final TextEditingController _precioB2b;
  late final TextEditingController _cantidadB2b;
  late final TextEditingController _pedidoMinimo;
  late final TextEditingController _stock;
  late String _unidad;
  late bool _predeterminada;
  late bool _visible;
  late List<String> _molienda;

  bool _guardando = false;
  String? _errorContenido;
  String? _errorPrecio;
  String? _errorGeneral;

  bool get _esEdicion => widget.presentacion != null;

  static String _num(num n) => n % 1 == 0 ? '${n.toInt()}' : '$n';

  @override
  void initState() {
    super.initState();
    final p = widget.presentacion;
    _contenido = TextEditingController(text: p != null ? _num(p.contenido) : '');
    _precio = TextEditingController(text: p != null ? p.precio.toStringAsFixed(2) : '');
    _precioB2b = TextEditingController(text: p?.precioB2b != null ? p!.precioB2b!.toStringAsFixed(2) : '');
    _cantidadB2b = TextEditingController(text: p?.cantidadB2b != null ? '${p!.cantidadB2b}' : '');
    _pedidoMinimo = TextEditingController(text: p != null ? '${p.pedidoMinimo}' : '1');
    _stock = TextEditingController(text: p != null ? '${p.stock}' : '0');
    _unidad = p?.unidad ?? 'g';
    _predeterminada = p?.predeterminada ?? false;
    _visible = p?.visible ?? true;
    _molienda = List<String>.from(p?.molienda ?? const []);
    for (final c in [_contenido, _precio, _precioB2b, _cantidadB2b, _pedidoMinimo, _stock]) {
      c.addListener(_alEditar);
    }
  }

  @override
  void dispose() {
    for (final c in [_contenido, _precio, _precioB2b, _cantidadB2b, _pedidoMinimo, _stock]) {
      c.dispose();
    }
    super.dispose();
  }

  void _alEditar() {
    if (mounted) setState(() { _errorContenido = null; _errorPrecio = null; _errorGeneral = null; });
  }

  double? _decimal(TextEditingController c) => double.tryParse(c.text.trim().replaceAll(',', '.'));
  int? _entero(TextEditingController c) => int.tryParse(c.text.trim());

  PresentacionDatos? _leer() {
    final contenido = _decimal(_contenido) ?? 0;
    final precio = _decimal(_precio) ?? 0;
    String? errContenido, errPrecio;
    if (contenido <= 0) errContenido = 'Ingresa el contenido';
    if (precio <= 0) errPrecio = 'Ingresa el precio';
    if (errContenido != null || errPrecio != null) {
      setState(() { _errorContenido = errContenido; _errorPrecio = errPrecio; });
      return null;
    }
    return PresentacionDatos(
      contenido: contenido,
      unidad: _unidad,
      precio: precio,
      precioB2b: _precioB2b.text.trim().isEmpty ? null : _decimal(_precioB2b),
      cantidadB2b: _cantidadB2b.text.trim().isEmpty ? null : _entero(_cantidadB2b),
      stock: widget.stockManual ? (_entero(_stock) ?? 0) : null,
      pedidoMinimo: (_entero(_pedidoMinimo) ?? 1) < 1 ? 1 : (_entero(_pedidoMinimo) ?? 1),
      predeterminada: _predeterminada,
      visible: _visible,
      molienda: _molienda,
    );
  }

  bool get _hayCambios {
    final p = widget.presentacion;
    if (p == null) return true;
    final b2b = _precioB2b.text.trim().isEmpty ? null : _decimal(_precioB2b);
    final cant = _cantidadB2b.text.trim().isEmpty ? null : _entero(_cantidadB2b);
    return (_decimal(_contenido) ?? 0) != p.contenido.toDouble() ||
        _unidad != p.unidad ||
        (_decimal(_precio) ?? 0) != p.precio ||
        b2b != p.precioB2b ||
        cant != p.cantidadB2b ||
        (_entero(_pedidoMinimo) ?? 1) != p.pedidoMinimo ||
        (widget.stockManual && (_entero(_stock) ?? 0) != p.stock) ||
        _predeterminada != p.predeterminada ||
        _visible != p.visible ||
        _molienda.join(',') != p.molienda.join(',');
  }

  Future<void> _guardar() async {
    if (_guardando) return;
    final datos = _leer();
    if (datos == null) return;
    FocusScope.of(context).unfocus();
    setState(() { _guardando = true; _errorGeneral = null; });
    final error = await widget.onGuardar(datos);
    if (!mounted) return;
    setState(() { _guardando = false; _errorGeneral = error; });
  }

  Widget _campo(String etiqueta, TextEditingController c, {String? hint, String? prefijo, String? error, bool decimal = false}) {
    return TextField(
      controller: c,
      enabled: !_guardando,
      keyboardType: decimal ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.number,
      decoration: InputDecoration(labelText: etiqueta, hintText: hint, prefixText: prefijo, errorText: error),
    );
  }

  /// Dos campos lado a lado; con texto grande pasan uno debajo del otro para que no se corten.
  Widget _par(bool apilar, Widget a, Widget b, {int flexA = 1, int flexB = 1}) {
    if (apilar) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [a, const SizedBox(height: FincasSpacing.field), b]);
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [Expanded(flex: flexA, child: a), const SizedBox(width: FincasSpacing.s), Expanded(flex: flexB, child: b)],
    );
  }

  @override
  Widget build(BuildContext context) {
    final prefijo = '${widget.simboloMoneda} ';
    final apilar = MediaQuery.textScalerOf(context).scale(16) / 16 > 1.3;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _par(
          apilar,
          _campo('Contenido', _contenido, hint: 'Ej: 250', error: _errorContenido, decimal: true),
          DropdownButtonFormField<String>(
            key: ValueKey('unidad-$_unidad'),
            initialValue: _unidad,
            decoration: const InputDecoration(labelText: 'Unidad'),
            items: [for (final u in _unidades) DropdownMenuItem(value: u, child: Text(u))],
            onChanged: _guardando ? null : (v) => setState(() => _unidad = v ?? _unidad),
          ),
          flexA: 3,
          flexB: 2,
        ),
        const SizedBox(height: FincasSpacing.field),
        _par(
          apilar,
          _campo('Precio público', _precio, prefijo: prefijo, hint: '0.00', error: _errorPrecio, decimal: true),
          _campo('Precio B2B (opcional)', _precioB2b, prefijo: prefijo, hint: 'Opcional', decimal: true),
        ),
        const SizedBox(height: FincasSpacing.field),
        _par(
          apilar,
          _campo('Cant. mínima para precio B2B', _cantidadB2b, hint: 'Ej: 6 (opcional)'),
          _campo('Pedido mínimo', _pedidoMinimo, hint: '1'),
        ),
        if (widget.stockManual) ...[
          const SizedBox(height: FincasSpacing.field),
          _campo('Stock', _stock, hint: '0'),
        ],
        const SizedBox(height: FincasSpacing.l),
        const Text('Molienda disponible', style: FincasText.label),
        const Text('Marca todas las que ofreces', style: FincasText.caption),
        const SizedBox(height: FincasSpacing.s),
        Wrap(
          spacing: FincasSpacing.s,
          runSpacing: FincasSpacing.xs,
          children: [
            for (final e in _moliendas.entries)
              FilterChip(
                label: Text(e.value),
                selected: _molienda.contains(e.key),
                onSelected: _guardando
                    ? null
                    : (v) => setState(() {
                          if (v) {
                            _molienda.add(e.key);
                          } else {
                            _molienda.remove(e.key);
                          }
                        }),
              ),
          ],
        ),
        const SizedBox(height: FincasSpacing.s),
        SwitchListTile(
          value: _predeterminada,
          onChanged: _guardando ? null : (v) => setState(() => _predeterminada = v),
          contentPadding: EdgeInsets.zero,
          title: const Text('Predeterminada', style: FincasText.label),
          subtitle: const Text('Se usa como precio base del producto', style: FincasText.caption),
        ),
        SwitchListTile(
          value: _visible,
          onChanged: _guardando ? null : (v) => setState(() => _visible = v),
          contentPadding: EdgeInsets.zero,
          title: const Text('Visible en tienda', style: FincasText.label),
          subtitle: const Text('Si la apagas, esta presentación no aparece en la tienda', style: FincasText.caption),
        ),
        if (_errorGeneral != null)
          Padding(
            padding: const EdgeInsets.only(top: FincasSpacing.s),
            child: Text(_errorGeneral!, style: const TextStyle(color: FincasColors.error, fontSize: 14, height: 1.4)),
          ),
        const SizedBox(height: FincasSpacing.m),
        FincasPrimaryButton(
          label: _esEdicion ? 'Guardar cambios' : 'Crear presentación',
          loading: _guardando,
          onPressed: (_esEdicion && !_hayCambios) ? null : _guardar,
        ),
        if (widget.onCancelar != null) FincasTextButton(label: 'Cancelar', onPressed: _guardando ? null : widget.onCancelar),
      ],
    );
  }
}
