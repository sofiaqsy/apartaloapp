part of 'administracion_tab.dart';

// ─── Registrar: tarjetas por proceso ─────────────────────────────────────────
// General Manager, 3 nov 2026: Registrar se ordena por proceso. Cada tarjeta muestra un resumen
// (lotes y café de hoy) y al entrar tiene sus acciones: Compras (café recibido, adelantos, pagar
// compras) y Producción (tostar café). Los datos vienen de la base: purchasing_summary y
// production_summary, que leen nuestros registros y los lotes y tuestes de Apartalo sin cambiarlos.

const _estadosCafe = {'parchment': 'Pergamino', 'cherry': 'Cereza', 'green': 'Verde', 'roasted': 'Tostado', 'packaged': 'Empacado'};

String _kg(dynamic v) {
  final n = (v is num) ? v.toDouble() : double.tryParse('${v ?? ''}') ?? 0;
  final s = n == n.roundToDouble() ? n.toStringAsFixed(0) : n.toStringAsFixed(1);
  return '${s.replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',')} kg';
}

String _soles(dynamic v) {
  final n = (v is num) ? v.toDouble() : double.tryParse('${v ?? ''}') ?? 0;
  return 'S/ ${n.toStringAsFixed(n == n.roundToDouble() ? 0 : 2).replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',')}';
}

String _fechaCorta(dynamic iso) {
  final d = DateTime.tryParse('${iso ?? ''}')?.toLocal();
  if (d == null) return '';
  const meses = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];
  return '${d.day} ${meses[d.month - 1]}';
}

Map<String, dynamic> _mapa(dynamic v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
List<Map<String, dynamic>> _lista(dynamic v) => v is List ? v.map(_mapa).toList() : <Map<String, dynamic>>[];

Future<T?> _abrirPantalla<T>(BuildContext context, Widget pantalla) =>
    Navigator.of(context).push<T>(CupertinoPageRoute(builder: (_) => pantalla));

class _Registrar extends StatefulWidget {
  const _Registrar({required this.esDueno});
  final bool esDueno;

  @override
  State<_Registrar> createState() => _RegistrarState();
}

class _RegistrarState extends State<_Registrar> {
  Map<String, dynamic>? _compras;
  Map<String, dynamic>? _produccion;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final r = await AdministracionService.procesos();
    if (!mounted) return;
    setState(() {
      _error = r.isSuccess ? null : r.error;
      if (r.isSuccess) {
        _compras = _mapa(r.data!['compras']);
        _produccion = _mapa(r.data!['produccion']);
      }
    });
  }

  Future<void> _entrar(Widget pantalla) async {
    final irA = await _abrirPantalla<String>(context, pantalla);
    if (!mounted) return;
    if (irA == 'pendientes') {
      DefaultTabController.of(context).animateTo(1); // se paga desde Pendientes
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Elige la compra "Por pagar"')));
    }
    _cargar();
  }

  List<String> _lineasCompras() {
    final c = _compras;
    if (c == null) return [_error ?? 'Cargando…'];
    final mes = _mapa(c['mes']);
    final sinPrecio = _mapa(c['sin_precio']);
    final porPagar = c['por_pagar'] == null ? null : _mapa(c['por_pagar']);
    final adelantos = c['adelantos'] == null ? null : _mapa(c['adelantos']);
    return [
      'Este mes: ${mes['recibidos'] ?? 0} recibidos · ${_kg(mes['kg'])}',
      if ((sinPrecio['n'] ?? 0) != 0) 'Sin precio: ${sinPrecio['n']} (${_kg(sinPrecio['kg'])})',
      if (porPagar != null && (porPagar['n'] ?? 0) != 0) 'Por pagar: ${_soles(porPagar['total'])} (${porPagar['n']})',
      if (adelantos != null && (adelantos['n'] ?? 0) != 0) 'Adelantos abiertos: ${_soles(adelantos['saldo'])} (${adelantos['n']})',
    ];
  }

  List<String> _lineasProduccion() {
    final p = _produccion;
    if (p == null) return [_error ?? 'Cargando…'];
    final lotes = _lista(p['lotes_verdes']);
    final tuestes = _lista(p['tuestes']);
    final mes = _mapa(p['mes']);
    final enCurso = tuestes.where((t) => t['estado'] == 'in_progress').length;
    return [
      'Café verde: ${_kg(p['verde_kg'])} en ${lotes.length} ${lotes.length == 1 ? 'lote' : 'lotes'}',
      if (tuestes.isNotEmpty)
        enCurso > 0 ? 'Tostando ahora: $enCurso · programados: ${tuestes.length - enCurso}' : 'Tuestes programados: ${tuestes.length}',
      'Este mes: ${mes['tuestes'] ?? 0} tuestes${mes['merma_pct'] != null ? ' · merma ${mes['merma_pct']}%' : ''}',
    ];
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _cargar,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _TarjetaProceso(
            icono: Icons.shopping_basket,
            titulo: 'Compras',
            lineas: _lineasCompras(),
            onTap: () => _entrar(_ComprasScreen(esDueno: widget.esDueno)),
          ),
          const SizedBox(height: 12),
          _TarjetaProceso(
            icono: Icons.local_fire_department,
            titulo: 'Producción',
            lineas: _lineasProduccion(),
            onTap: () => _entrar(const _ProduccionScreen()),
          ),
          const SizedBox(height: 20),
          Text('Otros', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
          const SizedBox(height: 8),
          _Acciones(acciones: [
            (Icons.receipt_long, _titulos['gasto']!, () async { if (await _abrirFormulario(context, 'gasto')) _cargar(); }),
            if (widget.esDueno)
              (Icons.account_balance_wallet, _titulos['retiro']!, () => _abrirFormulario(context, 'retiro')),
          ]),
        ],
      ),
    );
  }
}

