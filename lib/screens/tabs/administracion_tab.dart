import 'dart:async';
import 'package:flutter/cupertino.dart' show CupertinoPageRoute;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/administracion_service.dart';
import 'reportes_tab.dart';

/// Pestaña Administración (antes Reportes): Registrar, Pendientes y Resumen.
/// Los formularios guardan en la base de operaciones (fincas) con el login de la persona.
/// Los reportes de ventas de siempre siguen dentro de Resumen, sin cambios.
class AdministracionTab extends StatefulWidget {
  const AdministracionTab({super.key});

  @override
  State<AdministracionTab> createState() => _AdministracionTabState();
}

class _AdministracionTabState extends State<AdministracionTab> {
  bool _esDueno = false;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      if (mounted) setState(() => _esDueno = p.getString('business_role') == 'owner');
    });
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Administración', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            ),
          ),
          TabBar(
            labelColor: Colors.blue.shade700,
            unselectedLabelColor: Colors.grey.shade600,
            indicatorColor: Colors.blue.shade600,
            // Las pestañas caben en la pantalla del teléfono, sin deslizar. Mi área está en Perfil.
            isScrollable: false,
            labelPadding: const EdgeInsets.symmetric(horizontal: 2),
            labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            unselectedLabelStyle: const TextStyle(fontSize: 13),
            tabs: const [Tab(text: 'Registrar'), Tab(text: 'Pendientes'), Tab(text: 'Solicitudes'), Tab(text: 'Resumen')],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _Registrar(esDueno: _esDueno),
                _Pendientes(esDueno: _esDueno),
                _Solicitudes(esDueno: _esDueno),
                _Resumen(esDueno: _esDueno),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Campos y formularios ────────────────────────────────────────────────────

enum _Tipo { texto, monto, numero, opcion, persona, fecha }

class _Campo {
  const _Campo(this.clave, this.etiqueta, this.tipo,
      {this.opciones = const {}, this.requerido = true, this.rol, this.visibleSi, this.porDefecto, this.ayuda, this.avanzado = false});
  /// Campo poco usado: va dentro de "Más opciones" para que el formulario sea corto.
  final bool avanzado;
  final String clave;
  final String etiqueta;
  final _Tipo tipo;
  final Map<String, String> opciones; // valor -> texto
  final bool requerido;
  /// Para un campo persona: a quién se puede elegir (agricultor, comprador o ambos); null = cualquiera.
  final String? rol;
  final bool Function(Map<String, dynamic> valores)? visibleSi;
  final dynamic porDefecto;
  final String? ayuda;
}

const _areas = {
  'farm': 'Finca', 'sourcing': 'Compras', 'production': 'Producción', 'quality': 'Calidad', 'commercial': 'Comercial',
  'marketing': 'Marketing', 'fulfillment': 'Logística', 'people': 'Personas', 'finance': 'Finanzas', 'compliance': 'Cumplimiento',
  'risk': 'Riesgos', 'technology': 'Tecnología', 'strategy': 'Estrategia', 'shared': 'Compartido',
};

/// Una categoría de gasto: qué entra, qué no, y lo que sugiere. La lista viva viene de la base
/// (expense_category_guide, acordada por las áreas el 1 de noviembre de 2026); esta es el respaldo sin señal.
class _Categoria {
  const _Categoria(this.categoria, this.queEntra, this.noVa, this.area, this.centro, {this.principal = false, this.pideDescripcion = false});
  final String categoria;
  final String queEntra;
  final String? noVa;
  final String area;
  final String centro;
  final bool principal;
  final bool pideDescripcion;

  factory _Categoria.desde(Map m) => _Categoria('${m['category']}', '${m['what_goes_here'] ?? ''}', m['not_here'] as String?,
      '${m['default_area'] ?? 'shared'}', '${m['default_cost_centre'] ?? 'coffee'}',
      principal: m['main'] == true, pideDescripcion: m['needs_description'] == true);
}

/// El gasto más frecuente: va primero y ya elegido al abrir Registrar gasto (General Manager, 1 nov 2026).
const _categoriaInicial = 'Combustible';

const _guiaRespaldo = [
  _Categoria('Combustible', 'Gasolina y petróleo de la camioneta, el carro o una máquina.', 'Gas GLP de la tostadora (Gas).', 'fulfillment', 'coffee', principal: true),
  _Categoria('Transporte', 'Pasajes y movilidad de personas, y traslado del café comprado antes de venderlo.', 'Gasolina (Combustible). Envío al cliente (Flete).', 'sourcing', 'coffee', principal: true),
  _Categoria('Mano de obra', 'Pago por día, por kilo o por lata: jornaleros, cosechadores, maquinista.', 'Sueldos mensuales (Personal).', 'farm', 'farm', principal: true),
  _Categoria('Personal', 'Sueldo fijo o mensual, ayuda médica a trabajadores, cursos.', 'Jornales (Mano de obra).', 'people', 'coffee', principal: true),
  _Categoria('Insumos', 'Abono, plantas, almácigo, fungicidas, herramientas de campo.', 'Bolsas de café (Empaque).', 'farm', 'farm', principal: true),
  _Categoria('Construcción', 'Obras: local, cafetería, cocina, techo, piso, carretera. Escribe qué obra.', 'Reparaciones (Mantenimiento).', 'strategy', 'venue', principal: true, pideDescripcion: true),
  _Categoria('Mantenimiento', 'Reparar máquinas y vehículos. Repara, no compra.', 'Máquina nueva (inversión).', 'production', 'coffee', principal: true),
  _Categoria('Empaque', 'Bolsas, válvulas, etiquetas impresas, serigrafiado, costales, film, cajas.', 'Diseño de etiqueta (Marketing).', 'fulfillment', 'coffee', principal: true),
  _Categoria('Flete', 'Envío de café ya vendido al cliente.', 'Café comprado en camino (Transporte).', 'fulfillment', 'coffee'),
  _Categoria('Gas', 'Gas GLP: tostadora, secadora, cocina del local.', 'Gasolina (Combustible).', 'production', 'coffee'),
  _Categoria('Finca', 'Otros gastos de la chacra: despulpadora, sus piezas, materiales.', 'Obras (Construcción). Luz (Servicios).', 'farm', 'farm'),
  _Categoria('Servicios', 'Luz, agua, alquiler, secado o pilado por terceros.', 'Internet y teléfono (Tecnología).', 'finance', 'coffee'),
  _Categoria('Tecnología', 'Teléfono, internet, programas, celular, computadora.', null, 'technology', 'coffee'),
  _Categoria('Calidad y laboratorio', 'Catación, laboratorio, medidor de humedad, bolsitas de muestra.', null, 'quality', 'coffee'),
  _Categoria('Marketing', 'Diseño, fotos, publicidad, ferias y eventos, material de muestras.', 'Impresión de bolsas (Empaque).', 'marketing', 'coffee'),
  _Categoria('Impuestos y comisiones', 'SUNAT, ITF, comisiones del banco, multas y papeletas.', null, 'finance', 'coffee'),
  _Categoria('Permisos y licencias', 'DIGESA, registro sanitario, licencia municipal, trámites.', null, 'compliance', 'coffee'),
  _Categoria('Seguros', 'Primas de pólizas.', null, 'risk', 'coffee'),
  _Categoria('Servicios profesionales', 'Contadora, abogado, consultor externo.', 'Sueldos (Personal).', 'finance', 'coffee'),
  _Categoria('Otro', 'Solo si nada encaja. Escribe siempre qué fue.', null, 'shared', 'coffee', pideDescripcion: true),
];

/// "Para qué" fue el combustible: Administración lo elige en "Áreas por revisar" cuando la base no pudo saberlo
/// (el formulario no lo pregunta: General Manager, 1 nov 2026).
const _paraQueCombustible = {
  'compra': ('Compra de café', 'sourcing', 'coffee'),
  'finca': ('Finca', 'farm', 'farm'),
  'reparto': ('Reparto', 'fulfillment', 'coffee'),
  'obra': ('Obra', 'strategy', 'venue'),
  'otro': ('Otro', 'fulfillment', 'coffee'),
};

const _metodosPago = {'transfer': 'Transferencia', 'yape': 'Yape', 'plin': 'Plin', 'cash': 'Efectivo'};
bool _necesitaOperacion(Map<String, dynamic> v, [String clave = 'metodo']) => v[clave] != null && v[clave] != 'cash';
final _campoOperacion = _Campo('operacion', 'Número de operación', _Tipo.texto,
    visibleSi: _necesitaOperacion, ayuda: 'Para cruzarlo solo con el banco');

final Map<String, List<_Campo>> _formularios = {
  // Un gasto es una solicitud de pago: Administración decide cómo pagarlo (Pagar gasto, en Pendientes).
  'gasto': [
    // Las categorías y el área sugerida vienen de la base (expense_categories); esta lista es el respaldo.
    const _Campo('categoria', 'Categoría', _Tipo.opcion), // las opciones son la guía de categorías (_guia)
    const _Campo('monto', 'Monto (S/)', _Tipo.monto),
    const _Campo('descripcion', 'Descripción', _Tipo.texto, requerido: false),
    // Quien registra elige el área que responde por el gasto; se llena sola según la categoría.
    const _Campo('area', 'Área', _Tipo.opcion, opciones: _areas, porDefecto: 'shared', avanzado: true),
    const _Campo('centro', 'Centro de costo', _Tipo.opcion, opciones: {'coffee': 'Café', 'farm': 'Finca', 'venue': 'Local', 'property': 'Casa'}, porDefecto: 'coffee', avanzado: true),
    const _Campo('fecha', 'Fecha', _Tipo.fecha, avanzado: true),
  ],
  'pagoGasto': [
    const _Campo('metodo', 'Cómo se pagó', _Tipo.opcion, opciones: _metodosPago, porDefecto: 'transfer'),
    _campoOperacion,
    const _Campo('fecha', 'Fecha', _Tipo.fecha, avanzado: true),
  ],
  // Un adelanto es una solicitud: Administración lo aprueba (eligiendo cómo pagarlo) o lo rechaza.
  'adelanto': [
    const _Campo('personaId', 'Para', _Tipo.persona, rol: 'ambos'),
    const _Campo('monto', 'Monto (S/)', _Tipo.monto, ayuda: 'Máximo S/ 2,000 y uno abierto por persona'),
    const _Campo('motivo', 'Para qué', _Tipo.texto, requerido: false),
    const _Campo('devuelveEn', 'Se devuelve en', _Tipo.opcion, opciones: {'coffee': 'Café', 'money': 'Dinero', 'coffee_or_money': 'Café o dinero'}, porDefecto: 'coffee', avanzado: true),
    const _Campo('fecha', 'Fecha', _Tipo.fecha, avanzado: true),
  ],
  'aprobarAdelanto': [
    const _Campo('metodo', 'Cómo se entrega', _Tipo.opcion, opciones: _metodosPago, porDefecto: 'transfer'),
    _campoOperacion,
    const _Campo('fecha', 'Fecha', _Tipo.fecha, avanzado: true),
  ],
  'rechazarAdelanto': [
    const _Campo('motivo', 'Por qué se rechaza', _Tipo.texto),
  ],
  'proveedor': [
    const _Campo('nombre', 'Nombre', _Tipo.texto),
    const _Campo('rol', 'Es', _Tipo.opcion, opciones: {'farmer': 'Agricultor', 'buyer': 'Comprador', 'supplier': 'Proveedor de insumos'}),
    _Campo('vende', 'Vende', _Tipo.opcion, opciones: const {'parchment': 'Pergamino', 'cherry': 'Cereza', 'both': 'Ambos'}, porDefecto: 'parchment',
        visibleSi: (v) => v['rol'] == 'farmer'),
    _Campo('recogidoPor', 'Lo recoge (comprador)', _Tipo.persona, requerido: false, rol: 'comprador',
        visibleSi: (v) => v['rol'] == 'farmer'),
    const _Campo('documento', 'DNI o RUC', _Tipo.texto, requerido: false),
    const _Campo('telefono', 'Teléfono', _Tipo.texto, requerido: false),
    const _Campo('comunidad', 'Comunidad o sector', _Tipo.texto, requerido: false, avanzado: true),
    const _Campo('tipo', 'Persona o empresa', _Tipo.opcion, opciones: {'person': 'Persona', 'business': 'Empresa'}, porDefecto: 'person', avanzado: true),
  ],
  'entrega': [
    const _Campo('agricultorId', 'Agricultor', _Tipo.persona, rol: 'agricultor'),
    const _Campo('compradorId', 'Recogido por (comprador)', _Tipo.persona, requerido: false, rol: 'comprador'),
    const _Campo('estado', 'Café', _Tipo.opcion, opciones: {'parchment': 'Pergamino', 'cherry': 'Cereza', 'green': 'Verde'}, porDefecto: 'parchment'),
    const _Campo('kg', 'Kilos', _Tipo.numero),
    const _Campo('precioKg', 'Precio por kilo (si ya se sabe)', _Tipo.monto, requerido: false, ayuda: 'Con precio queda en "Por pagar" para Administración'),
    const _Campo('humedad', 'Humedad %', _Tipo.numero, requerido: false, avanzado: true),
    const _Campo('rendimiento', 'Factor de rendimiento', _Tipo.numero, requerido: false, avanzado: true),
    const _Campo('notas', 'Notas', _Tipo.texto, requerido: false),
    const _Campo('fecha', 'Fecha', _Tipo.fecha, avanzado: true),
  ],
  // Con el precio, la compra usa los adelantos abiertos y lo demás queda en "Por pagar" para Administración.
  'precio': [
    const _Campo('precioKg', 'Precio por kilo', _Tipo.monto),
    const _Campo('fecha', 'Fecha', _Tipo.fecha, avanzado: true),
  ],
  'pago': [
    const _Campo('monto', 'Monto (vacío = todo lo que se debe)', _Tipo.monto, requerido: false),
    const _Campo('metodo', 'Cómo se pagó', _Tipo.opcion, opciones: _metodosPago, porDefecto: 'transfer'),
    _campoOperacion,
    const _Campo('fecha', 'Fecha', _Tipo.fecha, avanzado: true),
  ],
  'ingreso': [
    const _Campo('tipo', 'Qué es', _Tipo.opcion, opciones: {'sale': 'Venta fuera de la tienda', 'advance_return': 'Devolución de adelanto', 'loan': 'Préstamo', 'other': 'Otro'}),
    const _Campo('adelantoId', 'Adelanto que se devuelve (código ADV-)', _Tipo.texto, visibleSi: _esDevolucion),
    const _Campo('monto', 'Monto (S/)', _Tipo.monto),
    const _Campo('metodo', 'Cómo entró', _Tipo.opcion, opciones: {'transfer': 'Transferencia', 'yape': 'Yape', 'plin': 'Plin', 'cash': 'Efectivo', 'deposit': 'Depósito'}, porDefecto: 'transfer'),
    _campoOperacion,
    const _Campo('descripcion', 'Descripción', _Tipo.texto, requerido: false),
    const _Campo('fecha', 'Fecha', _Tipo.fecha, avanzado: true),
  ],
  'retiro': [
    const _Campo('monto', 'Monto (S/)', _Tipo.monto),
    const _Campo('operacion', 'Número de operación', _Tipo.texto, requerido: false),
    const _Campo('notas', 'Para qué', _Tipo.texto, requerido: false),
    const _Campo('fecha', 'Fecha', _Tipo.fecha, avanzado: true),
  ],
};

bool _esDevolucion(Map<String, dynamic> v) => v['tipo'] == 'advance_return';

// Nombres de acción (verbo + cosa), iguales en el botón y en el título del formulario.
const _titulos = {
  'gasto': 'Registrar gasto', 'pagoGasto': 'Pagar gasto', 'adelanto': 'Solicitar adelanto', 'aprobarAdelanto': 'Aprobar adelanto',
  'rechazarAdelanto': 'Rechazar adelanto', 'proveedor': 'Registrar proveedor', 'entrega': 'Registrar entrega',
  'precio': 'Poner precio a la entrega', 'pago': 'Pagar compra', 'ingreso': 'Registrar ingreso', 'retiro': 'Pasar dinero a caja',
};

// Lo que pasó y lo que sigue, después de guardar.
const _hecho = {
  'gasto': 'Gasto registrado ✓ Administración lo pagará', 'pagoGasto': 'Gasto pagado ✓',
  'adelanto': 'Adelanto solicitado ✓ Administración lo revisará', 'aprobarAdelanto': 'Adelanto aprobado y entregado ✓',
  'rechazarAdelanto': 'Adelanto rechazado', 'proveedor': 'Proveedor registrado ✓', 'entrega': 'Entrega registrada ✓',
  'precio': 'Precio puesto ✓ Lo que falta queda por pagar', 'pago': 'Compra pagada ✓', 'retiro': 'Dinero pasado a caja ✓',
};

/// Abre un formulario a pantalla completa. Se cierra con la X o deslizando hacia la derecha (como
/// cualquier pantalla de iPhone). [fijos] van siempre (por ejemplo entregaId o compraId desde Pendientes).
Future<bool> _abrirFormulario(BuildContext context, String formulario, {Map<String, dynamic> fijos = const {}, String? subtitulo}) async {
  final guardado = await Navigator.of(context).push<bool>(
    CupertinoPageRoute(builder: (_) => _FormularioSheet(formulario: formulario, fijos: fijos, subtitulo: subtitulo)),
  );
  return guardado == true;
}

class _FormularioSheet extends StatefulWidget {
  const _FormularioSheet({required this.formulario, required this.fijos, this.subtitulo});
  final String formulario;
  final Map<String, dynamic> fijos;
  final String? subtitulo;

  @override
  State<_FormularioSheet> createState() => _FormularioSheetState();
}

class _FormularioSheetState extends State<_FormularioSheet> {
  late final List<_Campo> _campos = _formularios[widget.formulario]!;
  late final String _clave = AdministracionService.nuevaClave(widget.formulario); // la misma en cada reintento
  final Map<String, dynamic> _valores = {};
  final Map<String, String> _nombresElegidos = {}; // campo persona -> nombre que se muestra
  final Map<String, Map<String, String>> _opciones = {}; // opciones que vienen de la base
  Map<String, _Categoria> _guia = {for (final g in _guiaRespaldo) g.categoria: g}; // qué entra en cada categoría
  bool _todasCategorias = false; // "Ver más categorías"
  // Combustible: la base sugiere el área (compra o entrega del mismo día, o la de la persona); si la persona
  // no la cambia, la elige la base al guardar.
  bool _areaTocada = false;
  bool _guardando = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    for (final c in _campos) {
      if (c.porDefecto != null) _valores[c.clave] = c.porDefecto;
      if (c.tipo == _Tipo.fecha) _valores[c.clave] = DateTime.now();
    }
    if (widget.formulario == 'gasto') {
      final inicial = _guia[_categoriaInicial];
      if (inicial != null) {
        _valores['categoria'] = _categoriaInicial;
        _valores['area'] = inicial.area;
        _valores['centro'] = inicial.centro;
        _pedirSugerencia(); // la base dice el área (compra del día, el área de la persona)
      }
      AdministracionService.categorias().then((r) {
        if (!mounted || !r.isSuccess) return;
        final cats = (r.data!['categorias'] as List? ?? []).cast<Map>();
        final areas = (r.data!['areas'] as List? ?? []).cast<Map>();
        setState(() {
          if (cats.isNotEmpty) {
            final guia = {for (final c in cats) '${c['category']}': _Categoria.desde(c)};
            // Combustible primero; las demás en el orden de la base.
            _guia = {
              if (guia.containsKey(_categoriaInicial)) _categoriaInicial: guia[_categoriaInicial]!,
              for (final e in guia.entries) if (e.key != _categoriaInicial) e.key: e.value,
            };
          }
          if (areas.isNotEmpty) _opciones['area'] = {for (final a in areas) '${a['id']}': '${a['name']}'};
        });
      });
    }
  }

  List<_Campo> get _visibles => _campos.where((c) => c.visibleSi == null || c.visibleSi!(_valores)).toList();

  Future<void> _guardar() async {
    final faltan = _visibles.where((c) => c.requerido && (_valores[c.clave] == null || _valores[c.clave] == '')).map((c) => c.etiqueta);
    if (faltan.isNotEmpty) {
      setState(() => _error = 'Falta: ${faltan.join(', ')}');
      return;
    }
    final categoria = widget.formulario == 'gasto' ? _guia[_valores['categoria']] : null;
    if (categoria != null && categoria.pideDescripcion && '${_valores['descripcion'] ?? ''}'.trim().isEmpty) {
      setState(() => _error = 'Escribe en Descripción qué fue (lo pide ${categoria.categoria}).');
      return;
    }
    final datos = <String, dynamic>{...widget.fijos};
    for (final c in _visibles) {
      final v = _valores[c.clave];
      if (v == null || v == '') continue;
      datos[c.clave] = v is DateTime ? v.toIso8601String().substring(0, 10) : v;
    }
    if (_areaAutomatica) {
      // La base pone el área (compra o entrega del mismo día, o la de la persona); el formulario no pregunta para qué fue.
      datos.remove('area');
      datos.remove('centro');
    }
    setState(() { _guardando = true; _error = null; });
    final r = await AdministracionService.registrar(widget.formulario, datos, clave: _clave);
    if (!mounted) return;
    if (r.isSuccess) {
      var texto = _hecho[widget.formulario] ?? '${_titulos[widget.formulario]} ✓';
      final areaNombre = r.data?['area_name'];
      if (widget.formulario == 'gasto' && areaNombre != null) {
        texto = '$texto · Área: $areaNombre${r.data?['area_source'] == 'to_review' ? ' (por revisar)' : ''}';
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(texto)));
      Navigator.of(context).pop(true);
    } else {
      setState(() { _guardando = false; _error = r.error; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final principales = _visibles.where((c) => !c.avanzado).toList();
    final avanzados = _visibles.where((c) => c.avanzado).toList();
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.close), tooltip: 'Cancelar', onPressed: () => Navigator.of(context).pop(false)),
        title: Text(_titulos[widget.formulario]!),
      ),
      // Tocar fuera de un campo esconde el teclado.
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => FocusScope.of(context).unfocus(),
        child: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          children: [
            if (widget.subtitulo != null)
              Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(widget.subtitulo!, style: TextStyle(color: Colors.grey.shade600))),
            for (final c in principales) Padding(padding: const EdgeInsets.only(bottom: 16), child: _campo(c)),
            if (avanzados.isNotEmpty)
              ExpansionTile(
                title: const Text('Más opciones'),
                subtitle: Text(_resumenAvanzado(avanzados), style: TextStyle(color: Colors.grey.shade600)),
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.only(top: 8),
                children: [for (final c in avanzados) Padding(padding: const EdgeInsets.only(bottom: 16), child: _campo(c))],
              ),
          ],
        ),
      ),
      // El botón Guardar siempre a la vista, encima del teclado, con el aviso justo encima.
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(20, 8, 20, 8 + MediaQuery.of(context).viewInsets.bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(_error!, style: TextStyle(color: Colors.red.shade700, fontWeight: FontWeight.w600)),
                ),
              ElevatedButton(
                onPressed: _guardando ? null : _guardar,
                style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                child: Text(_guardando ? 'Guardando...' : 'Guardar'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// "Fecha: hoy · Área: Café" para que se vea sin abrir "Más opciones".
  String _resumenAvanzado(List<_Campo> campos) => campos.map((c) {
        final v = _valores[c.clave];
        if (v is DateTime) {
          final hoy = DateTime.now();
          return '${c.etiqueta}: ${v.year == hoy.year && v.month == hoy.month && v.day == hoy.day ? 'hoy' : '${v.day}/${v.month}/${v.year}'}';
        }
        final auto = c.clave == 'area' && _areaAutomatica ? ' (automático)' : '';
        return '${c.etiqueta}: ${v == null ? '—' : (_opcionesDe(c)[v] ?? (c.clave == 'area' ? _areas[v] : null) ?? v)}$auto';
      }).join(' · ');

  Map<String, String> _opcionesDe(_Campo c) => _opciones[c.clave] ?? c.opciones;

  /// Al elegir la categoría, se sugieren el área y el centro de costo (se pueden cambiar en Más opciones).
  void _sugerirPorCategoria(String? categoria) {
    final g = _guia[categoria];
    setState(() {
      _valores['area'] = g?.area ?? 'shared';
      _valores['centro'] = g?.centro ?? 'coffee';
    });
  }

  Future<void> _pedirSugerencia() async {
    final f = _valores['fecha'];
    final r = await AdministracionService.sugerirArea('Combustible', f is DateTime ? f.toIso8601String().substring(0, 10) : null);
    if (!mounted || !r.isSuccess || _valores['categoria'] != 'Combustible') return;
    setState(() {
      if (!_areaTocada) {
        if (r.data!['area'] != null) _valores['area'] = r.data!['area'];
        if (r.data!['cost_centre'] != null) _valores['centro'] = r.data!['cost_centre'];
      }
    });
  }

  bool get _areaAutomatica => widget.formulario == 'gasto' && _valores['categoria'] == 'Combustible' && !_areaTocada;

  /// Las categorías principales primero; el resto con "Ver más categorías". La elegida siempre se ve.
  Widget _categorias(_Campo c) {
    final elegida = _valores[c.clave] as String?;
    final todas = _guia.keys.toList();
    final hayPrincipales = todas.any((k) => _guia[k]?.principal == true);
    final visibles = _todasCategorias || !hayPrincipales ? todas : todas.where((k) => _guia[k]?.principal == true || k == elegida).toList();
    final g = _guia[elegida];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(c.etiqueta, style: TextStyle(color: Colors.grey.shade700, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final k in visibles)
              ChoiceChip(
                label: Text(k),
                selected: elegida == k,
                onSelected: (_) {
                  FocusScope.of(context).unfocus();
                  setState(() { _valores[c.clave] = k; _areaTocada = false; });
                  _sugerirPorCategoria(k);
                  if (k == 'Combustible') _pedirSugerencia();
                },
              ),
            if (visibles.length < todas.length)
              ActionChip(
                avatar: const Icon(Icons.expand_more, size: 18),
                label: const Text('Ver más categorías'),
                onPressed: () => setState(() => _todasCategorias = true),
              ),
          ],
        ),
        if (g != null && g.queEntra.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text.rich(TextSpan(children: [
              TextSpan(text: g.queEntra),
              if (g.noVa != null) TextSpan(text: '\nNo va aquí: ${g.noVa}', style: TextStyle(color: Colors.grey.shade600)),
            ]), style: const TextStyle(fontSize: 13)),
          ),
      ],
    );
  }

  Widget _campo(_Campo c) {
    final deco = InputDecoration(labelText: c.requerido ? c.etiqueta : '${c.etiqueta} (opcional)', helperText: c.ayuda, border: const OutlineInputBorder());
    void poner(dynamic v) => setState(() => _valores[c.clave] = v);
    switch (c.tipo) {
      case _Tipo.opcion:
        if (widget.formulario == 'gasto' && c.clave == 'categoria') return _categorias(c);
        // Botones para tocar en lugar de una lista desplegable.
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(c.requerido ? c.etiqueta : '${c.etiqueta} (opcional)', style: TextStyle(color: Colors.grey.shade700, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final e in _opcionesDe(c).entries)
                  ChoiceChip(
                    label: Text(e.value),
                    selected: _valores[c.clave] == e.key,
                    onSelected: (sel) {
                      FocusScope.of(context).unfocus();
                      final v = sel ? e.key : (c.requerido ? e.key : null);
                      if (c.clave == 'area' || c.clave == 'centro') _areaTocada = true;
                      poner(v);
                    },
                  ),
              ],
            ),
            if (c.ayuda != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(c.ayuda!, style: TextStyle(fontSize: 12, color: Colors.grey.shade600))),
          ],
        );
      case _Tipo.persona:
        // Un campo que se toca y abre una pantalla de búsqueda (no una lista desplegable larga que no se cierra).
        final nombre = _nombresElegidos[c.clave];
        return InkWell(
          onTap: () async {
            FocusScope.of(context).unfocus();
            final p = await _elegirPersona(context, titulo: c.etiqueta, rol: c.rol, opcional: !c.requerido, elegido: _valores[c.clave] as String?);
            if (p == null || !mounted) return; // cerró sin elegir: no cambia nada
            setState(() {
              if (p.isEmpty) {
                _valores.remove(c.clave);
                _nombresElegidos.remove(c.clave);
              } else {
                _valores[c.clave] = p['id'];
                _nombresElegidos[c.clave] = '${p['nombre']}';
                // Entrega: se sugiere el comprador que suele recoger a ese agricultor.
                if (widget.formulario == 'entrega' && c.clave == 'agricultorId' && p['recogidoPor'] != null && _valores['compradorId'] == null) {
                  _valores['compradorId'] = p['recogidoPor'];
                  _nombresElegidos['compradorId'] = '${p['recogidoPorNombre'] ?? p['recogidoPor']}';
                }
              }
            });
          },
          child: InputDecorator(
            decoration: deco.copyWith(suffixIcon: const Icon(Icons.search)),
            isEmpty: nombre == null,
            child: Text(nombre ?? '', overflow: TextOverflow.ellipsis),
          ),
        );
      case _Tipo.fecha:
        final f = _valores[c.clave] as DateTime;
        return InkWell(
          onTap: () async {
            final elegido = await showDatePicker(context: context, initialDate: f, firstDate: DateTime(2026, 1, 1), lastDate: DateTime.now());
            if (elegido != null) poner(elegido);
          },
          child: InputDecorator(decoration: deco, child: Text('${f.day}/${f.month}/${f.year}')),
        );
      case _Tipo.monto:
      case _Tipo.numero:
        final primero = _visibles.isNotEmpty && identical(_visibles.first, c);
        return TextFormField(
          decoration: deco,
          autofocus: primero && c.tipo == _Tipo.monto, // el monto primero, con el teclado de números abierto
          style: primero ? const TextStyle(fontSize: 22, fontWeight: FontWeight.w600) : null,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          textInputAction: TextInputAction.done,
          onChanged: (t) => poner(_numero(t)),
        );
      case _Tipo.texto:
        return TextFormField(decoration: deco, onChanged: (t) => poner(t.trim().isEmpty ? null : t.trim()));
    }
  }

  /// "1,000.50", "1000,5" y "1000.5" -> número.
  num? _numero(String t) {
    final s = t.trim().replaceAll(' ', '');
    if (s.isEmpty) return null;
    final normal = RegExp(r',\d{1,2}$').hasMatch(s) ? s.replaceAll('.', '').replaceAll(',', '.') : s.replaceAll(',', '');
    final v = num.tryParse(normal);
    return v != null && v > 0 ? v : null;
  }
}

