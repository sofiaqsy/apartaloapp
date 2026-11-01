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
      length: 3,
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
            tabs: const [Tab(text: 'Registrar'), Tab(text: 'Pendientes'), Tab(text: 'Resumen')],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _Registrar(esDueno: _esDueno),
                _Pendientes(esDueno: _esDueno),
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
      {this.opciones = const {}, this.requerido = true, this.filtroPersona, this.visibleSi, this.porDefecto, this.ayuda, this.avanzado = false});
  /// Campo poco usado: va dentro de "Más opciones" para que el formulario sea corto.
  final bool avanzado;
  final String clave;
  final String etiqueta;
  final _Tipo tipo;
  final Map<String, String> opciones; // valor -> texto
  final bool requerido;
  final bool Function(Map<String, dynamic> persona)? filtroPersona;
  final bool Function(Map<String, dynamic> valores)? visibleSi;
  final dynamic porDefecto;
  final String? ayuda;
}

const _metodosPago = {'transfer': 'Transferencia', 'yape': 'Yape', 'plin': 'Plin', 'cash': 'Efectivo'};
bool _necesitaOperacion(Map<String, dynamic> v, [String clave = 'metodo']) => v[clave] != null && v[clave] != 'cash';
final _campoOperacion = _Campo('operacion', 'Número de operación', _Tipo.texto,
    visibleSi: _necesitaOperacion, ayuda: 'Para cruzarlo solo con el banco');