/// Tarjeta de un proceso: título, 2 o 3 líneas de resumen y una flecha; al tocarla se entra al proceso.
class _TarjetaProceso extends StatelessWidget {
  const _TarjetaProceso({required this.icono, required this.titulo, required this.lineas, required this.onTap});
  final IconData icono;
  final String titulo;
  final List<String> lineas;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.blue.shade50,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
          child: Row(children: [
            Icon(icono, size: 34, color: Colors.blue.shade700),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(titulo, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                for (final l in lineas)
                  Text(l, style: TextStyle(fontSize: 14, color: Colors.grey.shade800), maxLines: 1, overflow: TextOverflow.ellipsis),
              ]),
            ),
            Icon(Icons.chevron_right, color: Colors.grey.shade600),
          ]),
        ),
      ),
    );
  }
}

/// Botones grandes de acción, dos por fila.
class _Acciones extends StatelessWidget {
  const _Acciones({required this.acciones});
  final List<(IconData, String, VoidCallback)> acciones;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.6,
      children: [for (final (icono, texto, onTap) in acciones) _BotonGrande(icono: icono, texto: texto, onTap: onTap)],
    );
  }
}

/// Un número con su nombre, para el resumen de arriba de cada proceso.
class _Dato extends StatelessWidget {
  const _Dato(this.valor, this.nombre);
  final String valor;
  final String nombre;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 160,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(valor, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        Text(nombre, style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
      ]),
    );
  }
}

/// Pantalla de un proceso: resumen, acciones y listas. Se carga sola y se refresca deslizando hacia abajo.
abstract class _ProcesoState<T extends StatefulWidget> extends State<T> {
  Map<String, dynamic>? datos;
  String? error;
  String get clave; // 'compras' o 'produccion'

  @override
  void initState() {
    super.initState();
    cargar();
  }

  Future<void> cargar() async {
    final r = await AdministracionService.procesos();
    if (!mounted) return;
    setState(() {
      error = r.isSuccess ? null : r.error;
      if (r.isSuccess) datos = _mapa(r.data![clave]);
    });
  }

  /// Abre un formulario; al guardar, el resumen se vuelve a cargar.
  Future<void> formulario(String form, {Map<String, dynamic> fijos = const {}, String? subtitulo}) async {
    if (await _abrirFormulario(context, form, fijos: fijos, subtitulo: subtitulo)) cargar();
  }

  Widget pantalla(String titulo, List<Widget> Function(Map<String, dynamic> d) contenido) {
    final d = datos;
    return Scaffold(
      appBar: AppBar(title: Text(titulo)),
      body: RefreshIndicator(
        onRefresh: cargar,
        child: d == null
            ? ListView(children: [
                Padding(
                  padding: const EdgeInsets.all(32),
                  child: error != null ? Text(error!, textAlign: TextAlign.center) : const Center(child: CircularProgressIndicator()),
                ),
              ])
            : ListView(padding: const EdgeInsets.all(16), children: contenido(d)),
      ),
    );
  }
}

Widget _subtitulo(String texto) => Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 6),
      child: Text(texto, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
    );

Widget _vacio(String texto) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(texto, style: TextStyle(color: Colors.grey.shade600)),
    );

// ─── Compras ─────────────────────────────────────────────────────────────────