// ─── Registrar ───────────────────────────────────────────────────────────────

class _Registrar extends StatelessWidget {
  const _Registrar({required this.esDueno});
  final bool esDueno;

  @override
  Widget build(BuildContext context) {
    // Todos registran y piden; sólo Administración mueve dinero (Pagar compra, Retiro a caja).
    final botones = <(String, IconData, String)>[
      ('gasto', Icons.receipt_long, _titulos['gasto']!),
      ('entrega', Icons.local_shipping, _titulos['entrega']!),
      ('adelanto', Icons.handshake, _titulos['adelanto']!),
      ('proveedor', Icons.person_add_alt_1, _titulos['proveedor']!),
      if (esDueno) ('pago', Icons.payments, 'Pagar compras'),
      if (esDueno) ('retiro', Icons.account_balance_wallet, _titulos['retiro']!),
    ];
    return GridView.count(
      crossAxisCount: 2,
      padding: const EdgeInsets.all(16),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.6,
      children: [
        for (final (form, icono, texto) in botones)
          _BotonGrande(
            icono: icono,
            texto: texto,
            onTap: () async {
              if (form == 'pago') {
                DefaultTabController.of(context).animateTo(1); // se paga desde "Por pagar"
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Elige la compra en "Compras por pagar"')));
                return;
              }
              await _abrirFormulario(context, form);
            },
          ),
      ],
    );
  }
}

