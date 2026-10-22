import 'package:flutter/material.dart';
import '../models/producto_info.dart';
import '../services/api_service.dart';
import '../theme/fincas_tokens.dart';
import 'fincas_widgets.dart';
import 'producto_info_general.dart' show CargarInfo, GuardarInfo;

/// Ajustes del producto que afectan a sus presentaciones.
class AjustesPresentaciones {
  final bool stockManual;
  final String simboloMoneda;
  const AjustesPresentaciones({required this.stockManual, required this.simboloMoneda});
}

/// Stock manual, lote verde a vender y moneda. Va dentro de la sección "Presentaciones" (sin tarjeta propia).
/// Carga y guarda con el mismo servicio que "Información general", pero solo envía estos tres campos.
class ProductoPresentacionesAjustes extends StatefulWidget {
  const ProductoPresentacionesAjustes({
    super.key,
    required this.productId,
    this.onAjustes,
    this.onDirtyChanged,
    CargarInfo? cargar,
    GuardarInfo? guardar,
  })  : _cargar = cargar,
        _guardar = guardar;

  final String productId;

  /// Se llama al cargar y al guardar: la pantalla usa el símbolo de moneda y si el stock es manual.
  final ValueChanged<AjustesPresentaciones>? onAjustes;
  final ValueChanged<bool>? onDirtyChanged;
  final CargarInfo? _cargar;
  final GuardarInfo? _guardar;

  @override
  State<ProductoPresentacionesAjustes> createState() => _ProductoPresentacionesAjustesState();
}

class _ProductoPresentacionesAjustesState extends State<ProductoPresentacionesAjustes> {
  ProductoInfo? _inicial;
  CatalogosProducto _catalogos = const CatalogosProducto();
  bool _stockManual = false;
  String? _moneda;
  String? _loteId;