final Map<String, List<_Campo>> _formularios = {
  'gasto': [
    const _Campo('monto', 'Monto (S/)', _Tipo.monto),
    const _Campo('categoria', 'Categoría', _Tipo.opcion, opciones: {
      'Transporte': 'Transporte', 'Operativo': 'Operativo', 'Gas': 'Gas', 'Finca': 'Finca', 'Mantenimiento': 'Mantenimiento',
      'Servicios': 'Servicios', 'Insumos': 'Insumos', 'Personal': 'Personal', 'Otro': 'Otro',
    }),
    const _Campo('metodo', 'Cómo se pagó', _Tipo.opcion, opciones: _metodosPago, porDefecto: 'transfer'),
    _campoOperacion,
    const _Campo('descripcion', 'Descripción', _Tipo.texto, requerido: false),
    const _Campo('centro', 'Área', _Tipo.opcion, opciones: {'coffee': 'Café', 'farm': 'Finca'}, porDefecto: 'coffee', avanzado: true),
    const _Campo('fecha', 'Fecha', _Tipo.fecha, avanzado: true),
  ],
  'adelanto': [
    _Campo('personaId', 'Para', _Tipo.persona, filtroPersona: (p) => p['agricultor'] == true || p['comprador'] == true),
    const _Campo('monto', 'Monto (S/)', _Tipo.monto, ayuda: 'Máximo S/ 2,000 y uno abierto por persona'),
    const _Campo('devuelveEn', 'Se devuelve en', _Tipo.opcion, opciones: {'coffee': 'Café', 'money': 'Dinero', 'coffee_or_money': 'Café o dinero'}, porDefecto: 'coffee'),
    const _Campo('metodo', 'Cómo se entregó', _Tipo.opcion, opciones: _metodosPago, porDefecto: 'transfer'),
    _campoOperacion,
    const _Campo('notas', 'Notas', _Tipo.texto, requerido: false),
    const _Campo('fecha', 'Fecha', _Tipo.fecha, avanzado: true),
  ],
  'entrega': [
    _Campo('agricultorId', 'Agricultor', _Tipo.persona, filtroPersona: (p) => p['agricultor'] == true),
    _Campo('compradorId', 'Recogido por (comprador)', _Tipo.persona, requerido: false, filtroPersona: (p) => p['comprador'] == true),
    const _Campo('estado', 'Café', _Tipo.opcion, opciones: {'parchment': 'Pergamino', 'cherry': 'Cereza', 'green': 'Verde'}, porDefecto: 'parchment'),
    const _Campo('kg', 'Kilos', _Tipo.numero),
    const _Campo('precioKg', 'Precio por kilo (si ya se sabe)', _Tipo.monto, requerido: false),
    const _Campo('humedad', 'Humedad %', _Tipo.numero, requerido: false, avanzado: true),
    const _Campo('rendimiento', 'Factor de rendimiento', _Tipo.numero, requerido: false, avanzado: true),
    _Campo('metodoPago', 'Pago del saldo ahora', _Tipo.opcion, requerido: false, opciones: _metodosPago,
        visibleSi: (v) => v['precioKg'] != null),
    _Campo('operacion', 'Número de operación', _Tipo.texto,
        visibleSi: (v) => v['precioKg'] != null && _necesitaOperacion(v, 'metodoPago'), ayuda: 'Para cruzarlo solo con el banco'),
    const _Campo('notas', 'Notas', _Tipo.texto, requerido: false),
    const _Campo('fecha', 'Fecha', _Tipo.fecha, avanzado: true),
  ],
  'precio': [
    const _Campo('precioKg', 'Precio por kilo', _Tipo.monto),
    const _Campo('metodoPago', 'Pago del saldo ahora', _Tipo.opcion, requerido: false, opciones: _metodosPago),
    _Campo('operacion', 'Número de operación', _Tipo.texto, visibleSi: (v) => _necesitaOperacion(v, 'metodoPago'), ayuda: 'Para cruzarlo solo con el banco'),
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

const _titulos = {
  'gasto': 'Gasto', 'adelanto': 'Adelanto', 'entrega': 'Entrega de café', 'precio': 'Poner precio',
  'pago': 'Pagar compra', 'ingreso': 'Ingreso de dinero', 'retiro': 'Retiro a caja',
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
  List<Map<String, dynamic>> _personas = [];
  bool _guardando = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    for (final c in _campos) {
      if (c.porDefecto != null) _valores[c.clave] = c.porDefecto;
      if (c.tipo == _Tipo.fecha) _valores[c.clave] = DateTime.now();
    }
    if (_campos.any((c) => c.tipo == _Tipo.persona)) {
      AdministracionService.personas().then((r) {
        if (mounted && r.isSuccess) setState(() => _personas = r.data!);
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
    final datos = <String, dynamic>{...widget.fijos};
    for (final c in _visibles) {
      final v = _valores[c.clave];
      if (v == null || v == '') continue;
      datos[c.clave] = v is DateTime ? v.toIso8601String().substring(0, 10) : v;
    }
    setState(() { _guardando = true; _error = null; });
    final r = await AdministracionService.registrar(widget.formulario, datos, clave: _clave);
    if (!mounted) return;
    if (r.isSuccess) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${_titulos[widget.formulario]} guardado ✓')));
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
        return '${c.etiqueta}: ${v == null ? '—' : (c.opciones[v] ?? v)}';
      }).join(' · ');

  Widget _campo(_Campo c) {
    final deco = InputDecoration(labelText: c.requerido ? c.etiqueta : '${c.etiqueta} (opcional)', helperText: c.ayuda, border: const OutlineInputBorder());
    void poner(dynamic v) => setState(() => _valores[c.clave] = v);
    switch (c.tipo) {
      case _Tipo.opcion:
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
                for (final e in c.opciones.entries)
                  ChoiceChip(
                    label: Text(e.value),
                    selected: _valores[c.clave] == e.key,
                    onSelected: (sel) {
                      FocusScope.of(context).unfocus();
                      final v = sel ? e.key : (c.requerido ? e.key : null);
                      poner(v);
                      if (widget.formulario == 'gasto' && c.clave == 'categoria') {
                        setState(() => _valores['centro'] = (v == 'Finca' || v == 'Personal') ? 'farm' : 'coffee');
                      }
                    },
                  ),
              ],
            ),
            if (c.ayuda != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(c.ayuda!, style: TextStyle(fontSize: 12, color: Colors.grey.shade600))),
          ],
        );
      case _Tipo.persona:
        final lista = _personas.where((p) => c.filtroPersona == null || c.filtroPersona!(p)).toList();
        return DropdownButtonFormField<String>(
          value: _valores[c.clave] as String?,
          decoration: deco,
          isExpanded: true,
          items: [
            if (!c.requerido) const DropdownMenuItem<String>(value: null, child: Text('—')),
            for (final p in lista) DropdownMenuItem(value: p['id'] as String, child: Text(p['nombre']?.toString() ?? p['id'].toString())),
          ],
          onChanged: (v) {
            poner(v);
            if (widget.formulario == 'entrega' && c.clave == 'agricultorId') {
              final p = _personas.firstWhere((x) => x['id'] == v, orElse: () => {});
              if (p['recogidoPor'] != null) setState(() => _valores['compradorId'] = p['recogidoPor']);
            }
          },
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
    final botones = <(String, IconData, String)>[
      ('gasto', Icons.receipt_long, 'Gasto'),
      ('entrega', Icons.local_shipping, 'Entrega de café'),
      ('adelanto', Icons.handshake, esDueno ? 'Adelanto' : 'Adelanto (sólo dueño)'),
      ('pago', Icons.payments, 'Pagar compra'),
      ('ingreso', Icons.savings, 'Ingreso de dinero'),
      ('retiro', Icons.account_balance_wallet, 'Retiro a caja'),
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
            habilitado: form != 'adelanto' || esDueno,
            onTap: () async {
              if (form == 'pago') {
                DefaultTabController.of(context).animateTo(1); // se paga desde "Por pagar"
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Elige la compra en "Por pagar"')));
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
          _Seccion(titulo: 'Por pagar', vacio: 'No se debe ninguna compra', items: [
            for (final p in lista('porPagar'))
              ListTile(
                title: Text('${p['id']} · debe ${_soles(p['still_owed'])}'),
                subtitle: Text('${p['farmer_id']} · ${p['purchase_date']}'),
                trailing: const Icon(Icons.payments),
                onTap: () async {
                  if (await _abrirFormulario(context, 'pago', fijos: {'compraId': p['id']}, subtitulo: '${p['id']} · debe ${_soles(p['still_owed'])}')) _cargar();
                },
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