class _BotonGrande extends StatelessWidget {
  const _BotonGrande({required this.icono, required this.texto, required this.onTap, this.habilitado = true});
  final IconData icono;
  final String texto;
  final VoidCallback onTap;
  final bool habilitado;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: habilitado ? Colors.blue.shade50 : Colors.grey.shade200,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: habilitado ? onTap : null,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icono, size: 30, color: habilitado ? Colors.blue.shade700 : Colors.grey),
            const SizedBox(height: 6),
            Text(texto, textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w600, color: habilitado ? Colors.black87 : Colors.grey)),
          ],
        ),
      ),
    );
  }
}

// ─── Pendientes ──────────────────────────────────────────────────────────────

class _Pendientes extends StatefulWidget {
  const _Pendientes({required this.esDueno});
  final bool esDueno;

  @override
  State<_Pendientes> createState() => _PendientesState();
}

class _PendientesState extends State<_Pendientes> {
  Map<String, dynamic>? _datos;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final r = await AdministracionService.pendientes();
    if (!mounted) return;
    setState(() { _datos = r.data; _error = r.isSuccess ? null : r.error; });
  }

  String _soles(dynamic v) => 'S/ ${(num.tryParse('${v ?? 0}') ?? 0).toStringAsFixed(2)}';

  /// Administración dice para qué fue: queda como corrección; el gasto no se cambia.
  Future<void> _revisarArea(Map<String, dynamic> g) async {
    final eleccion = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(title: Text('${g['category']} · ${_soles(g['amount'])}', style: const TextStyle(fontWeight: FontWeight.w600)), subtitle: const Text('¿Para qué fue?')),
          for (final e in _paraQueCombustible.entries.where((e) => e.key != 'otro'))
            ListTile(title: Text(e.value.$1), subtitle: Text(_areas[e.value.$2] ?? e.value.$2), onTap: () => Navigator.pop(ctx, e.key)),
        ]),
      ),
    );
    if (eleccion == null || !mounted) return;
    final p = _paraQueCombustible[eleccion]!;
    final r = await AdministracionService.registrar('corregirArea', {'gastoId': g['id'], 'area': p.$2, 'centro': p.$3, 'motivo': p.$1},
        clave: AdministracionService.nuevaClave('corregirArea'));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(r.isSuccess ? 'Área corregida ✓ ${_areas[p.$2]}' : (r.error ?? 'No se guardó'))));
    if (r.isSuccess) _cargar();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) return _Mensaje(texto: _error!, onReintentar: _cargar);
    if (_datos == null) return const Center(child: CircularProgressIndicator());
    List<dynamic> lista(String k) => (_datos![k] as List?) ?? [];
    return RefreshIndicator(
      onRefresh: _cargar,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _Seccion(titulo: 'Sin precio', vacio: 'Ninguna entrega espera precio', items: [
            for (final d in lista('sinPrecio'))
              ListTile(
                title: Text('${d['id']} · ${d['kg']} kg'),
                subtitle: Text('${d['farmer_id']} · ${d['delivery_date']}'),
                trailing: const Icon(Icons.price_change),
                onTap: () async {
                  if (await _abrirFormulario(context, 'precio', fijos: {'entregaId': d['id']}, subtitulo: '${d['id']} · ${d['kg']} kg')) _cargar();
                },
              ),
          ]),
          if (widget.esDueno)
            _Seccion(titulo: 'Adelantos por aprobar', vacio: 'Ningún adelanto espera aprobación', items: [
              for (final q in lista('adelantosPorAprobar'))
                ListTile(
                  title: Text('${q['party']} · ${_soles(q['amount'])}'),
                  subtitle: Text('${q['reason'] ?? ''}${q['reason'] != null ? ' · ' : ''}${q['request_date']} · ${q['created_by']}'),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    IconButton(
                      icon: Icon(Icons.close, color: Colors.red.shade600),
                      tooltip: 'Rechazar',
                      onPressed: () async {
                        if (await _abrirFormulario(context, 'rechazarAdelanto', fijos: {'solicitudId': q['id']}, subtitulo: '${q['party']} · ${_soles(q['amount'])}')) _cargar();
                      },
                    ),
                    IconButton(
                      icon: Icon(Icons.check_circle, color: Colors.green.shade700),
                      tooltip: 'Aprobar',
                      onPressed: () async {
                        if (await _abrirFormulario(context, 'aprobarAdelanto', fijos: {'solicitudId': q['id']}, subtitulo: '${q['party']} · ${_soles(q['amount'])}')) _cargar();
                      },
                    ),
                  ]),
                ),
            ]),
          _Seccion(titulo: 'Compras por pagar', vacio: 'No se debe ninguna compra', items: [
            for (final p in lista('porPagar'))
              ListTile(
                title: Text('${p['id']} · debe ${_soles(p['still_owed'])}'),
                subtitle: Text('${p['farmer_id']} · ${p['purchase_date']}'),
                trailing: widget.esDueno ? const Icon(Icons.payments) : null,
                onTap: !widget.esDueno
                    ? null
                    : () async {
                        if (await _abrirFormulario(context, 'pago', fijos: {'compraId': p['id']}, subtitulo: '${p['id']} · debe ${_soles(p['still_owed'])}')) _cargar();
                      },
              ),
          ]),
          if (widget.esDueno)
            _Seccion(titulo: 'Gastos por pagar', vacio: 'Ningún gasto espera pago', items: [
              for (final g in lista('gastosPorPagar'))
                ListTile(
                  title: Text('${g['category']} · ${_soles(g['amount'])}'),
                  subtitle: Text('${g['description'] ?? ''}${g['description'] != null ? ' · ' : ''}${g['expense_date']} · ${g['created_by']}'),
                  trailing: const Icon(Icons.payments),
                  onTap: () async {
                    if (await _abrirFormulario(context, 'pagoGasto', fijos: {'gastoId': g['id']}, subtitulo: '${g['category']} · ${_soles(g['amount'])}')) _cargar();
                  },
                ),
            ]),
          if (widget.esDueno)
            _Seccion(titulo: 'Áreas por revisar', vacio: 'Ningún gasto espera revisión', items: [
              for (final g in lista('porRevisar'))
                ListTile(
                  title: Text('${g['category']} · ${_soles(g['amount'])}'),
                  subtitle: Text('${g['description'] ?? ''}${g['description'] != null ? ' · ' : ''}${g['expense_date']} · ${g['created_by']}'
                      '${(g['suggestion'] is Map && g['suggestion']['source'] != 'to_review') ? '\nSugerido: ${_areas[g['suggestion']['area']] ?? g['suggestion']['area']}' : ''}'),
                  trailing: const Icon(Icons.rule),
                  onTap: () => _revisarArea(Map<String, dynamic>.from(g as Map)),
                ),
            ]),
          _Seccion(titulo: 'Adelantos abiertos', vacio: 'Ningún adelanto abierto', items: [
            for (final a in lista('adelantos'))
              ListTile(
                title: Text('${a['id']} · ${a['party_id']} · abierto ${_soles(a['open_balance'])}'),
                subtitle: Text('Desde ${a['advance_date']}'),
              ),
          ]),
          if (widget.esDueno)
            _Seccion(titulo: 'Banco por cruzar', vacio: 'Todo el banco está cruzado', items: [
              for (final b in lista('banco'))
                ListTile(
                  title: Text('${b['description']} · ${_soles(b['amount'])}'),
                  subtitle: Text('${b['movement_date']} · op. ${b['operation_number'] ?? '—'}'
                      '${b['suggested_payment'] != null ? ' · sugerido ${b['suggested_payment']}' : ''}'),
                ),
            ]),
        ],
      ),
    );
  }
}