class _ComprasScreen extends StatefulWidget {
  const _ComprasScreen({required this.esDueno});
  final bool esDueno;

  @override
  State<_ComprasScreen> createState() => _ComprasScreenState();
}

class _ComprasScreenState extends _ProcesoState<_ComprasScreen> {
  @override
  String get clave => 'compras';

  @override
  Widget build(BuildContext context) {
    return pantalla('Compras', (d) {
      final mes = _mapa(d['mes']);
      final sinPrecio = _mapa(d['sin_precio']);
      final porPagar = d['por_pagar'] == null ? null : _mapa(d['por_pagar']);
      final adelantos = d['adelantos'] == null ? null : _mapa(d['adelantos']);
      final almacen = _lista(d['almacen']);
      final recientes = _lista(d['recientes']);
      return [
        Wrap(spacing: 10, runSpacing: 10, children: [
          _Dato(_kg(mes['kg']), 'recibido este mes (${mes['recibidos'] ?? 0})'),
          _Dato('${sinPrecio['n'] ?? 0}', 'sin precio'),
          if (porPagar != null) _Dato(_soles(porPagar['total']), 'por pagar (${porPagar['n'] ?? 0})'),
          if (adelantos != null) _Dato(_soles(adelantos['saldo']), 'en adelantos (${adelantos['n'] ?? 0})'),
        ]),
        const SizedBox(height: 16),
        _Acciones(acciones: [
          (Icons.move_to_inbox, _titulos['entrega']!, () => formulario('entrega')),
          (Icons.handshake, _titulos['adelanto']!, () => formulario('adelanto')),
          if (widget.esDueno) (Icons.payments, 'Pagar compras', () => Navigator.of(context).pop('pendientes')),
          (Icons.person_add_alt_1, _titulos['proveedor']!, () => formulario('proveedor')),
          (Icons.receipt_long, 'Registrar gasto de compras',
              () => formulario('gasto', fijos: const {'area': 'sourcing'}, subtitulo: 'Área: Compras')),
        ]),
        _subtitulo('Café en almacén'),
        if (almacen.isEmpty) _vacio('No hay café de compras guardado.'),
        for (final a in almacen)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.inventory_2_outlined),
            title: Text(_estadosCafe[a['estado']] ?? '${a['estado']}'),
            subtitle: Text('${a['lotes']} ${a['lotes'] == 1 ? 'lote' : 'lotes'}'),
            trailing: Text(_kg(a['kg']), style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
        _subtitulo('Últimos recibidos'),
        if (recientes.isEmpty) _vacio('Todavía no hay café recibido.'),
        for (final r in recientes)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('${r['agricultor'] ?? 'Sin nombre'}'),
            subtitle: Text('${_fechaCorta(r['fecha'])} · ${_estadosCafe[r['estado']] ?? r['estado']} · ${_kg(r['kg'])}'),
            trailing: Text(
              r['precio'] != null ? '${_soles(r['precio'])}/kg' : (widget.esDueno ? 'Sin precio' : ''),
              style: TextStyle(color: r['precio'] != null ? Colors.black87 : Colors.orange.shade800),
            ),
          ),
      ];
    });
  }
}

// ─── Producción ──────────────────────────────────────────────────────────────

class _ProduccionScreen extends StatefulWidget {
  const _ProduccionScreen();

  @override
  State<_ProduccionScreen> createState() => _ProduccionScreenState();
}

class _ProduccionScreenState extends _ProcesoState<_ProduccionScreen> {
  @override
  String get clave => 'produccion';

  /// Tostar café: se elige el producto (el café que sale del tueste) y se programa con su lote verde.
  Future<void> _tostar() async {
    final producto = await _abrirPantalla<Map<String, dynamic>>(context, const _ElegirProducto());
    if (producto == null || !mounted) return;
    await abrirProgramarTueste(context, producto, onCreado: cargar);
    cargar();
  }

