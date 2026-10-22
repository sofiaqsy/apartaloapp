import 'package:flutter/material.dart';
import '../models/producto_info.dart';
import '../services/api_service.dart';
import '../theme/fincas_tokens.dart';
import 'fincas_widgets.dart';

typedef CargarInfo = Future<ApiResponse<ProductoInfoData>> Function(String productId);
typedef GuardarInfo = Future<ApiResponse<ProductoInfo>> Function(String productId, Map<String, dynamic> cambios);

/// Sección "Información general" del detalle de un producto.
///
/// Nombre, descripción breve, detalle completo y categoría; y, para café, los atributos
/// (variedad, tueste, proceso, técnica de secado y análisis sensorial). No incluye la información
/// nutricional ni la URL del producto. Los datos y los catálogos vienen del servidor.
class ProductoInfoGeneral extends StatefulWidget {
  const ProductoInfoGeneral({
    super.key,
    required this.productId,
    this.onDirtyChanged,
    this.onGuardado,
    CargarInfo? cargar,
    GuardarInfo? guardar,
  })  : _cargar = cargar,
        _guardar = guardar;

  final String productId;

  /// Avisa si hay cambios sin guardar (para confirmar antes de salir de la pantalla).
  final ValueChanged<bool>? onDirtyChanged;

  /// Se llama con el producto ya guardado.
  final ValueChanged<ProductoInfo>? onGuardado;

  final CargarInfo? _cargar;
  final GuardarInfo? _guardar;

  @override
  State<ProductoInfoGeneral> createState() => _ProductoInfoGeneralState();
}

class _ProductoInfoGeneralState extends State<ProductoInfoGeneral> {
  final _nombre = TextEditingController();
  final _descripcion = TextEditingController();
  final _detalle = TextEditingController();
  final _nota = TextEditingController();

  ProductoInfo? _inicial;
  CatalogosProducto _catalogos = const CatalogosProducto();
  String? _categoriaId, _variedadId, _tuesteId, _procesoId, _secadoId;
  List<String> _notas = [];

  bool _cargando = true;
  bool _guardando = false;
  String? _errorCarga;
  String? _errorGuardar;
  bool _avisadoSucio = false;

  static const _maxNotas = 12;

  @override
  void initState() {
    super.initState();
    for (final c in [_nombre, _descripcion, _detalle]) {
      c.addListener(_revisarCambios);
    }
    _cargar();
  }