class _Seccion extends StatelessWidget {
  const _Seccion({required this.titulo, required this.items, required this.vacio});
  final String titulo;
  final List<Widget> items;
  final String vacio;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text('$titulo (${items.length})', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ),
          if (items.isEmpty) Padding(padding: const EdgeInsets.fromLTRB(16, 4, 16, 12), child: Text(vacio, style: TextStyle(color: Colors.grey.shade600))),
          ...items,
        ],
      ),
    );
  }
}

class _Mensaje extends StatelessWidget {
  const _Mensaje({required this.texto, required this.onReintentar});
  final String texto;
  final VoidCallback onReintentar;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(texto, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          ElevatedButton(onPressed: onReintentar, child: const Text('Reintentar')),
        ]),
      ),
    );
  }
}

// ─── Mis solicitudes ─────────────────────────────────────────────────────────

/// Lo que cada persona registró o pidió y en qué quedó. Administración ve las de todos.
class _Solicitudes extends StatefulWidget {
  const _Solicitudes({required this.esDueno});
  final bool esDueno;

  @override
  State<_Solicitudes> createState() => _SolicitudesState();
}

class _SolicitudesState extends State<_Solicitudes> {
  List<dynamic>? _lista;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final r = await AdministracionService.solicitudes();
    if (!mounted) return;
    setState(() { _lista = (r.data?['solicitudes'] as List?) ?? []; _error = r.isSuccess ? null : r.error; });
  }

  static const _iconos = {'gasto': Icons.receipt_long, 'adelanto': Icons.handshake, 'entrega': Icons.local_shipping};
  static const _nombres = {'gasto': 'Gasto', 'adelanto': 'Adelanto', 'entrega': 'Entrega'};

  Color _color(String estado) {
    if (estado == 'Pagado' || estado == 'Pagada' || estado == 'Entregado') return Colors.green.shade700;
    if (estado == 'Rechazado') return Colors.red.shade700;
    return Colors.orange.shade800;
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) return _Mensaje(texto: _error!, onReintentar: _cargar);
    if (_lista == null) return const Center(child: CircularProgressIndicator());
    return RefreshIndicator(
      onRefresh: _cargar,
      child: _lista!.isEmpty
          ? ListView(children: const [Padding(padding: EdgeInsets.all(24), child: Text('Todavía no hay solicitudes', textAlign: TextAlign.center))])
          : ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: _lista!.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final s = _lista![i] as Map;
                final estado = '${s['status']}';
                final monto = s['amount'] == null ? '' : ' · S/ ${(num.tryParse('${s['amount']}') ?? 0).toStringAsFixed(2)}';
                return ListTile(
                  leading: Icon(_iconos[s['kind']] ?? Icons.description),
                  title: Text('${_nombres[s['kind']] ?? s['kind']}$monto'),
                  subtitle: Text([
                    '${s['description'] ?? ''}',
                    '${s['request_date']}${widget.esDueno ? ' · ${s['created_by']}' : ''}',
                    if (s['detail'] != null) '${s['detail']}',
                  ].where((t) => t.isNotEmpty).join('\n')),
                  isThreeLine: s['detail'] != null,
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: _color(estado).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                    child: Text(estado, style: TextStyle(color: _color(estado), fontWeight: FontWeight.w600, fontSize: 12)),
                  ),
                );
              },
            ),
    );
  }
}