  bool _cargando = true;
  bool _guardando = false;
  String? _errorCarga;
  String? _errorGuardar;
  bool _avisadoSucio = false;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() { _cargando = true; _errorCarga = null; });
    final result = await (widget._cargar ?? ApiService.getProductoInfo)(widget.productId);
    if (!mounted) return;
    if (result.isSuccess && result.data != null) {
      _catalogos = result.data!.catalogos;
      _aplicar(result.data!.producto);
      setState(() => _cargando = false);
    } else {
      setState(() { _errorCarga = result.error ?? 'No se pudo cargar los ajustes'; _cargando = false; });
    }
  }

  void _aplicar(ProductoInfo info) {
    _inicial = info;
    _stockManual = info.stockManual;
    _moneda = info.moneda;
    _loteId = info.loteVerdeId;
    _avisarSucio(false);
    _avisarAjustes();
  }

  String get _simbolo {
    final m = _catalogos.monedas.where((m) => m.codigo == _moneda);
    return m.isEmpty ? 'S/' : m.first.simbolo.replaceAll(RegExp(r'\.$'), '');
  }

  void _avisarAjustes() => widget.onAjustes?.call(AjustesPresentaciones(stockManual: _stockManual, simboloMoneda: _simbolo));

  Map<String, dynamic> _cambios() {
    final i = _inicial;
    if (i == null) return {};
    final c = <String, dynamic>{};
    if (_stockManual != i.stockManual) c['stockManual'] = _stockManual;
    if (_moneda != i.moneda && _moneda != null) c['moneda'] = _moneda;
    if (_loteId != i.loteVerdeId) c['loteVerdeId'] = _loteId;
    return c;
  }

  bool get _hayCambios => _cambios().isNotEmpty;

  void _avisarSucio(bool sucio) {
    if (_avisadoSucio == sucio) return;
    _avisadoSucio = sucio;
    widget.onDirtyChanged?.call(sucio);
  }

  void _cambiar(VoidCallback f) {
    setState(() { f(); _errorGuardar = null; });
    _avisarSucio(_hayCambios);
  }

  Future<void> _guardar() async {
    if (_guardando) return;
    final cambios = _cambios();
    if (cambios.isEmpty) return;
    setState(() { _guardando = true; _errorGuardar = null; });
    final result = await (widget._guardar ?? ApiService.actualizarProductoInfo)(widget.productId, cambios);
    if (!mounted) return;
    if (result.isSuccess && result.data != null) {
      _aplicar(result.data!);
      setState(() => _guardando = false);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Ajustes guardados')));
    } else {
      setState(() { _guardando = false; _errorGuardar = result.error ?? 'No se pudo guardar'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_cargando) {
      return const Padding(padding: EdgeInsets.symmetric(vertical: FincasSpacing.l), child: Center(child: FincasLoader(message: 'Cargando ajustes...')));
    }
    if (_errorCarga != null) {
      return Padding(
        padding: const EdgeInsets.only(bottom: FincasSpacing.m),
        child: Column(
          children: [
            FincasMessageState(title: 'No se pudieron cargar los ajustes', message: _errorCarga!, tone: FincasTone.error),
            const SizedBox(height: FincasSpacing.s),
            FincasTextButton(label: 'Reintentar', onPressed: _cargar),
          ],
        ),
      );
    }

    final lotes = _catalogos.lotesVerdes;
    final loteExiste = _loteId == null || lotes.any((l) => l.id == _loteId);
    final monedaExiste = _catalogos.monedas.any((m) => m.codigo == _moneda);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SwitchListTile(
          value: _stockManual,
          onChanged: _guardando ? null : (v) => _cambiar(() => _stockManual = v),
          contentPadding: EdgeInsets.zero,
          title: const Text('Stock manual', style: FincasText.label),
          subtitle: const Text(
            'Este café no se asigna desde tuestes: ingresa el stock de cada presentación a mano y se descuenta al vender.',
            style: FincasText.caption,
          ),
        ),
        if (!_stockManual)
          const Padding(
            padding: EdgeInsets.only(top: FincasSpacing.s, bottom: FincasSpacing.m),
            child: _CajaInfo(
              titulo: 'Stock automático',
              texto: 'El stock de café tostado (Grano y Molido) se calcula desde los kg asignados en los tuestes. '
                  'El verde sale 1:1 del lote verde que elijas abajo.',
            ),
          ),
        Padding(
          padding: const EdgeInsets.only(bottom: FincasSpacing.xs),
          child: DropdownButtonFormField<String?>(
            key: ValueKey('lote-${loteExiste ? _loteId : null}'),
            initialValue: loteExiste ? _loteId : null,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Lote verde a vender (presentación verde)'),
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('Sin lote')),
              ...lotes.map((l) => DropdownMenuItem<String?>(value: l.id, child: Text(l.etiqueta, overflow: TextOverflow.ellipsis, maxLines: 2))),
            ],
            onChanged: _guardando ? null : (v) => _cambiar(() => _loteId = v),
          ),
        ),
        const Padding(
          padding: EdgeInsets.only(bottom: FincasSpacing.m),
          child: Text('Las presentaciones marcadas como Verde descontarán 1:1 de este lote al vender.', style: FincasText.caption),
        ),
        if (_catalogos.monedas.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: FincasSpacing.m),
            child: DropdownButtonFormField<String>(
              key: ValueKey('moneda-${monedaExiste ? _moneda : null}'),
              initialValue: monedaExiste ? _moneda : null,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Moneda'),
              items: [for (final m in _catalogos.monedas) DropdownMenuItem<String>(value: m.codigo, child: Text(m.etiqueta, overflow: TextOverflow.ellipsis))],
              onChanged: _guardando ? null : (v) => _cambiar(() => _moneda = v),
            ),
          ),
        if (_errorGuardar != null)
          Padding(
            padding: const EdgeInsets.only(bottom: FincasSpacing.m),
            child: Text(_errorGuardar!, style: const TextStyle(color: FincasColors.error, fontSize: 14, height: 1.4)),
          ),
        if (_hayCambios || _guardando)
          Padding(
            padding: const EdgeInsets.only(bottom: FincasSpacing.m),
            child: FincasPrimaryButton(label: 'Guardar ajustes', loading: _guardando, onPressed: _hayCambios ? _guardar : null),
          ),
      ],
    );
  }
}

class _CajaInfo extends StatelessWidget {
  const _CajaInfo({required this.titulo, required this.texto});
  final String titulo;
  final String texto;

  @override
  Widget build(BuildContext context) {
    return FincasCard(
      tone: FincasTone.warning,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(titulo, style: FincasText.label.copyWith(color: FincasColors.warning, fontWeight: FontWeight.w700)),
          const SizedBox(height: FincasSpacing.xs),
          Text(texto, style: FincasText.metadata.copyWith(color: FincasColors.warning)),
        ],
      ),
    );
  }
}