  @override
  void dispose() {
    for (final c in [_nombre, _descripcion, _detalle, _nota]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _cargar() async {
    setState(() { _cargando = true; _errorCarga = null; });
    final result = await (widget._cargar ?? ApiService.getProductoInfo)(widget.productId);
    if (!mounted) return;
    if (result.isSuccess && result.data != null) {
      _aplicar(result.data!.producto);
      setState(() { _catalogos = result.data!.catalogos; _cargando = false; });
    } else {
      setState(() { _errorCarga = result.error ?? 'No se pudo cargar la información'; _cargando = false; });
    }
  }

  /// Pone los valores del servidor en el formulario sin contarlos como cambios.
  void _aplicar(ProductoInfo info) {
    _inicial = info;
    _nombre.text = info.nombre;
    _descripcion.text = info.descripcionBreve;
    _detalle.text = info.detalle;
    _categoriaId = info.categoriaId;
    _variedadId = info.variedadId;
    _tuesteId = info.tuesteId;
    _procesoId = info.procesoId;
    _secadoId = info.secadoId;
    _notas = List<String>.from(info.notasSensoriales);
    _avisarSucio(false);
  }

  Map<String, dynamic> _cambios() {
    final i = _inicial;
    if (i == null) return {};
    final c = <String, dynamic>{};
    if (_nombre.text.trim() != i.nombre) c['nombre'] = _nombre.text.trim();
    if (_descripcion.text.trim() != i.descripcionBreve) c['descripcionBreve'] = _descripcion.text.trim();
    if (_detalle.text.trim() != i.detalle) c['detalle'] = _detalle.text.trim();
    if (_categoriaId != i.categoriaId) c['categoriaId'] = _categoriaId;
    if (_variedadId != i.variedadId) c['variedadId'] = _variedadId;
    if (_tuesteId != i.tuesteId) c['tuesteId'] = _tuesteId;
    if (_procesoId != i.procesoId) c['procesoId'] = _procesoId;
    if (_secadoId != i.secadoId) c['secadoId'] = _secadoId;
    if (_notas.join('\u0000') != i.notasSensoriales.join('\u0000')) c['notasSensoriales'] = _notas;
    return c;
  }

  bool get _hayCambios => _cambios().isNotEmpty;

  void _avisarSucio(bool sucio) {
    if (_avisadoSucio == sucio) return;
    _avisadoSucio = sucio;
    widget.onDirtyChanged?.call(sucio);
  }

  void _revisarCambios() {
    if (_inicial == null) return;
    _avisarSucio(_hayCambios);
    if (mounted) setState(() => _errorGuardar = null);
  }

  void _cambiar(VoidCallback f) {
    setState(f);
    _avisarSucio(_hayCambios);
  }

  Future<void> _guardar() async {
    if (_guardando) return;
    final cambios = _cambios();
    if (cambios.isEmpty) return;
    if (cambios.containsKey('nombre') && (cambios['nombre'] as String).isEmpty) {
      setState(() => _errorGuardar = 'El nombre es obligatorio');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() { _guardando = true; _errorGuardar = null; });
    final result = await (widget._guardar ?? ApiService.actualizarProductoInfo)(widget.productId, cambios);
    if (!mounted) return;
    if (result.isSuccess && result.data != null) {
      _aplicar(result.data!);
      setState(() => _guardando = false);
      widget.onGuardado?.call(result.data!);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Información guardada')));
    } else {
      setState(() { _guardando = false; _errorGuardar = result.error ?? 'No se pudo guardar'; });
    }
  }

  // ── Notas sensoriales ────────────────────────────────────────────────────

  void _agregarNota(String texto) {
    final nota = texto.trim().replaceAll(',', '');
    if (nota.isEmpty) return;
    if (_notas.any((n) => n.toLowerCase() == nota.toLowerCase())) {
      _nota.clear();
      return;
    }
    if (_notas.length >= _maxNotas) {
      setState(() => _errorGuardar = 'Máximo $_maxNotas notas sensoriales');
      return;
    }
    _nota.clear();
    _cambiar(() => _notas = [..._notas, nota]);
  }

  // ── Interfaz ─────────────────────────────────────────────────────────────

  bool get _esCafe {
    final cat = _catalogos.categorias.where((c) => c.id == _categoriaId);
    final nombre = cat.isEmpty ? '' : cat.first.nombre.toLowerCase();
    return nombre == 'café' || nombre == 'cafe' || [_variedadId, _tuesteId, _procesoId, _secadoId].any((v) => v != null) || _notas.isNotEmpty;
  }

  Widget _selector(String etiqueta, List<OpcionCatalogo> opciones, String? valor, ValueChanged<String?> alCambiar) {
    final existe = valor == null || opciones.any((o) => o.id == valor);
    return Padding(
      padding: const EdgeInsets.only(bottom: FincasSpacing.field),
      child: DropdownButtonFormField<String?>(
        // La clave recrea el campo cuando el valor cambia desde fuera (por ejemplo tras guardar).
        key: ValueKey('$etiqueta-${existe ? valor : null}'),
        initialValue: existe ? valor : null,
        isExpanded: true,
        decoration: InputDecoration(labelText: etiqueta),
        items: [
          const DropdownMenuItem<String?>(value: null, child: Text('Sin seleccionar')),
          ...opciones.map((o) => DropdownMenuItem<String?>(value: o.id, child: Text(o.nombre, overflow: TextOverflow.ellipsis))),
        ],
        onChanged: _guardando ? null : alCambiar,
      ),
    );
  }

  Widget _campo(String etiqueta, TextEditingController c, {String? hint, int lineas = 1, int? max, String? ayuda}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: FincasSpacing.field),
      child: TextField(
        controller: c,
        enabled: !_guardando,
        minLines: lineas,
        maxLines: lineas == 1 ? 1 : lineas + 3,
        maxLength: max,
        textCapitalization: TextCapitalization.sentences,
        keyboardType: lineas == 1 ? TextInputType.text : TextInputType.multiline,
        decoration: InputDecoration(labelText: etiqueta, hintText: hint, helperText: ayuda, helperMaxLines: 2, alignLabelWithHint: lineas > 1),
      ),
    );
  }