  Future<void> _iniciar(Map<String, dynamic> t) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Iniciar tueste?'),
        content: Text('Lote ${t['lote'] ?? ''} · ${_kg(t['kg_verde'])} de café verde'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Iniciar tueste')),
        ],
      ),
    );
    if (ok != true) return;
    final r = await ApiService.iniciarTueste('${t['id']}');
    _aviso(r.isSuccess ? 'Tueste iniciado ✓' : 'No se inició: ${r.error}');
    cargar();
  }

  Future<void> _finalizar(Map<String, dynamic> t) async {
    final resultado = await showDialog<(double, String)>(context: context, builder: (_) => _FinalizarTueste(tueste: t));
    if (resultado == null) return;
    final r = await ApiService.finalizarTueste('${t['id']}', resultado.$1, notas: resultado.$2);
    _aviso(r.isSuccess ? 'Tueste finalizado ✓ ${_kg(resultado.$1)} de café tostado' : 'No se finalizó: ${r.error}');
    cargar();
  }

  void _aviso(String texto) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(texto)));
  }

  @override
  Widget build(BuildContext context) {
    return pantalla('Producción', (d) {
      final lotes = _lista(d['lotes_verdes']);
      final tuestes = _lista(d['tuestes']);
      final mes = _mapa(d['mes']);
      final porProcesar = _lista(d['por_procesar']);
      return [
        Wrap(spacing: 10, runSpacing: 10, children: [
          _Dato(_kg(d['verde_kg']), 'café verde disponible'),
          _Dato(_kg(d['tostado_kg']), 'café tostado disponible'),
          _Dato('${mes['tuestes'] ?? 0}', 'tuestes este mes'),
          _Dato(mes['merma_pct'] != null ? '${mes['merma_pct']}%' : '—',
              'merma (${_kg(mes['kg_verde'])} → ${_kg(mes['kg_tostado'])})'),
        ]),
        const SizedBox(height: 16),
        _Acciones(acciones: [
          (Icons.local_fire_department, 'Tostar café', _tostar),
          (Icons.receipt_long, 'Registrar gasto de producción',
              () => formulario('gasto', fijos: const {'area': 'production'}, subtitulo: 'Área: Producción')),
        ]),
        _subtitulo('Tuestes en curso y programados'),
        if (tuestes.isEmpty) _vacio('No hay tuestes programados. Toca "Tostar café".'),
        for (final t in tuestes)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(t['estado'] == 'in_progress' ? Icons.local_fire_department : Icons.schedule,
                color: t['estado'] == 'in_progress' ? Colors.deepOrange : Colors.grey.shade700),
            title: Text('${t['producto'] ?? 'Lote ${t['lote'] ?? ''}'}'),
            subtitle: Text('Lote ${t['lote'] ?? '—'} · ${_kg(t['kg_verde'])} · ${_fechaCorta(t['fecha'])}'),
            trailing: t['estado'] == 'in_progress'
                ? ElevatedButton(onPressed: () => _finalizar(t), child: const Text('Finalizar'))
                : OutlinedButton(onPressed: () => _iniciar(t), child: const Text('Iniciar')),
          ),
        _subtitulo('Lotes de café verde'),
        if (lotes.isEmpty) _vacio('No hay lotes de café verde con stock.'),
        for (final l in lotes) _FilaLote(lote: l),
        if (porProcesar.isNotEmpty) ...[
          _subtitulo('Café comprado por procesar'),
          for (final p in porProcesar)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.inventory_2_outlined),
              title: Text(_estadosCafe[p['estado']] ?? '${p['estado']}'),
              subtitle: Text('${p['lotes']} ${p['lotes'] == 1 ? 'lote' : 'lotes'} · calidad: ${p['calidad'] == 'pending' ? 'por revisar' : p['calidad']}'),
              trailing: Text(_kg(p['kg']), style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
        ],
      ];
    });
  }
}

/// Un lote verde: código, variedad y cosecha, y cuánto queda de lo que entró.
class _FilaLote extends StatelessWidget {
  const _FilaLote({required this.lote});
  final Map<String, dynamic> lote;

  @override
  Widget build(BuildContext context) {
    final ahora = (lote['kg_ahora'] as num?)?.toDouble() ?? 0;
    final inicial = (lote['kg_inicial'] as num?)?.toDouble() ?? 0;
    final detalle = [if (lote['variedad'] != null) '${lote['variedad']}', if (lote['cosecha'] != null) 'cosecha ${lote['cosecha']}'];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('${lote['codigo']}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          if (detalle.isNotEmpty) ...[
            const SizedBox(width: 8),
            Expanded(child: Text(detalle.join(' · '), style: TextStyle(color: Colors.grey.shade700), overflow: TextOverflow.ellipsis)),
          ] else
            const Spacer(),
          Text('${_kg(ahora)} de ${_kg(inicial)}'),
        ]),
        const SizedBox(height: 6),
        LinearProgressIndicator(
          value: inicial > 0 ? (ahora / inicial).clamp(0, 1) : 0,
          minHeight: 6,
          borderRadius: BorderRadius.circular(3),
          backgroundColor: Colors.grey.shade200,
        ),
      ]),
    );
  }
}