// ─── Mi área ─────────────────────────────────────────────────────────────────

/// Los gastos del área de la persona (Administración ve todas): por mes y los últimos.
/// Dónde se recuerdan las áreas marcadas para Mi área (las mismas en Perfil y en Mi área).
const claveAreasElegidas = 'mi_area_elegidas';

/// Mi área como pantalla propia (se abre desde Perfil), con flecha para volver.
class MiAreaScreen extends StatelessWidget {
  const MiAreaScreen({super.key, this.area});
  final String? area;

  @override
  Widget build(BuildContext context) =>
      Scaffold(appBar: AppBar(title: const Text('Mi área')), body: _MiArea(inicial: area));
}

class _MiArea extends StatefulWidget {
  const _MiArea({this.inicial});
  final String? inicial;

  @override
  State<_MiArea> createState() => _MiAreaState();
}

class _MiAreaState extends State<_MiArea> {
  Map<String, dynamic>? _datos;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar(widget.inicial);
  }

  /// [area]: un área, varias separadas por coma, o "todas". La base sólo cuenta las áreas de la persona.
  Future<void> _cargar([String? area]) async {
    final r = await AdministracionService.miArea(area);
    if (!mounted) return;
    setState(() { _datos = r.data; _error = r.isSuccess ? null : r.error; });
    // Las áreas marcadas aquí son las mismas que en Perfil.
    final elegidas = r.data?['elegidas'];
    if (r.isSuccess && elegidas is List && elegidas.isNotEmpty) {
      try {
        await (await SharedPreferences.getInstance()).setStringList(claveAreasElegidas, elegidas.map((e) => '$e').toList());
      } catch (_) {}
    }
  }

  /// Marcar o desmarcar un área; siempre queda al menos una elegida.
  void _alternar(String area, Set<String> elegidas) {
    final nuevas = {...elegidas};
    if (!nuevas.remove(area)) nuevas.add(area);
    if (nuevas.isEmpty) return;
    _cargar(nuevas.join(','));
  }

  String _soles(dynamic v) => 'S/ ${(num.tryParse('${v ?? 0}') ?? 0).toStringAsFixed(2)}';

  @override
  Widget build(BuildContext context) {
    if (_error != null) return _Mensaje(texto: _error!, onReintentar: _cargar);
    if (_datos == null) return const Center(child: CircularProgressIndicator());
    final areas = (_datos!['areas'] as List? ?? []).cast<Map>();
    if (areas.isEmpty) {
      return const Center(child: Padding(
        padding: EdgeInsets.all(24),
        child: Text('Todavía no estás en ningún área. Administración te asigna una.', textAlign: TextAlign.center),
      ));
    }
    final elegidas = {...((_datos!['elegidas'] as List?) ?? [if (_datos!['area'] != null) _datos!['area']]).map((e) => '$e')};
    final todas = elegidas.length == areas.length;
    final nombres = {for (final a in areas) '${a['area']}': '${a['name']}'};
    final meses = (_datos!['meses'] as List? ?? []).cast<Map>();
    final gastos = (_datos!['gastos'] as List? ?? []).cast<Map>();
    // Un mes puede tener varias filas (una por centro de costo): se suman.
    final porMes = <String, List<num>>{};
    for (final m in meses) {
      final t = porMes.putIfAbsent('${m['month']}', () => [0, 0, 0]);
      t[0] += num.tryParse('${m['total'] ?? 0}') ?? 0;
      t[1] += num.tryParse('${m['paid'] ?? 0}') ?? 0;
      t[2] += num.tryParse('${m['to_pay'] ?? 0}') ?? 0;
    }
    return RefreshIndicator(
      onRefresh: () => _cargar(elegidas.join(',')),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Se puede ver una, varias o todas las áreas juntas (cada gasto tiene una sola área: no se cuenta dos veces).
          if (areas.length > 1) ...[
            Text('Toca para sumar o quitar áreas', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
            const SizedBox(height: 6),
            Wrap(spacing: 8, runSpacing: 8, children: [
              FilterChip(label: const Text('Todas'), selected: todas, onSelected: (_) => _cargar(todas ? '${areas.first['area']}' : 'todas')),
              for (final a in areas)
                FilterChip(
                  label: Text('${a['name']}${a['principal'] == true ? ' · principal' : ''}'),
                  selected: elegidas.contains('${a['area']}'),
                  onSelected: (_) => _alternar('${a['area']}', elegidas),
                ),
            ]),
          ],
          const SizedBox(height: 12),
          _Seccion(titulo: 'Gastos por mes', vacio: 'Sin gastos todavía', items: [
            for (final e in porMes.entries)
              ListTile(
                title: Text('${e.key.substring(0, 7)} · ${_soles(e.value[0])}'),
                subtitle: Text('Pagado ${_soles(e.value[1])} · por pagar ${_soles(e.value[2])}'),
              ),
          ]),
          _Seccion(titulo: 'Últimos gastos', vacio: 'Sin gastos todavía', items: [
            for (final g in gastos)
              ListTile(
                title: Text('${g['category']} · ${_soles(g['amount'])}'),
                subtitle: Text('${elegidas.length > 1 ? '${nombres['${g['area']}'] ?? g['area']} · ' : ''}'
                    '${g['description'] ?? ''}${g['description'] != null ? ' · ' : ''}${g['expense_date']} · ${g['created_by']}'),
                trailing: Text('${g['status']}', style: TextStyle(fontSize: 12, color: g['status'] == 'Pagado' ? Colors.green.shade700 : Colors.orange.shade800)),
              ),
          ]),
        ],
      ),
    );
  }
}