  Widget _notasSensoriales() {
    final sugeridas = _catalogos.notasSugeridas.where((s) => !_notas.any((n) => n.toLowerCase() == s.toLowerCase())).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Análisis sensorial', style: FincasText.label),
        const SizedBox(height: FincasSpacing.s),
        if (_notas.isNotEmpty)
          Wrap(
            spacing: FincasSpacing.s,
            runSpacing: FincasSpacing.xs,
            children: [
              for (final nota in _notas)
                InputChip(
                  label: Text(nota),
                  onDeleted: _guardando ? null : () => _cambiar(() => _notas = _notas.where((n) => n != nota).toList()),
                  deleteButtonTooltipMessage: 'Quitar $nota',
                ),
            ],
          ),
        const SizedBox(height: FincasSpacing.s),
        TextField(
          controller: _nota,
          enabled: !_guardando,
          textInputAction: TextInputAction.done,
          textCapitalization: TextCapitalization.sentences,
          onSubmitted: _agregarNota,
          onChanged: (v) {
            if (v.contains(',')) _agregarNota(v);
          },
          decoration: const InputDecoration(hintText: 'Escribe una nota y presiona Enter o coma'),
        ),
        if (sugeridas.isNotEmpty) ...[
          const SizedBox(height: FincasSpacing.s),
          const Text('Sugerencias', style: FincasText.caption),
          const SizedBox(height: FincasSpacing.xs),
          Wrap(
            spacing: FincasSpacing.s,
            runSpacing: FincasSpacing.xs,
            children: [
              for (final s in sugeridas) ActionChip(label: Text(s), onPressed: _guardando ? null : () => _agregarNota(s)),
            ],
          ),
        ],
        const SizedBox(height: FincasSpacing.xs),
        const Text('Las sugerencias son solo una ayuda: puedes escribir cualquier nota.', style: FincasText.caption),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return FincasCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const FincasSectionHeader('Información general'),
          if (_cargando)
            const Padding(padding: EdgeInsets.symmetric(vertical: FincasSpacing.xl), child: Center(child: FincasLoader(message: 'Cargando información...')))
          else if (_errorCarga != null) ...[
            FincasMessageState(title: 'No se pudo cargar', message: _errorCarga!, tone: FincasTone.error),
            const SizedBox(height: FincasSpacing.m),
            Center(child: SizedBox(width: 220, child: FincasSecondaryButton(label: 'Reintentar', onPressed: _cargar))),
          ] else ...[
            _campo('Nombre del producto', _nombre, max: 120),
            _campo('Descripción breve', _descripcion, hint: 'Resumen corto que aparece en listados y tarjetas.', lineas: 3, max: 300),
            _campo('Detalle completo', _detalle,
                hint: 'Cuéntanos la historia del producto: origen, altitud, recolección, beneficios, recomendaciones de preparación.',
                lineas: 5,
                ayuda: 'Texto extendido que se mostrará en la página del producto.'),
            _selector('Categoría', _catalogos.categorias, _categoriaId, (v) => _cambiar(() => _categoriaId = v)),
            if (_esCafe) ...[
              const SizedBox(height: FincasSpacing.s),
              Semantics(header: true, child: const Text('Atributos del café', style: FincasText.sectionTitle)),
              const SizedBox(height: FincasSpacing.m),
              _selector('Variedad', _catalogos.variedades, _variedadId, (v) => _cambiar(() => _variedadId = v)),
              _selector('Tueste', _catalogos.tuestes, _tuesteId, (v) => _cambiar(() => _tuesteId = v)),
              _selector('Según el proceso', _catalogos.procesos, _procesoId, (v) => _cambiar(() => _procesoId = v)),
              _selector('Técnica de secado', _catalogos.secados, _secadoId, (v) => _cambiar(() => _secadoId = v)),
              _notasSensoriales(),
            ],
            const SizedBox(height: FincasSpacing.l),
            if (_errorGuardar != null)
              Padding(
                padding: const EdgeInsets.only(bottom: FincasSpacing.m),
                child: Text(_errorGuardar!, style: const TextStyle(color: FincasColors.error, fontSize: 14, height: 1.4)),
              ),
            FincasPrimaryButton(
              label: 'Guardar información',
              loading: _guardando,
              onPressed: _hayCambios ? _guardar : null,
            ),
          ],
        ],
      ),
    );
  }
}