/// Finalizar tueste: cuántos kilos de café tostado salieron, y notas.
class _FinalizarTueste extends StatefulWidget {
  const _FinalizarTueste({required this.tueste});
  final Map<String, dynamic> tueste;

  @override
  State<_FinalizarTueste> createState() => _FinalizarTuesteState();
}

class _FinalizarTuesteState extends State<_FinalizarTueste> {
  final _kgCtrl = TextEditingController();
  final _notasCtrl = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _kgCtrl.dispose();
    _notasCtrl.dispose();
    super.dispose();
  }

  void _guardar() {
    final kg = _numero(_kgCtrl.text);
    final verde = (widget.tueste['kg_verde'] as num?)?.toDouble();
    if (kg == null || kg <= 0) return setState(() => _error = 'Escribe los kilos de café tostado.');
    if (verde != null && kg > verde) return setState(() => _error = 'No puede salir más que el café verde (${_kg(verde)}).');
    Navigator.pop(context, (kg, _notasCtrl.text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Finalizar tueste'),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Lote ${widget.tueste['lote'] ?? ''} · entraron ${_kg(widget.tueste['kg_verde'])} de café verde'),
        const SizedBox(height: 12),
        TextField(
          controller: _kgCtrl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Kilos de café tostado', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 12),
        TextField(controller: _notasCtrl, decoration: const InputDecoration(labelText: 'Notas (opcional)', border: OutlineInputBorder())),
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: const TextStyle(color: Colors.red))),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        ElevatedButton(onPressed: _guardar, child: const Text('Finalizar tueste')),
      ],
    );
  }
}

/// "1,000.50", "1000,50" y "1000.5" valen lo mismo.
double? _numero(String texto) {
  var t = texto.trim().replaceAll(' ', '');
  if (t.contains(',') && t.contains('.')) {
    t = t.lastIndexOf(',') > t.lastIndexOf('.') ? t.replaceAll('.', '').replaceAll(',', '.') : t.replaceAll(',', '');
  } else {
    t = t.replaceAll(',', '.');
  }
  return double.tryParse(t);
}

/// Elegir el producto que sale del tueste: buscar por nombre, de 20 en 20, X para cerrar sin elegir.
class _ElegirProducto extends StatefulWidget {
  const _ElegirProducto();

  @override
  State<_ElegirProducto> createState() => _ElegirProductoState();
}

class _ElegirProductoState extends State<_ElegirProducto> {
  static const _porPagina = 20;
  final _scroll = ScrollController();
  final List<Map<String, dynamic>> _productos = [];
  String _busqueda = '';
  int _pagina = 0;
  bool _cargando = false;
  bool _hayMas = true;
  String? _error;
  int _pedido = 0;
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
      setState(() { _busqueda = texto.trim(); _productos.clear(); _pagina = 0; _hayMas = true; _error = null; _cargando = false; _pedido++; });
      _cargarMas();
    });
  }

  Future<void> _cargarMas() async {
    if (_cargando || !_hayMas) return;
    final pedido = _pedido;
    setState(() => _cargando = true);
    final r = await ApiService.getProductos(buscar: _busqueda.isEmpty ? null : _busqueda, pagina: _pagina + 1, limite: _porPagina);
    if (!mounted || pedido != _pedido) return;
    setState(() {
      _cargando = false;
      if (r.isSuccess && r.data != null) {
        _productos.addAll(r.data!.productos);
        _pagina++;
        _hayMas = r.data!.hayMas;
      } else {
        _error = r.error ?? 'No se pudieron cargar los productos.';
        _hayMas = false;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.close), tooltip: 'Cerrar', onPressed: () => Navigator.of(context).pop()),
        title: const Text('¿Qué café vas a tostar?'),
      ),
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => FocusScope.of(context).unfocus(),
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Buscar producto', border: OutlineInputBorder()),
              textInputAction: TextInputAction.search,
              onChanged: _buscar,
            ),
          ),
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              itemCount: _productos.length + 1,
              itemBuilder: (context, i) {
                if (i == _productos.length) {
                  if (_error != null) return Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center));
                  if (_cargando || _hayMas) return const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()));
                  return Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(_productos.isEmpty ? 'Ningún producto con ese nombre' : '${_productos.length} en total',
                        textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade600)),
                  );
                }
                final p = _productos[i];
                return ListTile(
                  title: Text('${p['nombre'] ?? ''}'),
                  subtitle: p['estado'] != null ? Text('${p['estado']}', maxLines: 1) : null,
                  trailing: const Icon(Icons.chevron_right),
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