// ─── Resumen ─────────────────────────────────────────────────────────────────

class _Resumen extends StatefulWidget {
  const _Resumen({required this.esDueno});
  final bool esDueno;

  @override
  State<_Resumen> createState() => _ResumenState();
}

class _ResumenState extends State<_Resumen> {
  List<dynamic> _meses = [];
  String? _error;
  bool _verVentas = false;

  @override
  void initState() {
    super.initState();
    if (widget.esDueno) _cargar();
  }

  Future<void> _cargar() async {
    final r = await AdministracionService.resumen();
    if (!mounted) return;
    setState(() { _meses = (r.data?['meses'] as List?) ?? []; _error = r.isSuccess ? null : r.error; });
  }

  String _soles(dynamic v) => (num.tryParse('${v ?? 0}') ?? 0).toStringAsFixed(2);

  @override
  Widget build(BuildContext context) {
    // Los reportes de ventas de siempre, sin cambios.
    if (_verVentas || !widget.esDueno) {
      return Column(children: [
        if (widget.esDueno)
          Align(alignment: Alignment.centerLeft, child: TextButton.icon(onPressed: () => setState(() => _verVentas = false), icon: const Icon(Icons.arrow_back), label: const Text('Dinero del mes'))),
        const Expanded(child: ReportesTab()),
      ]);
    }
    return RefreshIndicator(
      onRefresh: _cargar,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ListTile(
            leading: const Icon(Icons.bar_chart_rounded),
            title: const Text('Reportes de ventas'),
            subtitle: const Text('Ventas por mes, por cobrar, clientes'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => setState(() => _verVentas = true),
          ),
          const Divider(),
          const Text('Dinero del mes', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!)),
          if (_error == null && _meses.isEmpty) const Padding(padding: EdgeInsets.only(top: 8), child: Text('Aún no hay movimientos')),
          for (final m in _meses)
            Card(
              child: ListTile(
                title: Text('${m['account']} · ${m['month']}'),
                subtitle: Text('Inicio ${_soles(m['opening'])} · entra ${_soles(m['money_in'])} · sale ${_soles(m['money_out'])}'),
                trailing: Text('S/ ${_soles(m['closing'])}', style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Elegir persona ──────────────────────────────────────────────────────────

/// Abre la búsqueda de personas a pantalla completa. Devuelve la persona elegida, {} si eligió "Ninguno",
/// o null si cerró sin elegir (X o deslizar a la derecha).
Future<Map<String, dynamic>?> _elegirPersona(BuildContext context,
    {required String titulo, String? rol, bool opcional = false, String? elegido}) {
  return Navigator.of(context).push<Map<String, dynamic>>(CupertinoPageRoute(
    fullscreenDialog: false,
    builder: (_) => _ElegirPersona(titulo: titulo, rol: rol, opcional: opcional, elegido: elegido),
  ));
}

class _ElegirPersona extends StatefulWidget {
  const _ElegirPersona({required this.titulo, this.rol, this.opcional = false, this.elegido});
  final String titulo;
  final String? rol;
  final bool opcional;
  final String? elegido;

  @override
  State<_ElegirPersona> createState() => _ElegirPersonaState();
}

class _ElegirPersonaState extends State<_ElegirPersona> {
  static const _porPagina = 20;
  final _scroll = ScrollController();
  final List<Map<String, dynamic>> _personas = [];
  String _busqueda = '';
  bool _cargando = false;
  bool _hayMas = true;
  String? _error;
  int _pedido = 0; // descarta respuestas viejas si la búsqueda cambió
  Timer? _espera;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 200) _cargarMas();
    });
    _cargarMas();
  }

  @override
  void dispose() {
    _espera?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  void _buscar(String texto) {
    _espera?.cancel();
    _espera = Timer(const Duration(milliseconds: 300), () {
      setState(() { _busqueda = texto.trim(); _personas.clear(); _hayMas = true; _error = null; _cargando = false; _pedido++; });
      _cargarMas();
    });
  }

  Future<void> _cargarMas() async {
    if (_cargando || !_hayMas) return;
    final pedido = _pedido;
    setState(() => _cargando = true);
    final r = await AdministracionService.buscarPersonas(q: _busqueda, rol: widget.rol, offset: _personas.length, limit: _porPagina);
    if (!mounted || pedido != _pedido) return;
    setState(() {
      _cargando = false;
      if (r.isSuccess) {
        _personas.addAll(((r.data!['personas'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)));
        _hayMas = r.data!['hayMas'] == true;
      } else {
        _error = r.error;
        _hayMas = false;
      }
    });
  }

  String? _detalle(Map<String, dynamic> p) {
    const vende = {'cherry': 'Vende cereza', 'parchment': 'Vende pergamino', 'both': 'Vende cereza y pergamino'};
    final partes = [if (p['vende'] != null) vende[p['vende']] ?? '${p['vende']}', if (p['detalle'] != null) '${p['detalle']}'];
    return partes.isEmpty ? null : partes.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.close), tooltip: 'Cerrar', onPressed: () => Navigator.of(context).pop()),
        title: Text(widget.titulo),
      ),
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => FocusScope.of(context).unfocus(),
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Buscar por nombre o apodo', border: OutlineInputBorder()),
              textInputAction: TextInputAction.search,
              onChanged: _buscar,
            ),
          ),
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              itemCount: (widget.opcional ? 1 : 0) + _personas.length + 1,
              itemBuilder: (context, i) {
                if (widget.opcional && i == 0) {
                  return ListTile(
                    leading: const Icon(Icons.remove_circle_outline),
                    title: const Text('Ninguno'),
                    onTap: () => Navigator.of(context).pop(<String, dynamic>{}),
                  );
                }
                final k = i - (widget.opcional ? 1 : 0);
                if (k == _personas.length) {
                  if (_error != null) return Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center));
                  if (_cargando || _hayMas) return const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()));
                  return Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(_personas.isEmpty ? 'Nadie con ese nombre' : '${_personas.length} en total',
                        textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade600)),
                  );
                }
                final p = _personas[k];
                final detalle = _detalle(p);
                return ListTile(
                  title: Text('${p['nombre']}'),
                  subtitle: detalle == null ? null : Text(detalle, maxLines: 1, overflow: TextOverflow.ellipsis),
                  trailing: p['id'] == widget.elegido ? Icon(Icons.check, color: Colors.blue.shade700) : null,
                  onTap: () => Navigator.of(context).pop(p),
                );
              },
            ),
          ),
        ]),
      ),
    );
  }
}
