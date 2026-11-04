part of 'administracion_tab.dart';

// ─── Procesos (antes Registrar): tarjetas por proceso ───────────────────────
// General Manager, 3 nov 2026: Registrar se ordena por proceso. Cada tarjeta muestra un resumen
// (lotes y café de hoy) y al entrar tiene sus acciones: Compras (compras, adelantos, pagar
// compras) y Producción (tostar café). Los datos vienen de la base: purchasing_summary y
// production_summary, que leen nuestros registros y los lotes y tuestes de Apartalo sin cambiarlos.

/// Estados de una compra (General Manager, 3 nov 2026, tras la reunión con Compras, Finanzas, Calidad y TI).
const _coloresCompra = {
  'Sin precio': Colors.orange,
  // Lo que todavía se debe va en naranja, igual que Pendiente en Finanzas (General Manager, 3 nov 2026).
  'Por pagar': Colors.orange,
  'Pago solicitado': Colors.indigo, // Compras tocó "Solicitar pago": espera a Finanzas
  'Pagado en parte': Colors.orange,
  'Pagado': Colors.green,
  'Rechazado': Colors.red,
};
const _decisiones = {
  'accepted': 'Aceptado',
  'accepted_with_discount': 'Aceptado con descuento',
  'rejected': 'Rechazado',
  'on_hold': 'En espera',
};

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

/// Las mismas áreas que Perfil marca: las guardadas que son de la persona; sin nada guardado, la principal.
/// (Los dueños sin áreas asignadas tienen todas.) null si no se pudo leer.
Future<Set<String>?> _areasMarcadas() async {
  final r = await AdministracionService.miArea();
  List<String> guardadas = [];
  try {
    guardadas = (await SharedPreferences.getInstance()).getStringList(claveAreasElegidas) ?? [];
  } catch (_) {}
  if (!r.isSuccess) return null;
  final todas = ((r.data!['areas'] as List?) ?? []).map(_mapa).toList();
  final asignadas = todas.where((a) => a['role'] == 'lead' || a['role'] == 'member').toList();
  final mias = asignadas.isNotEmpty ? asignadas : todas;
  final validas = mias.map((a) => '${a['area']}').toSet();
  final elegidas = guardadas.where(validas.contains).toSet();
  if (elegidas.isEmpty && mias.isNotEmpty) {
    elegidas.add('${mias.firstWhere((a) => a['principal'] == true, orElse: () => mias.first)['area']}');
  }
  return elegidas;
}

Future<T?> _abrirPantalla<T>(BuildContext context, Widget pantalla) => Navigator.of(context).push<T>(CupertinoPageRoute(builder: (_) => pantalla));

class _Registrar extends StatefulWidget {
  const _Registrar({required this.esDueno});
  final bool esDueno;

  @override
  State<_Registrar> createState() => _RegistrarState();
}

class _RegistrarState extends State<_Registrar> {
  Map<String, dynamic>? _finca;
  Map<String, dynamic>? _compras;
  Map<String, dynamic>? _produccion;
  Map<String, dynamic>? _comercial;
  Map<String, dynamic>? _logistica;
  Map<String, dynamic>? _finanzas;
  String? _error;
  Set<String>? _areas; // las áreas marcadas en Perfil; null mientras carga
  bool _cargado = false; // ya llegaron los resúmenes (hasta entonces cada tarjeta muestra su carga)

  @override
  void initState() {
    super.initState();
    cambioDeAreas.addListener(_leerAreas);
    _cargar();
  }

  @override
  void dispose() {
    cambioDeAreas.removeListener(_leerAreas);
    super.dispose();
  }

  Future<void> _leerAreas() async {
    final m = await _areasMarcadas();
    if (mounted && m != null) setState(() => _areas = m);
  }

  Future<void> _cargar() async {
    _leerAreas();
    final r = await AdministracionService.procesos();
    if (!mounted) return;
    setState(() {
      _error = r.isSuccess ? null : r.error;
      if (r.isSuccess) {
        _cargado = true;
        // El servidor sólo manda los procesos de las áreas de la persona; los que faltan quedan en null.
        Map<String, dynamic>? de(String k) => r.data![k] is Map ? _mapa(r.data![k]) : null;
        _finca = de('finca');
        _compras = de('compras');
        _produccion = de('produccion');
        _comercial = de('comercial');
        _logistica = de('logistica');
        // Finanzas es dinero: sólo para dueños (la base responde "solo_duenos" a los demás).
        final fin = de('finanzas');
        _finanzas = fin == null || fin['solo_duenos'] == true ? null : fin;
      }
    });
  }

  Future<void> _entrar(Widget pantalla) async {
    await _abrirPantalla<String>(context, pantalla);
    if (!mounted) return;
    _cargar();
  }

  @override
  Widget build(BuildContext context) {
    // Una tarjeta por proceso, en el orden que pidió la General Manager (3 nov 2026): Comercialización,
    // Producción, Compras y Finca al final.
    // Registrar gasto y el retiro de efectivo están dentro de cada proceso (General Manager, 3 nov 2026).
    // Sólo se ven las de las áreas marcadas en Perfil → Mis áreas (General Manager, 3 nov 2026).
    final tarjetas = <(String, Object?, Widget)>[
      (
        'commercial',
        _comercial,
        _TarjetaProceso(
          titulo: 'Comercialización',
          indicadores: _comercial == null ? null : _indicadoresComercial(_comercial!),
          error: _error,
          onTap: () => _entrar(const _ComercialScreen()),
        )
      ),
      (
        'production',
        _produccion,
        _TarjetaProceso(
          titulo: 'Producción',
          indicadores: _produccion == null ? null : _indicadoresProduccion(_produccion!),
          error: _error,
          onTap: () => _entrar(const _ProduccionScreen()),
        )
      ),
      (
        'sourcing',
        _compras,
        _TarjetaProceso(
          titulo: 'Compras',
          indicadores: _compras == null ? null : _indicadoresCompras(_compras!, widget.esDueno),
          error: _error,
          onTap: () => _entrar(_ComprasScreen(esDueno: widget.esDueno)),
        )
      ),
      (
        'fulfillment',
        _logistica,
        _TarjetaProceso(
          titulo: 'Logística',
          indicadores: _logistica == null ? null : _indicadoresLogistica(_logistica!, widget.esDueno),
          error: _error,
          onTap: () => _entrar(_LogisticaScreen(esDueno: widget.esDueno)),
        )
      ),
      (
        'farm',
        _finca,
        _TarjetaProceso(
          titulo: 'Finca',
          indicadores: _finca == null ? null : _indicadoresFinca(_finca!, widget.esDueno),
          error: _error,
          onTap: () => _entrar(_FincaScreen(esDueno: widget.esDueno)),
        )
      ),
      (
        'finance',
        _finanzas,
        _TarjetaProceso(
          titulo: 'Finanzas',
          indicadores: _finanzas == null ? null : _indicadoresFinanzas(_finanzas!),
          error: _error,
          onTap: () => _entrar(const _FinanzasScreen()),
        )
      ),
    ];
    final areas = _areas;
    // Marcada en Perfil y, ya cargado, con datos del servidor (que no manda procesos de áreas ajenas).
    final visibles = areas == null
        ? <Widget>[]
        : [
            for (final (area, datos, t) in tarjetas)
              if (areas.contains(area) && (!_cargado || datos != null)) t
          ];
    return RefreshIndicator(
      onRefresh: _cargar,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (areas == null)
            const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
          else if (visibles.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Tus áreas marcadas no tienen tarjeta aquí. Marca Finca, Compras, Producción o Comercial en Perfil → Mis áreas.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade700),
              ),
            ),
          for (final (i, t) in visibles.indexed) ...[if (i > 0) const SizedBox(height: 10), t],
        ],
      ),
    );
  }
}

/// Un dato de un proceso: ícono, valor grande, nombre y una nota corta. [atencion] lo marca en naranja
/// sólo cuando alguien tiene que hacer algo (por ejemplo café sin precio).
/// [tono] es el color propio del dato (siempre el mismo para ese dato, no dice si es bueno o malo).
class _Indicador {
  const _Indicador(this.icono, this.valor, this.nombre, {this.nota, this.atencion = false, this.tono = Colors.blue});
  final MaterialColor tono;
  final IconData icono;
  final String valor;
  final String nombre;
  final String? nota;
  final bool atencion;
}

const _meses = ['enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', 'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre'];

/// Finca: siempre 4. Dueños: gastos del mes, por pagar, gastos del año y cosecha del año.
/// El equipo no ve dinero: cuántos gastos, parcelas, actividades del mes y cosecha.
List<_Indicador> _indicadoresFinca(Map<String, dynamic> f, bool esDueno) {
  final mes = _mapa(f['gastos_mes']);
  final anio = _mapa(f['gastos_anio']);
  final cosecha = _mapa(f['cosecha']);
  final nMes = (mes['n'] as num?)?.toInt() ?? 0;
  final gastos = (int n) => '$n ${n == 1 ? 'gasto' : 'gastos'}';
  final cosechaInd =
      _Indicador(Icons.agriculture, _kg(cosecha['kg']), 'Cosecha', tono: Colors.green, nota: 'cereza · ${cosecha['anio'] ?? DateTime.now().year}');
  if (esDueno && mes['total'] != null) {
    final porPagar = (_mapa(f['por_pagar'])['total'] as num?) ?? 0;
    return [
      _Indicador(Icons.receipt_long, _soles(mes['total']), 'Gastos este mes',
          tono: Colors.orange, nota: '${_meses[DateTime.now().month - 1]} · ${gastos(nMes)}'),
      _Indicador(Icons.account_balance_wallet, _soles(porPagar), 'Por pagar',
          tono: Colors.blue, atencion: porPagar > 0, nota: porPagar > 0 ? 'gastos de finca' : 'todo pagado'),
      _Indicador(Icons.calendar_month, _soles(anio['total']), 'Gastos en el año',
          tono: Colors.purple, nota: '${DateTime.now().year} · ${gastos((anio['n'] as num?)?.toInt() ?? 0)}'),
      cosechaInd,
    ];
  }
  final parcelas = _mapa(f['parcelas']);
  final nAct = (f['actividades_mes'] as num?)?.toInt() ?? 0;
  return [
    _Indicador(Icons.receipt_long, '$nMes', 'Gastos este mes', tono: Colors.orange, nota: 'registrados'),
    cosechaInd,
    _Indicador(Icons.landscape, '${parcelas['n'] ?? 0}', 'Parcelas', tono: Colors.brown, nota: '${parcelas['hectareas'] ?? 0} ha'),
    _Indicador(Icons.event_note, '$nAct', 'Labores del mes', tono: Colors.blue, nota: 'en las parcelas'),
  ];
}

/// Compras: siempre 4. Dueños: lo recibido, lo que falta precio, lo que se debe y los adelantos.
/// El equipo no ve dinero: en su lugar, el café en almacén y el último recibido.
List<_Indicador> _indicadoresCompras(Map<String, dynamic> c, bool esDueno) {
  final mes = _mapa(c['mes']);
  final sinPrecio = _mapa(c['sin_precio']);
  final nRecibidos = (mes['recibidos'] as num?)?.toInt() ?? 0;
  final nSinPrecio = (sinPrecio['n'] as num?)?.toInt() ?? 0;
  // Comprado: sólo el café que no se rechazó (General Manager, 3 nov 2026).
  final rechazados = (c['rechazados_mes'] as num?)?.toInt() ?? 0;
  final recibido = _Indicador(Icons.move_to_inbox, _kg(mes['kg']), 'Comprado',
      tono: Colors.green,
      nota: '${_meses[DateTime.now().month - 1]} · $nRecibidos ${nRecibidos == 1 ? 'compra' : 'compras'}'
          '${rechazados > 0 ? ' · $rechazados ${rechazados == 1 ? 'rechazada' : 'rechazadas'}' : ''}');
  final precio = _Indicador(Icons.sell_outlined, '$nSinPrecio', 'Sin precio',
      tono: Colors.orange, nota: nSinPrecio == 0 ? 'todo con precio' : _kg(sinPrecio['kg']), atencion: nSinPrecio > 0);
  if (esDueno && c['por_pagar'] != null) {
    final porPagar = _mapa(c['por_pagar']);
    final adelantos = _mapa(c['adelantos']);
    final nPagar = (porPagar['n'] as num?)?.toInt() ?? 0;
    final nAdel = (adelantos['n'] as num?)?.toInt() ?? 0;
    return [
      recibido,
      _Indicador(Icons.account_balance_wallet, _soles(porPagar['total']), 'Por pagar',
          tono: Colors.blue, nota: '$nPagar ${nPagar == 1 ? 'compra' : 'compras'}', atencion: nPagar > 0),
      _Indicador(Icons.handshake, _soles(adelantos['saldo']), 'Adelantos abiertos',
          tono: Colors.purple, nota: '$nAdel ${nAdel == 1 ? 'persona' : 'personas'}'),
    ];
  }
  final almacen = _lista(c['almacen']);
  final kgAlmacen = almacen.fold<double>(0, (t, a) => t + ((a['kg'] as num?)?.toDouble() ?? 0));
  return [
    recibido,
    precio,
    _Indicador(Icons.inventory_2_outlined, _kg(kgAlmacen), 'En almacén',
        tono: Colors.brown, nota: almacen.map((a) => _estadosCafe[a['estado']] ?? '${a['estado']}').join(', ')),
    _Indicador(Icons.event, c['ultimo'] == null ? '—' : _fechaCorta(c['ultimo']), 'Última compra', tono: Colors.blue),
  ];
}

/// Producción: siempre 4. Café tostado, café verde, lotes de tostado del mes y merma.
List<_Indicador> _indicadoresProduccion(Map<String, dynamic> p) {
  final lotes = _lista(p['lotes_verdes']);
  final tuestes = _lista(p['tuestes']);
  final mes = _mapa(p['mes']);
  final enCurso = tuestes.where((t) => t['estado'] == 'in_progress').length;
  final programados = tuestes.length - enCurso;
  return [
    // Primero el tostado, luego el verde (General Manager, 3 nov 2026).
    _Indicador(Icons.coffee, _kg(p['tostado_kg']), 'Café tostado', tono: Colors.orange, nota: 'disponible'),
    _Indicador(Icons.eco, _kg(p['verde_kg']), 'Café verde', tono: Colors.green, nota: '${lotes.length} ${lotes.length == 1 ? 'lote' : 'lotes'}'),
    _Indicador(Icons.local_fire_department, '${mes['tuestes'] ?? 0}', 'Lotes de tostado este mes', // antes "Tuestes" (General Manager, 4 nov 2026)
        tono: Colors.blue,
        nota: enCurso > 0 ? '$enCurso tostando ahora' : (programados > 0 ? '$programados programados' : 'ninguno programado'),
        atencion: enCurso > 0),
    _Indicador(Icons.trending_down, mes['merma_pct'] != null ? '${mes['merma_pct']}%' : '—', 'Merma',
        tono: Colors.red, nota: '${_kg(mes['kg_verde'])} → ${_kg(mes['kg_tostado'])}'),
  ];
}

/// Logística: siempre 4. Primero lo que hay que despachar y lo entregado en el mes (pedidos de la tienda);
/// luego, dueños: gastos del mes y por pagar; equipo: en camino y cuántos gastos.
List<_Indicador> _indicadoresLogistica(Map<String, dynamic> l, bool esDueno) {
  int n(dynamic v) => (v as num?)?.toInt() ?? 0;
  final despachar = n(l['por_despachar']);
  final camino = n(l['en_camino']);
  final mes = _mapa(l['gastos_mes']);
  String pedidos(int k) => '$k ${k == 1 ? 'pedido' : 'pedidos'}';
  final primeros = [
    _Indicador(Icons.outbox, pedidos(despachar), 'Por despachar',
        tono: Colors.orange, atencion: despachar > 0, nota: camino > 0 ? '$camino en camino' : 'de la tienda'),
    _Indicador(Icons.local_shipping, pedidos(n(l['entregados_mes'])), 'Entregados', tono: Colors.green, nota: _meses[DateTime.now().month - 1]),
  ];
  if (esDueno && mes['total'] != null) {
    final porPagar = (_mapa(l['por_pagar'])['total'] as num?) ?? 0;
    return [
      ...primeros,
      _Indicador(Icons.receipt_long, _soles(mes['total']), 'Gastos este mes',
          tono: Colors.purple, nota: '${n(mes['n'])} ${n(mes['n']) == 1 ? 'gasto' : 'gastos'} · flete, empaque'),
      _Indicador(Icons.account_balance_wallet, _soles(porPagar), 'Por pagar',
          tono: Colors.blue, atencion: porPagar > 0, nota: porPagar > 0 ? 'gastos de logística' : 'todo pagado'),
    ];
  }
  return [
    ...primeros,
    _Indicador(Icons.route, pedidos(camino), 'En camino', tono: Colors.blue, nota: 'enviados'),
    _Indicador(Icons.receipt_long, '${n(mes['n'])}', 'Gastos este mes', tono: Colors.purple, nota: 'registrados'),
  ];
}

/// Finanzas (sólo dueños): siempre 4. Primero todo lo que espera pago y los adelantos por aprobar.
List<_Indicador> _indicadoresFinanzas(Map<String, dynamic> f) {
  final compras = _mapa(f['compras']);
  final gastos = _mapa(f['gastos']);
  final adelantos = _mapa(f['adelantos']);
  num v(Map m) => (m['total'] as num?) ?? num.tryParse('${m['total']}') ?? 0;
  int n(Map m) => (m['n'] as num?)?.toInt() ?? 0;
  String cuantos(int k, String uno, String varios) => '$k ${k == 1 ? uno : varios}';
  final porPagar = v(compras) + v(gastos);
  return [
    _Indicador(Icons.payments, _soles(porPagar), 'Por pagar',
        tono: Colors.blue, atencion: porPagar > 0, nota: '${cuantos(n(compras), 'compra', 'compras')} · ${cuantos(n(gastos), 'gasto', 'gastos')}'),
    _Indicador(Icons.handshake, _soles(v(adelantos)), 'Adelantos por aprobar',
        tono: Colors.purple, atencion: n(adelantos) > 0, nota: cuantos(n(adelantos), 'solicitud', 'solicitudes')),
    _Indicador(Icons.shopping_bag, _soles(v(compras)), 'Compras por pagar',
        tono: Colors.green,
        nota: '${cuantos(n(compras), 'solicitada', 'solicitadas')}'
            '${((f['sin_solicitar'] as num?) ?? 0) > 0 ? ' · ${f['sin_solicitar']} sin solicitar' : ''}'),
    _Indicador(Icons.receipt_long, _soles(v(gastos)), 'Gastos por pagar', tono: Colors.orange, nota: cuantos(n(gastos), 'gasto', 'gastos')),
  ];
}

/// Comercialización: siempre 4, de las ventas de la tienda por mes (pedidos no cancelados).
/// "Por cobrar" no va aquí: el estado de pago de los pedidos en la base no coincide con el reporte;
/// la lista de clientes por cobrar está dentro, en el reporte de ventas.
List<_Indicador> _indicadoresComercial(Map<String, dynamic> c) {
  final meses = _lista(c['meses']);
  final hoy = DateTime.now();
  String clave(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}';
  Map<String, dynamic> mes(DateTime d) => meses.firstWhere((m) => '${m['month']}'.startsWith(clave(d)), orElse: () => <String, dynamic>{});
  num n(dynamic v) => v is num ? v : num.tryParse('${v ?? ''}') ?? 0;
  final actual = mes(hoy);
  final anterior = mes(DateTime(hoy.year, hoy.month - 1));
  final pedidos = n(actual['orders']);
  final anio = meses.where((m) => '${m['month']}'.startsWith('${hoy.year}-'));
  final pedidosAnio = anio.fold<num>(0, (t, m) => t + n(m['orders']));
  String plural(num k) => '$k ${k == 1 ? 'pedido' : 'pedidos'}';
  return [
    _Indicador(Icons.point_of_sale, _soles(n(actual['total'])), 'Vendido este mes',
        tono: Colors.green, nota: '${_meses[hoy.month - 1]} · ${plural(pedidos)}'),
    _Indicador(Icons.history, _soles(n(anterior['total'])), 'Mes anterior',
        tono: Colors.blue, nota: '${_meses[DateTime(hoy.year, hoy.month - 1).month - 1]} · ${plural(n(anterior['orders']))}'),
    _Indicador(Icons.receipt, pedidos > 0 ? _soles((n(actual['total']) / pedidos).round()) : '—', 'Ticket promedio',
        tono: Colors.purple, nota: 'por pedido este mes'),
    _Indicador(Icons.calendar_month, _soles(anio.fold<num>(0, (t, m) => t + n(m['total']))), 'En el año',
        tono: Colors.orange, nota: '${hoy.year} · ${plural(pedidosAnio)}'),
  ];
}

/// Tarjeta de un proceso (estándar, General Manager 3 nov 2026): el nombre y una flecha, y siempre 4 datos
/// en dos filas. Toda la tarjeta abre el proceso.
class _TarjetaProceso extends StatelessWidget {
  const _TarjetaProceso({required this.titulo, required this.indicadores, required this.onTap, this.error});
  final String titulo;
  final List<_Indicador>? indicadores; // null mientras carga
  final VoidCallback onTap;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final datos = indicadores;
    return Material(
      color: Colors.blue.shade50,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 8, 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(titulo, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold))),
              Icon(Icons.chevron_right, color: Colors.grey.shade700),
            ]),
            const SizedBox(height: 6),
            if (datos == null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: error != null ? Text(error!) : const Center(child: CircularProgressIndicator()),
              )
            else
              // En la tarjeta sólo los 2 más importantes (General Manager, 3 nov 2026); los 4 están dentro.
              _CuatroDatos(indicadores: datos.take(2).toList()),
          ]),
        ),
      ),
    );
  }
}

/// Los 4 datos en una cuadrícula de 2 x 2. En la tarjeta van en cajas blancas; arriba de la pantalla
/// del proceso ([grande]) cada caja lleva el color propio del dato.
class _CuatroDatos extends StatelessWidget {
  const _CuatroDatos({required this.indicadores, this.grande = false});
  final List<_Indicador> indicadores;
  final bool grande;

  @override
  Widget build(BuildContext context) {
    // La información se ve como información, no como botones (General Manager, 3 nov 2026): nada de cajas
    // por dato, sólo líneas finas entre ellos. En la tarjeta, toda la tarjeta es el único botón; en la pantalla
    // del proceso, los 4 van en un solo panel gris que no se toca.
    final linea = grande ? Colors.grey.shade300 : Colors.blue.shade100;
    final filas = <Widget>[];
    for (var i = 0; i < indicadores.length; i += 2) {
      if (i > 0) filas.add(Divider(height: 1, thickness: 1, color: linea));
      filas.add(IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(child: _DatoCaja(indicadores[i], grande: grande)),
          VerticalDivider(width: 17, thickness: 1, color: linea),
          Expanded(child: i + 1 < indicadores.length ? _DatoCaja(indicadores[i + 1], grande: grande) : const SizedBox()),
        ]),
      ));
    }
    if (!grande) return Column(children: filas);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(16)),
      child: Column(children: filas),
    );
  }
}

class _DatoCaja extends StatelessWidget {
  const _DatoCaja(this.d, {this.grande = false});
  final _Indicador d;
  final bool grande;

  @override
  Widget build(BuildContext context) {
    final color = grande ? d.tono.shade700 : (d.atencion ? Colors.orange.shade800 : Colors.blue.shade700);
    final valorColor = d.atencion ? Colors.orange.shade800 : Colors.black87;
    // Sin caja ni sombra: el ícono lleva el color propio del dato y nada invita a tocarlo.
    return Padding(
      padding: EdgeInsets.symmetric(vertical: grande ? 10 : 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(padding: const EdgeInsets.only(top: 2), child: Icon(d.icono, size: grande ? 22 : 20, color: color)),
        const SizedBox(width: 8),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(d.valor, style: TextStyle(fontSize: grande ? 21 : 18, height: 1.15, fontWeight: FontWeight.bold, color: valorColor)),
            ),
            Text(d.nombre, style: TextStyle(fontSize: 13, height: 1.2, color: Colors.grey.shade800), maxLines: 1, overflow: TextOverflow.ellipsis),
            if (d.nota != null && d.nota!.isNotEmpty)
              Text(d.nota!, style: TextStyle(fontSize: 12, height: 1.2, color: Colors.grey.shade600), maxLines: 1, overflow: TextOverflow.ellipsis),
          ]),
        ),
      ]),
    );
  }
}

/// Botones de acción del proceso: todos del mismo tamaño, dos por fila (General Manager, 3 nov 2026).
class _Acciones extends StatelessWidget {
  const _Acciones({required this.acciones});
  final List<(IconData, String, VoidCallback)> acciones;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 2.3,
      children: [
        for (final (icono, texto, onTap) in acciones)
          Material(
            color: Colors.blue.shade50,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Row(children: [
                  Icon(icono, size: 24, color: Colors.blue.shade700),
                  const SizedBox(width: 8),
                  Expanded(
                    child:
                        Text(texto, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600), maxLines: 2, overflow: TextOverflow.ellipsis),
                  ),
                ]),
              ),
            ),
          ),
      ],
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
    final r = await AdministracionService.procesos(solo: clave);
    if (!mounted) return;
    setState(() {
      error = r.isSuccess ? null : r.error;
      if (r.isSuccess && r.data![clave] is! Map) error = 'Este proceso no es de tus áreas.';
      if (r.isSuccess && r.data![clave] is Map) datos = _mapa(r.data![clave]);
    });
  }

  /// Abre un formulario; al guardar, el resumen se vuelve a cargar.
  Future<void> formulario(String form, {Map<String, dynamic> fijos = const {}, String? subtitulo, Map<String, dynamic> iniciales = const {}}) async {
    if (await _abrirFormulario(context, form, fijos: fijos, subtitulo: subtitulo, iniciales: iniciales)) cargar();
  }

  Widget pantalla(String titulo, List<Widget> Function(Map<String, dynamic> d) contenido, {VoidCallback? alFinal, Widget? botonFlotante}) {
    final d = datos;
    return Scaffold(
      appBar: AppBar(title: Text(titulo)),
      floatingActionButton: botonFlotante,
      body: NotificationListener<ScrollNotification>(
        // Cerca del final de la lista se pide la página siguiente (listas largas, como los proveedores).
        onNotification: (n) {
          if (alFinal != null && n.metrics.extentAfter < 300) alFinal();
          return false;
        },
        child: RefreshIndicator(
          onRefresh: cargar,
          child: d == null
              ? ListView(children: [
                  Padding(
                    padding: const EdgeInsets.all(32),
                    child: error != null ? Text(error!, textAlign: TextAlign.center) : const Center(child: CircularProgressIndicator()),
                  ),
                ])
              : ListView(
                  // Con botón flotante, espacio al final para que no tape la última fila.
                  padding: EdgeInsets.fromLTRB(16, 16, 16, botonFlotante == null ? 16 : 88),
                  children: contenido(d)),
        ),
      ),
    );
  }
}

Widget _vacio(String texto) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(texto, style: TextStyle(color: Colors.grey.shade600)),
    );

// ─── Partes de la pantalla de un proceso ─────────────────────────────────────
// Estándar (General Manager, 3 nov 2026, de su ejemplo de Producción): los 4 datos con su color, dos
// botones grandes con la acción principal, pestañas para las listas, y cada fila es una ficha blanca.

/// Pestañas debajo de las acciones: el texto elegido en azul y subrayado.
class _Pestanas extends StatelessWidget {
  const _Pestanas({required this.nombres, required this.elegida, required this.onElegir, this.anchoPorNombre = false});
  final List<String> nombres;
  /// Cada pestaña tan ancha como su nombre, para que un nombre largo ("Lotes de tostado") se lea sin achicarse (4 nov 2026).
  final bool anchoPorNombre;
  final int elegida;
  final ValueChanged<int> onElegir;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 8), // menos espacio bajo los botones (General Manager, 4 nov 2026)
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.grey.shade300))),
      child: Row(children: [
        for (final (i, n) in nombres.indexed)
          Expanded(
            flex: anchoPorNombre ? (n.length < 6 ? 6 : n.length) : 1,
            child: InkWell(
              onTap: () => onElegir(i),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: i == elegida ? Colors.blue.shade700 : Colors.transparent, width: 3)),
                ),
                // Si no cabe, el texto se achica un poco en vez de cortarse.
                child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(n,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        style: TextStyle(
                          fontSize: nombres.length > 3 ? 14 : 16, // cuatro pestañas caben en una línea del iPhone
                          fontWeight: FontWeight.w600,
                          color: i == elegida ? Colors.blue.shade700 : Colors.grey.shade600,
                        ))),
              ),
            ),
          ),
      ]),
    );
  }
}

/// Título de la lista con cuántos hay a la derecha ("6 lotes").
Widget _encabezado(String titulo, String cuenta) => Padding(
      padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
      child: Row(children: [
        Expanded(child: Text(titulo, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
        Text(cuenta, style: TextStyle(fontSize: 15, color: Colors.grey.shade700)),
      ]),
    );

/// Una etiqueta corta en una caja de color (el código del lote, la fecha).
class _Insignia extends StatelessWidget {
  const _Insignia(this.texto, {this.tono = Colors.blue});
  final String texto;
  final MaterialColor tono;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 48),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(color: tono.shade50, borderRadius: BorderRadius.circular(10)),
      child: Text(texto, textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold, color: tono.shade800)),
    );
  }
}

/// La misma caja de color que [_Insignia], con un ícono en vez de texto.
class _InsigniaIcono extends StatelessWidget {
  const _InsigniaIcono(this.icono, {this.tono = Colors.blue});
  final IconData icono;
  final MaterialColor tono;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 48,
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(color: tono.shade50, borderRadius: BorderRadius.circular(10)),
      child: Icon(icono, color: tono.shade700),
    );
  }
}

/// Un número o estado corto en una píldora de color (76 %, Sin precio).
class _Pildora extends StatelessWidget {
  const _Pildora(this.texto, this.tono);
  final String texto;
  final MaterialColor tono;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: tono.shade50, borderRadius: BorderRadius.circular(20)),
      child: Text(texto,
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: tono.shade800), maxLines: 1, overflow: TextOverflow.ellipsis),
    );
  }
}

/// Ficha blanca de una fila. Sin flecha: las filas de estas listas no abren otra pantalla.
class _Ficha extends StatelessWidget {
  const _Ficha({required this.inicio, required this.titulo, this.detalle, this.fin, this.onTap});
  final Widget inicio;
  final String titulo;
  final String? detalle;
  final Widget? fin;
  final VoidCallback? onTap; // con acción: ficha blanca y flecha; sin acción: fila simple con una línea debajo

  @override
  Widget build(BuildContext context) {
    final fila = Row(children: [
      inicio,
      const SizedBox(width: 12),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(titulo, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
          if (detalle != null)
            Text(detalle!, style: TextStyle(fontSize: 13, color: Colors.grey.shade700), maxLines: 2, overflow: TextOverflow.ellipsis),
        ]),
      ),
      // La etiqueta siempre pegada a la derecha, junto a la flecha (General Manager, 3 nov 2026); el texto toma el
      // resto. Nunca más de 150 de ancho, así no empuja la fila fuera de la pantalla.
      if (fin != null) ...[
        const SizedBox(width: 8),
        ConstrainedBox(constraints: const BoxConstraints(maxWidth: 150), child: fin!),
      ],
      if (onTap != null) Icon(Icons.chevron_right, color: Colors.grey.shade600),
    ]);
    // Lo que no se toca no parece botón (General Manager, 3 nov 2026): sin caja blanca, sólo una línea fina.
    if (onTap == null) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.grey.shade200))),
        child: fila,
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 12, 6, 12),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.grey.shade300)),
            child: fila,
          ),
        ),
      ),
    );
  }
}

/// Lista de proveedores de un proceso dentro de su pantalla: buscar por nombre o apodo, de 20 en 20 desde el
/// servidor al llegar al final, con su carga. Compras: los agricultores que venden café; Finca y Producción: los
/// proveedores de su área (General Manager, 3 nov 2026).
mixin _ProveedoresDelProceso<T extends StatefulWidget> on State<T> {
  String? get rolProveedores => null;
  String? get areaProveedores => null;
  String get vacioProveedores => 'Todavía no hay proveedores de este proceso.';

  // Proveedores: de 20 en 20 desde el servidor, con búsqueda por nombre o apodo (como el buscador de personas).
  static const _porPagina = 20;
  final List<Map<String, dynamic>> _proveedores = [];
  String _busqueda = '';
  bool _cargandoProv = false;
  bool _hayMasProv = true;
  int? _totalProv;
  String? _errorProv;
  int _pedidoProv = 0; // descarta respuestas viejas si la búsqueda cambió
  Timer? _espera;

  @override
  void dispose() {
    _espera?.cancel();
    super.dispose();
  }

  /// Primera página al abrir la pestaña.
  void abrirProveedores() {
    if (_proveedores.isEmpty && _hayMasProv && !_cargandoProv) masProveedores();
  }

  void _buscarProveedor(String texto) {
    _espera?.cancel();
    _espera = Timer(const Duration(milliseconds: 300), () {
      setState(() {
        _busqueda = texto.trim();
        _proveedores.clear();
        _hayMasProv = true;
        _totalProv = null;
        _errorProv = null;
        _cargandoProv = false;
        _pedidoProv++;
      });
      masProveedores();
    });
  }

  Future<void> masProveedores() async {
    if (_cargandoProv || !_hayMasProv) return;
    final pedido = _pedidoProv;
    setState(() => _cargandoProv = true);
    final r = await AdministracionService.buscarPersonas(
        q: _busqueda, rol: rolProveedores, area: areaProveedores, offset: _proveedores.length, limit: _porPagina);
    if (!mounted || pedido != _pedidoProv) return;
    setState(() {
      _cargandoProv = false;
      if (r.isSuccess) {
        _proveedores.addAll(((r.data!['personas'] as List?) ?? []).map(_mapa));
        _hayMasProv = r.data!['hayMas'] == true;
        _totalProv = (r.data!['total'] as num?)?.toInt();
      } else {
        _errorProv = r.error;
        _hayMasProv = false;
      }
    });
  }

  String _queEs(Map<String, dynamic> p) {
    const vende = {'cherry': 'vende cereza', 'parchment': 'vende pergamino', 'both': 'vende cereza y pergamino'};
    final partes = [
      if (p['agricultor'] == true) 'Agricultor${p['vende'] != null ? ' · ${vende[p['vende']] ?? p['vende']}' : ''}',
      if (p['comprador'] == true) 'Comprador',
      if (p['agricultor'] != true && p['comprador'] != true) 'Proveedor',
      if (p['recogidoPorNombre'] != null) 'lo recoge ${p['recogidoPorNombre']}',
      if ((p['detalle'] ?? '').toString().isNotEmpty) '${p['detalle']}',
    ];
    return partes.join(' · ');
  }

  String _inicialesProv(String nombre) =>
      nombre.trim().split(RegExp(r'\s+')).where((x) => x.isNotEmpty).take(2).map((x) => x[0].toUpperCase()).join();

  List<Widget> _listaProveedores() => [
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: TextField(
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Buscar por nombre o apodo', border: OutlineInputBorder()),
            textInputAction: TextInputAction.search,
            onChanged: _buscarProveedor,
          ),
        ),
        _encabezado('Proveedores', _totalProv == null ? '' : '$_totalProv'),
        for (final p in _proveedores)
          _Ficha(
            inicio: _Insignia(_inicialesProv('${p['nombre'] ?? ''}'), tono: p['agricultor'] == true ? Colors.green : Colors.blue),
            titulo: '${p['nombre'] ?? 'Sin nombre'}',
            detalle: _queEs(p),
            // Cada proveedor abre su detalle (General Manager, 3 nov 2026).
            onTap: () => _abrirPantalla<void>(context, _ProveedorDetalleScreen(id: '${p['id']}')),
          ),
        if (_errorProv != null)
          Padding(padding: const EdgeInsets.all(16), child: Text(_errorProv!, textAlign: TextAlign.center))
        else if (_cargandoProv || _hayMasProv)
          const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()))
        else if (_proveedores.isEmpty)
          _vacio(_busqueda.isEmpty ? vacioProveedores : 'Nadie con ese nombre.'),
      ];
}

// ─── Logística ───────────────────────────────────────────────────────────────

class _LogisticaScreen extends StatefulWidget {
  const _LogisticaScreen({required this.esDueno});
  final bool esDueno;

  @override
  State<_LogisticaScreen> createState() => _LogisticaScreenState();
}

class _LogisticaScreenState extends _ProcesoState<_LogisticaScreen> with _ProveedoresDelProceso {
  int _pestana = 0; // 0 Por despachar, 1 Proveedores

  @override
  String get clave => 'logistica';
  @override
  String? get areaProveedores => 'fulfillment';
  @override
  String get vacioProveedores => 'Todavía no hay proveedores de logística (empaque, transporte).';

  static const _estados = {'pending': 'Pendiente', 'confirmed': 'Confirmado', 'preparing': 'Preparando', 'shipped': 'En camino'};

  @override
  Widget build(BuildContext context) {
    return pantalla('Logística', alFinal: () {
      if (_pestana == 1) masProveedores();
    }, (d) {
      final pedidos = _lista(d['pedidos']);
      final abiertos = (d['abiertos'] as num?)?.toInt() ?? pedidos.length;
      return [
        _CuatroDatos(indicadores: _indicadoresLogistica(d, widget.esDueno), grande: true), // los mismos 4 de la tarjeta
        const SizedBox(height: 16),
        _Acciones(acciones: [
          (
            Icons.receipt_long,
            _titulos['gasto']!, // el mismo nombre en cada proceso; el área va fija (General Manager, 3 nov 2026)
            () => formulario('gasto', fijos: const {'area': 'fulfillment'}, subtitulo: 'Área: Logística')
          ),
        ]),
        _Pestanas(
          nombres: const ['Por despachar', 'Proveedores'],
          elegida: _pestana,
          onElegir: (i) {
            setState(() => _pestana = i);
            if (i == 1) abrirProveedores();
          },
        ),
        if (_pestana == 1)
          ..._listaProveedores()
        else ...[
          // Los más antiguos primero: son los siguientes por despachar. A lo más 30; el total a la derecha.
          _encabezado('Pedidos abiertos', '$abiertos ${abiertos == 1 ? 'pedido' : 'pedidos'}'),
          if (pedidos.isEmpty) _vacio('No hay pedidos por despachar.'),
          for (final p in pedidos)
            _Ficha(
              inicio: _Insignia(_fechaCorta(p['fecha']), tono: p['estado'] == 'shipped' ? Colors.blue : Colors.orange),
              titulo: '${p['cliente'] ?? 'Sin nombre'}',
              detalle: 'Pedido ${p['numero'] ?? ''}',
              fin: _Pildora(_estados[p['estado']] ?? '${p['estado']}', p['estado'] == 'shipped' ? Colors.blue : Colors.orange),
            ),
        ],
      ];
    });
  }
}

// ─── Finanzas ────────────────────────────────────────────────────────────────

/// Finanzas paga lo que piden las otras áreas (General Manager, 3 nov 2026): compras con precio, gastos, y
/// aprueba los adelantos. Cada fila abre su pago (transferencia por defecto; el número de operación llega solo
/// con el archivo del BCP). Sólo dueños.
class _FinanzasScreen extends StatefulWidget {
  const _FinanzasScreen();

  @override
  State<_FinanzasScreen> createState() => _FinanzasScreenState();
}

class _FinanzasScreenState extends _ProcesoState<_FinanzasScreen> {
  int _pestana = 0; // 0 Compras, 1 Gastos, 2 Adelantos

  @override
  String get clave => 'finanzas';

  // Cada pestaña: lo que espera (Pendiente o Urgente) y lo del último mes, de 20 en 20 desde el servidor
  // (General Manager, 3 nov 2026). Se pide recién al abrir la pestaña.
  static const _tipos = ['compras', 'gastos', 'adelantos'];
  final _filas = [<Map<String, dynamic>>[], <Map<String, dynamic>>[], <Map<String, dynamic>>[]];
  final _cargando = [false, false, false];
  final _hayMas = [true, true, true];
  final _errores = <String?>[null, null, null];
  int _vuelta = 0; // al recargar, las respuestas viejas se descartan

  /// Recarga el resumen y vuelve a empezar las listas (después de pagar, aprobar o subir evidencia).
  @override
  Future<void> cargar() async {
    _vuelta++;
    for (var i = 0; i < 3; i++) {
      _filas[i].clear();
      _cargando[i] = false;
      _hayMas[i] = true;
      _errores[i] = null;
    }
    await Future.wait([super.cargar(), _mas(_pestana)]);
  }

  Future<void> _mas(int i) async {
    if (_cargando[i] || !_hayMas[i]) return;
    _cargando[i] = true;
    final vuelta = _vuelta;
    final r = await AdministracionService.finanzasLista(_tipos[i], offset: _filas[i].length);
    if (!mounted || vuelta != _vuelta) return;
    setState(() {
      _cargando[i] = false;
      if (r.isSuccess) {
        _filas[i].addAll(_lista(r.data!['filas']));
        _hayMas[i] = r.data!['hayMas'] == true;
      } else {
        _errores[i] = r.error;
        _hayMas[i] = false;
      }
    });
  }

  static const _coloresEstado = {
    'Urgente': Colors.red,
    'Pendiente': Colors.orange,
    'Pagado': Colors.green,
    'Pagado en parte': Colors.orange, // el mismo color que Pendiente: todavía se debe (General Manager, 3 nov 2026)
    'Aprobado': Colors.green,
    'Rechazado': Colors.grey,
  };
  static bool _espera(Map<String, dynamic> f) => f['estado'] == 'Pendiente' || f['estado'] == 'Urgente';
  static _Pildora _estado(Map<String, dynamic> f) => _Pildora('${f['estado'] ?? ''}', _coloresEstado[f['estado']] ?? Colors.grey);
  static String? _diasEsperando(Map<String, dynamic> f) {
    final d = (f['espera'] as num?)?.toInt();
    if (d == null || !_espera(f)) return null;
    return d == 0 ? 'pedido hoy' : (d == 1 ? 'espera 1 día' : 'espera $d días');
  }

  static int _nEvidencias(Map<String, dynamic> f) => (f['evidencias'] as num?)?.toInt() ?? 0;
  static String _textoEvidencias(Map<String, dynamic> f) => _nEvidencias(f) == 1 ? '1 evidencia' : '${_nEvidencias(f)} evidencias';

  /// Tocar una fila abre su detalle (General Manager, 3 nov 2026); debajo, lo que se puede hacer: pagar o aprobar
  /// (sólo si espera), Subir evidencia y Ver evidencia. Al volver, si algo cambió, Finanzas se recarga.
  Future<void> _detalle(String tipo, Map<String, dynamic> f) async {
    final espera = _espera(f);
    final datos = <(String, String?)>[
      ('Estado', '${f['estado'] ?? ''}${_diasEsperando(f) != null ? ' · ${_diasEsperando(f)}' : ''}'),
      if (tipo == 'purchase') ...[
        ('Agricultor', f['agricultor']?.toString()),
        ('Compra', '${f['id']} · ${_kg(f['kg'])}'),
        if (espera) ('Pidieron pagar', _soles(f['monto'] ?? f['debe'])),
        if (espera) ('Cómo', f['metodo'] == 'advance' ? 'Con el adelanto ${f['adelanto']}' : 'Transferencia'),
        if (espera) ('Pidió', f['por']?.toString()),
        if (espera) ('Nota', f['nota']?.toString()),
        ('Total', _soles(f['total'])),
        ('Pagado', _soles(f['pagado'])),
        if (((f['de_adelantos'] as num?) ?? 0) > 0) ('De adelantos', _soles(f['de_adelantos'])),
        ('Falta pagar', _soles(f['debe'])),
        (espera ? 'Pedido el' : 'Último pago', _fechaCorta(f['fecha'])),
      ] else if (tipo == 'expense') ...[
        ('Monto', _soles(f['monto'])),
        ('Categoría', f['categoria']?.toString()),
        ('Descripción', f['descripcion']?.toString()),
        ('Área', f['area'] == null ? null : '${_areas[f['area']] ?? f['area']}${f['revisar'] == true ? ' (por revisar)' : ''}'),
        ('Fecha', _fechaCorta(f['fecha'])),
        ('Registrado por', f['por']?.toString()),
        ('Pagado el', f['pagado_el'] == null ? null : _fechaCorta(f['pagado_el'])),
        ('Cómo se pagó', f['metodo'] == null ? null : (_metodosPago[f['metodo']] ?? '${f['metodo']}')),
        ('Pagado por', f['pagado_por']?.toString()),
        ('Código', '${f['id']}'),
      ] else ...[
        ('Para', f['para']?.toString()),
        ('Monto', _soles(f['monto'])),
        ('Motivo', f['motivo']?.toString()),
        ('Devuelve en', f['devuelve'] == null ? null : (_devuelveEn[f['devuelve']] ?? '${f['devuelve']}')),
        ('Fecha', _fechaCorta(f['fecha'])),
        ('Pidió', f['por']?.toString()),
        ('Adelanto entregado', f['adelanto']?.toString()),
        ('Decidido el', f['decidido_el'] == null ? null : _fechaCorta(f['decidido_el'])),
        ('Decidido por', f['decidido_por']?.toString()),
        ('Motivo del rechazo', f['motivo_rechazo']?.toString()),
        ('Código', '${f['id']}'),
      ],
    ];
    // Lo que espera se paga o se decide desde aquí; true si se guardó (entonces el detalle se cierra).
    final acciones = <(IconData, String, Future<bool> Function(BuildContext))>[
      if (espera && tipo == 'purchase')
        f['metodo'] == 'advance'
            ? (Icons.savings_outlined, 'Pagar con el adelanto', (ctx) => _confirmarConAdelanto(ctx, f))
            : (
                Icons.payments_outlined,
                _titulos['pago']!,
                (ctx) => _pagar(ctx, 'pago', 'purchase', '${f['id']}',
                    fijos: {'compraId': f['id']},
                    subtitulo: '${f['agricultor'] ?? f['id']} · pidieron ${_soles(f['monto'] ?? f['debe'])}',
                    iniciales: {if (f['monto'] != null) 'monto': f['monto']})
              ),
      if (espera && tipo == 'expense')
        (
          Icons.payments_outlined,
          _titulos['pagoGasto']!,
          (ctx) =>
              _pagar(ctx, 'pagoGasto', 'expense', '${f['id']}', fijos: {'gastoId': f['id']}, subtitulo: '${f['categoria']} · ${_soles(f['monto'])}')
        ),
      // Antes estaba en Pendientes, que se quitó (General Manager, 4 nov 2026).
      if (tipo == 'expense' && f['revisar'] == true) (Icons.help_outline, 'Elegir para qué fue', (ctx) => _elegirParaQue(ctx, f)),
      if (espera && tipo == 'advance_request') ...[
        (
          Icons.check_circle_outline,
          'Aprobar y entregar',
          (ctx) => _pagar(ctx, 'aprobarAdelanto', 'advance_request', '${f['id']}',
              fijos: {'solicitudId': f['id']}, subtitulo: '${f['para'] ?? ''} · ${_soles(f['monto'])}')
        ),
        (
          Icons.cancel_outlined,
          'Rechazar',
          (ctx) => _abrirFormulario(ctx, 'rechazarAdelanto', fijos: {'solicitudId': f['id']}, subtitulo: '${f['para'] ?? ''}')
        ),
      ],
    ];
    var cambio = false;
    await _abrirPantalla<void>(
        context,
        _FinanzaDetalleScreen(
          titulo: switch (tipo) {
            'purchase' => 'Compra · ${f['agricultor'] ?? ''}',
            'expense' => '${f['categoria'] ?? 'Gasto'}',
            _ => 'Adelanto · ${f['para'] ?? ''}',
          },
          datos: datos,
          acciones: acciones,
          tipo: tipo,
          id: '${f['id']}',
          evidencias: _nEvidencias(f),
          entrega: tipo == 'purchase' ? f['entrega']?.toString() : null,
          onCambio: () => cambio = true,
        ));
    if (cambio && mounted) cargar();
  }

  /// Paga (o aprueba) y, si se guardó, ofrece subir la evidencia del pago en el momento. true si se guardó.
  Future<bool> _pagar(BuildContext ctx, String form, String tipo, String id,
      {required Map<String, dynamic> fijos, required String subtitulo, Map<String, dynamic> iniciales = const {}}) async {
    if (!await _abrirFormulario(ctx, form, fijos: fijos, subtitulo: subtitulo, iniciales: iniciales) || !ctx.mounted) return false;
    final subir = await showDialog<bool>(
      context: ctx,
      builder: (d) => AlertDialog(
        title: const Text('¿Subir la evidencia?'),
        content: const Text('Una foto del voucher o del recibo, para tenerla con el pago.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Después')),
          ElevatedButton(onPressed: () => Navigator.pop(d, true), child: const Text('Subir evidencia')),
        ],
      ),
    );
    if (subir == true && ctx.mounted) await _subirEvidencia(ctx, tipo, id);
    return true;
  }

  /// Administración dice para qué fue el gasto (la base no pudo saberlo): queda como corrección; el gasto no se cambia.
  Future<bool> _elegirParaQue(BuildContext ctx, Map<String, dynamic> g) async {
    final eleccion = await showModalBottomSheet<String>(
      context: ctx,
      builder: (s) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
              title: Text('${g['categoria']} · ${_soles(g['monto'])}', style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: const Text('¿Para qué fue?')),
          for (final e in _paraQueCombustible.entries.where((e) => e.key != 'otro'))
            ListTile(title: Text(e.value.$1), subtitle: Text(_areas[e.value.$2] ?? e.value.$2), onTap: () => Navigator.pop(s, e.key)),
        ]),
      ),
    );
    if (eleccion == null || !ctx.mounted) return false;
    final p = _paraQueCombustible[eleccion]!;
    final r = await AdministracionService.registrar('corregirArea', {'gastoId': g['id'], 'area': p.$2, 'centro': p.$3, 'motivo': p.$1},
        clave: AdministracionService.nuevaClave('corregirArea'));
    if (!ctx.mounted) return false;
    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(r.isSuccess ? 'Área corregida ✓ ${_areas[p.$2]}' : (r.error ?? 'No se guardó'))));
    return r.isSuccess;
  }

  /// Pagar con adelanto no mueve dinero: Finanzas confirma y la base descuenta el adelanto (revisando el saldo otra vez).
  Future<bool> _confirmarConAdelanto(BuildContext ctx, Map<String, dynamic> c) async {
    final ok = await showDialog<bool>(
      context: ctx,
      builder: (d) => AlertDialog(
        title: const Text('¿Pagar con el adelanto?'),
        content: Text('${c['agricultor'] ?? ''}: ${_soles(c['monto'])} del adelanto ${c['adelanto']}. No sale dinero del banco.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancelar')),
          ElevatedButton(onPressed: () => Navigator.pop(d, true), child: const Text('Confirmar')),
        ],
      ),
    );
    if (ok != true || !ctx.mounted) return false;
    final r = await AdministracionService.registrar('pagoConAdelanto', {'solicitudId': c['solicitud']},
        clave: AdministracionService.nuevaClave('pagoConAdelanto'));
    if (!ctx.mounted) return false;
    final res = r.data ?? const {};
    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
        content: Text(r.isSuccess
            ? 'Pagado con el adelanto ✓ ${_soles(res['amount'])} · al adelanto le queda ${_soles(res['advance_left'])}'
            : (r.error ?? 'No se guardó'))));
    return r.isSuccess;
  }

  @override
  Widget build(BuildContext context) {
    return pantalla('Finanzas', alFinal: () => _mas(_pestana), (d) {
      if (d['solo_duenos'] == true) return [_vacio('Finanzas es sólo para los dueños.')];
      int n(String k) => (_mapa(d[k])['n'] as num?)?.toInt() ?? 0;
      final filas = _filas[_pestana];
      return [
        _CuatroDatos(indicadores: _indicadoresFinanzas(d), grande: true),
        const SizedBox(height: 16),
        _Acciones(acciones: [
          (Icons.account_balance_wallet, _titulos['retiro']!, () => formulario('retiro')),
          (Icons.receipt_long, _titulos['gasto']!, () => formulario('gasto', fijos: const {'area': 'finance'}, subtitulo: 'Área: Finanzas')),
        ]),
        // El número de cada pestaña es lo que espera; la lista también trae lo del último mes.
        _Pestanas(
          nombres: ['Compras (${n('compras')})', 'Gastos (${n('gastos')})', 'Adelantos (${n('adelantos')})'],
          elegida: _pestana,
          onElegir: (i) {
            setState(() => _pestana = i);
            if (_filas[i].isEmpty) _mas(i);
          },
        ),
        const SizedBox(height: 12),
        for (final f in filas)
          if (_pestana == 0) _filaCompra(f) else if (_pestana == 1) _filaGasto(f) else _filaAdelanto(f),
        if (_errores[_pestana] != null)
          Padding(padding: const EdgeInsets.all(16), child: Text(_errores[_pestana]!, textAlign: TextAlign.center))
        else if (_cargando[_pestana] || _hayMas[_pestana])
          const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()))
        else if (filas.isEmpty)
          _vacio(const [
            'Ninguna compra pidió pago en el último mes.',
            'No hay gastos en el último mes.',
            'No hay adelantos en el último mes.'
          ][_pestana]),
      ];
    });
  }

  // Sólo las compras con "Solicitar pago" o pagadas el último mes; las demás esperan en Compras.
  Widget _filaCompra(Map<String, dynamic> c) {
    final espera = _espera(c);
    final monto = espera ? (c['monto'] ?? c['debe']) : c['total'];
    return _Ficha(
      inicio: _Insignia(_fechaCorta(c['fecha']), tono: Colors.green),
      titulo: '${c['agricultor'] ?? 'Sin nombre'}',
      detalle: [
        '${_soles(monto)} · ${c['id']} · ${_kg(c['kg'])}',
        if (espera) c['metodo'] == 'advance' ? 'con el adelanto ${c['adelanto']}' : 'por transferencia',
        if (_diasEsperando(c) != null) _diasEsperando(c)!,
        if (espera && ((c['pagado'] as num?) ?? 0) > 0) 'pagado ${_soles(c['pagado'])}',
        if (!espera && ((c['debe'] as num?) ?? 0) > 0) 'falta ${_soles(c['debe'])}',
        if ((c['nota'] ?? '').toString().isNotEmpty) '${c['nota']}',
        if (_nEvidencias(c) > 0) _textoEvidencias(c),
      ].join(' · '),
      fin: _estado(c),
      onTap: () => _detalle('purchase', c),
    );
  }

  Widget _filaGasto(Map<String, dynamic> g) {
    final espera = _espera(g);
    return _Ficha(
      inicio: _Insignia(_fechaCorta(g['fecha']), tono: Colors.orange),
      titulo: '${g['categoria'] ?? 'Gasto'}',
      detalle: [
        _soles(g['monto']),
        if ((g['descripcion'] ?? '').toString().isNotEmpty) '${g['descripcion']}',
        if (g['area'] != null) '${_areas[g['area']] ?? g['area']}${g['revisar'] == true ? ' por revisar' : ''}',
        if (_diasEsperando(g) != null) _diasEsperando(g)!,
        if (!espera && g['pagado_el'] != null) 'pagado el ${_fechaCorta(g['pagado_el'])}',
        if (_nEvidencias(g) > 0) _textoEvidencias(g),
      ].join(' · '),
      fin: _estado(g),
      onTap: () => _detalle('expense', g),
    );
  }

  Widget _filaAdelanto(Map<String, dynamic> a) {
    return _Ficha(
      inicio: _Insignia(_fechaCorta(a['fecha']), tono: Colors.purple),
      titulo: '${a['para'] ?? 'Sin nombre'}',
      detalle: [
        _soles(a['monto']),
        if ((a['motivo'] ?? '').toString().isNotEmpty) '${a['motivo']}',
        if (a['por'] != null) 'pidió ${a['por']}',
        if (_diasEsperando(a) != null) _diasEsperando(a)!,
        if (a['estado'] == 'Aprobado' && a['adelanto'] != null) '${a['adelanto']}',
        if (_nEvidencias(a) > 0) _textoEvidencias(a),
      ].join(' · '),
      fin: _estado(a),
      onTap: () => _detalle('advance_request', a),
    );
  }
}

/// Detalle de una fila de Finanzas (compra, gasto o adelanto): sólo información y, debajo, lo que se puede hacer:
/// pagar o decidir (si espera), Subir evidencia y Ver evidencia (General Manager, 3 nov 2026).
class _FinanzaDetalleScreen extends StatefulWidget {
  const _FinanzaDetalleScreen({
    required this.titulo,
    required this.datos,
    required this.acciones,
    required this.tipo,
    required this.id,
    required this.evidencias,
    required this.onCambio,
    this.entrega,
  });
  final String titulo;
  final List<(String, String?)> datos;
  final List<(IconData, String, Future<bool> Function(BuildContext))> acciones;
  final String tipo;
  final String id;
  final int evidencias;
  final String? entrega; // la compra completa (sólo compras)
  final VoidCallback onCambio;

  @override
  State<_FinanzaDetalleScreen> createState() => _FinanzaDetalleScreenState();
}

class _FinanzaDetalleScreenState extends State<_FinanzaDetalleScreen> {
  late int _n = widget.evidencias;

  Future<void> _accion(Future<bool> Function(BuildContext) hacer) async {
    if (await hacer(context) && mounted) {
      widget.onCambio();
      Navigator.of(context).pop(); // ya no espera: Finanzas se recarga con su nuevo estado
    }
  }

  Future<void> _subir() async {
    if (await _subirEvidencia(context, widget.tipo, widget.id) && mounted) {
      widget.onCambio();
      setState(() => _n++);
    }
  }

  /// Al volver de la evidencia se cuenta otra vez (pudo quitar una).
  Future<void> _ver() async {
    await _abrirPantalla<void>(context, _EvidenciasScreen(tipo: widget.tipo, id: widget.id, titulo: widget.titulo));
    final r = await AdministracionService.evidencias(widget.tipo, widget.id);
    if (!mounted || !r.isSuccess) return;
    final n = _lista(r.data!['evidencias']).length;
    if (n != _n) {
      widget.onCambio();
      setState(() => _n = n);
    }
  }

  @override
  Widget build(BuildContext context) {
    final visibles = widget.datos.where((d) => d.$2 != null && d.$2!.isNotEmpty && d.$2 != 'null').toList();
    return Scaffold(
      appBar: AppBar(title: Text(widget.titulo)),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(16)),
          child: Column(children: [
            for (final d in visibles)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.grey.shade300))),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SizedBox(width: 140, child: Text(d.$1, style: TextStyle(color: Colors.grey.shade700))),
                  Expanded(child: Text(d.$2!, style: const TextStyle(fontWeight: FontWeight.w600))),
                ]),
              ),
          ]),
        ),
        if (widget.entrega != null) ...[
          const SizedBox(height: 12),
          _Ficha(
            inicio: const _InsigniaIcono(Icons.move_to_inbox, tono: Colors.green),
            titulo: 'Ver la compra completa',
            detalle: 'Café, revisión de calidad, lote y pagos',
            onTap: () => _abrirPantalla<void>(context, _CompraDetalleScreen(id: widget.entrega!, esDueno: true, onCambio: widget.onCambio)),
          ),
        ],
        const SizedBox(height: 20),
        // Lo que se puede hacer (botones de verdad, debajo del detalle).
        _Acciones(acciones: [
          for (final a in widget.acciones) (a.$1, a.$2, () => _accion(a.$3)),
          (Icons.add_a_photo_outlined, 'Subir evidencia', _subir),
          if (_n > 0) (Icons.photo_library_outlined, 'Ver evidencia ($_n)', _ver),
        ]),
      ]),
    );
  }
}

// ─── Finca ───────────────────────────────────────────────────────────────────

class _FincaScreen extends StatefulWidget {
  const _FincaScreen({required this.esDueno});
  final bool esDueno;

  @override
  State<_FincaScreen> createState() => _FincaScreenState();
}

class _FincaScreenState extends _ProcesoState<_FincaScreen> with _ProveedoresDelProceso {
  int _pestana = 0; // 0 Gastos, 1 Proveedores

  @override
  String get clave => 'finca';
  @override
  String? get areaProveedores => 'farm';

  @override
  Widget build(BuildContext context) {
    return pantalla('Finca', alFinal: () {
      if (_pestana == 1) masProveedores();
    }, (d) {
      final recientes = _lista(d['recientes']);
      return [
        _CuatroDatos(indicadores: _indicadoresFinca(d, widget.esDueno), grande: true), // los mismos 4 de la tarjeta
        const SizedBox(height: 16),
        _Acciones(acciones: [
          (
            Icons.receipt_long,
            _titulos['gasto']!, // el mismo nombre en cada proceso; el área va fija (General Manager, 3 nov 2026)
            () => formulario('gasto', fijos: const {'area': 'farm'}, subtitulo: 'Área: Finca')
          ),
        ]),
        _Pestanas(
          nombres: const ['Gastos', 'Proveedores'],
          elegida: _pestana,
          onElegir: (i) {
            setState(() => _pestana = i);
            if (i == 1) abrirProveedores();
          },
        ),
        if (_pestana == 1) ..._listaProveedores(),
        if (_pestana == 0) _encabezado('Últimos gastos de la finca', '${recientes.length}'),
        if (_pestana == 0 && recientes.isEmpty) _vacio('Todavía no hay gastos de la finca.'),
        if (_pestana == 0)
          for (final g in recientes)
            _Ficha(
              inicio: _Insignia(_fechaCorta(g['fecha']), tono: Colors.green),
              titulo: '${g['categoria'] ?? 'Gasto'}',
              detalle: [if ((g['descripcion'] ?? '').toString().isNotEmpty) '${g['descripcion']}', '${g['estado'] ?? ''}']
                  .where((t) => t.isNotEmpty)
                  .join(' · '),
              // La base ya dice el estado en español ("Pendiente de pago", "Pagado").
              fin: g['monto'] != null ? _Pildora(_soles(g['monto']), '${g['estado']}'.startsWith('Pagado') ? Colors.green : Colors.orange) : null,
            ),
      ];
    });
  }
}

/// Botón flotante de reporte en PDF de un proceso (General Manager, 4 nov 2026: Compras, luego Producción): abre
/// Generar reporte (Mensual con fecha de inicio y de fin, o Anual), pide el reporte recién entonces y muestra el PDF
/// para compartir. Cada proceso dice su nombre, cómo pedir su reporte y cómo armar su PDF.
mixin _ReporteDelProceso<T extends StatefulWidget> on State<T> {
  String get nombreReporte;
  Future<ApiResponse<Map<String, dynamic>>> pedirReporte(DateTime desde, DateTime hasta);
  Future<Uint8List> armarPdf(Map<String, dynamic> reporte);
  bool _generando = false;

  Widget botonReporte() => FloatingActionButton(
        tooltip: 'Generar reporte',
        onPressed: _generando ? null : _elegirReporte,
        child: _generando
            ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
            : const Icon(Icons.picture_as_pdf_outlined),
      );

  Future<void> _elegirReporte() async {
    final rango = await _abrirPantalla<(DateTime, DateTime)>(context, const _ReporteComprasForm());
    if (rango == null || !mounted) return;
    final (desde, hasta) = rango;
    setState(() => _generando = true);
    final r = await pedirReporte(desde, hasta);
    if (!mounted) return;
    if (!r.isSuccess) {
      setState(() => _generando = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(r.error ?? 'No se pudo generar el reporte')));
      return;
    }
    try {
      final bytes = await armarPdf(_mapa(r.data!['reporte']));
      if (!mounted) return;
      String m(DateTime d) => '${d.year}_${d.month.toString().padLeft(2, '0')}';
      final base = nombreReporte.toLowerCase().replaceAll('ó', 'o');
      final nombre = desde == hasta ? '${base}_${m(desde)}.pdf' : '${base}_${m(desde)}_a_${m(hasta)}.pdf';
      await _abrirPantalla<void>(
          context, _ReportePdfScreen(bytes: bytes, archivo: nombre, titulo: '$nombreReporte · ${ComprasPdfService.periodo(desde, hasta)}'));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No se pudo generar el PDF: revisa la señal.')));
      }
    } finally {
      if (mounted) setState(() => _generando = false);
    }
  }
}

/// Pestaña Gastos de un proceso (General Manager, 4 nov 2026: Compras, luego Producción): los gastos de su área con su
/// estado, los últimos 30 (de Mi área, que ya respeta las áreas de la persona); el monto lo dice la base.
mixin _GastosDelArea<T extends StatefulWidget> on State<T> {
  String get areaGastos; // 'sourcing', 'production'
  String get vacioGastos;
  List<Map<String, dynamic>>? _gastos;
  String? _errorGastos;

  Future<void> cargarGastos() async {
    final r = await AdministracionService.miArea(areaGastos);
    if (!mounted) return;
    setState(() {
      _errorGastos = r.isSuccess ? null : (r.error ?? 'No se pudo cargar');
      if (r.isSuccess) _gastos = _lista(r.data!['gastos']).map((g) => Map<String, dynamic>.from(g)).toList();
    });
  }

  List<Widget> listaGastos() {
    final gastos = _gastos;
    if (_errorGastos != null) return [Padding(padding: const EdgeInsets.all(16), child: Text(_errorGastos!, textAlign: TextAlign.center))];
    if (gastos == null) return [const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()))];
    if (gastos.isEmpty) return [_vacio(vacioGastos)];
    return [
      const SizedBox(height: 8),
      for (final g in gastos)
        _Ficha(
          inicio: _Insignia(_fechaCorta(g['expense_date']), tono: Colors.orange),
          titulo: '${g['category'] ?? 'Gasto'}',
          detalle: [
            _soles(g['amount']),
            if ((g['description'] ?? '').toString().isNotEmpty) '${g['description']}',
            if ((g['created_by'] ?? '').toString().isNotEmpty) '${g['created_by']}',
          ].join(' · '),
          // La base dice "Pagado" o "Pendiente de pago"; el mismo naranja que lo que espera en Finanzas.
          fin: g['status'] == 'Pagado' ? const _Pildora('Pagado', Colors.green) : const _Pildora('Pendiente', Colors.orange),
        ),
    ];
  }
}

// ─── Compras ─────────────────────────────────────────────────────────────────

class _ComprasScreen extends StatefulWidget {
  const _ComprasScreen({required this.esDueno});
  final bool esDueno;

  @override
  State<_ComprasScreen> createState() => _ComprasScreenState();
}

class _ComprasScreenState extends _ProcesoState<_ComprasScreen> with _ProveedoresDelProceso, _GastosDelArea, _ReporteDelProceso {
  int _pestana = 0; // 0 Compras, 1 Adelantos, 2 Proveedores, 3 Gastos

  // Pestaña Compras: todas las compras, de 20 en 20 desde el servidor al llegar al final; cada una abre su detalle.
  final List<Map<String, dynamic>> _compras = [];
  bool _cargandoCompras = false;
  bool _hayMasCompras = true;
  String? _errorCompras;

  @override
  void initState() {
    super.initState();
    _masCompras();
  }

  Future<void> _masCompras() async {
    if (_cargandoCompras || !_hayMasCompras) return;
    setState(() => _cargandoCompras = true);
    final r = await AdministracionService.compras(offset: _compras.length);
    if (!mounted) return;
    setState(() {
      _cargandoCompras = false;
      if (r.isSuccess) {
        _compras.addAll(_lista(r.data!['compras']));
        _hayMasCompras = r.data!['hayMas'] == true;
      } else {
        _errorCompras = r.error;
        _hayMasCompras = false;
      }
    });
  }

  /// Después de registrar o pagar, la lista vuelve a empezar para mostrar lo nuevo.
  Future<void> _recargarCompras() async {
    setState(() {
      _compras.clear();
      _hayMasCompras = true;
      _errorCompras = null;
    });
    await _masCompras();
  }

  Future<void> _abrirCompra(Map<String, dynamic> c) async {
    var cambio = false;
    await _abrirPantalla<void>(context, _CompraDetalleScreen(id: '${c['id']}', esDueno: widget.esDueno, onCambio: () => cambio = true));
    if (cambio && mounted) {
      cargar();
      _recargarCompras();
    }
  }

  @override
  Future<void> formulario(String form, {Map<String, dynamic> fijos = const {}, String? subtitulo, Map<String, dynamic> iniciales = const {}}) async {
    if (await _abrirFormulario(context, form, fijos: fijos, subtitulo: subtitulo, iniciales: iniciales)) {
      cargar();
      if (form == 'entrega') _recargarCompras();
    }
  }

  static const _colorSituacion = _coloresCompra;

  // Pestaña Adelantos: los pedidos que esperan a Finanzas y los adelantos, de 20 en 20.
  final List<Map<String, dynamic>> _adelantos = [];
  List<Map<String, dynamic>> _porAprobar = [];
  bool _cargandoAdelantos = false;
  bool _hayMasAdelantos = true;
  String? _errorAdelantos;

  Future<void> _masAdelantos() async {
    if (_cargandoAdelantos || !_hayMasAdelantos) return;
    setState(() => _cargandoAdelantos = true);
    final r = await AdministracionService.adelantos(offset: _adelantos.length);
    if (!mounted) return;
    setState(() {
      _cargandoAdelantos = false;
      if (r.isSuccess) {
        if (_adelantos.isEmpty) _porAprobar = _lista(r.data!['porAprobar']);
        _adelantos.addAll(_lista(r.data!['adelantos']));
        _hayMasAdelantos = r.data!['hayMas'] == true;
      } else {
        _errorAdelantos = r.error;
        _hayMasAdelantos = false;
      }
    });
  }

  static const _estadosAdelanto = {'open': 'Abierto', 'partly_used': 'Usado en parte', 'settled': 'Liquidado'};

  List<Widget> _listaAdelantos() => [
        if (_porAprobar.isNotEmpty) ...[
          _encabezado('Esperan a Finanzas', '${_porAprobar.length}'),
          for (final q in _porAprobar)
            _Ficha(
              inicio: _Insignia(_fechaCorta(q['request_date']), tono: Colors.purple),
              titulo: '${q['party'] ?? 'Sin nombre'}',
              detalle: [if ((q['reason'] ?? '').toString().isNotEmpty) '${q['reason']}', 'pidió ${q['created_by'] ?? ''}'].join(' · '),
              fin: _Pildora('${_soles(q['amount'])} · por aprobar', Colors.purple),
            ),
        ],
        _encabezado('Adelantos', ''),
        for (final a in _adelantos)
          _Ficha(
            inicio: _Insignia(_fechaCorta(a['advance_date']), tono: ((a['open_balance'] as num?) ?? 0) > 0 ? Colors.blue : Colors.green),
            titulo: '${a['nombre'] ?? a['party_id'] ?? 'Sin nombre'}',
            detalle: [
              '${a['id']} · ${_soles(a['amount'])}',
              if (((a['used_in_coffee'] as num?) ?? 0) > 0) 'usado en café ${_soles(a['used_in_coffee'])}',
              if (((a['returned_in_money'] as num?) ?? 0) > 0) 'devuelto ${_soles(a['returned_in_money'])}',
              _estadosAdelanto[a['status']] ?? '${a['status'] ?? ''}',
            ].join(' · '),
            fin: ((a['open_balance'] as num?) ?? 0) > 0
                ? _Pildora('queda ${_soles(a['open_balance'])}', Colors.blue)
                : const _Pildora('Liquidado', Colors.green),
          ),
        if (_errorAdelantos != null)
          Padding(padding: const EdgeInsets.all(16), child: Text(_errorAdelantos!, textAlign: TextAlign.center))
        else if (_cargandoAdelantos || _hayMasAdelantos)
          const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()))
        else if (_adelantos.isEmpty)
          _vacio('Todavía no hay adelantos.'),
      ];

  List<Widget> _listaCompras() => [
        const SizedBox(height: 12),
        for (final c in _compras)
          _Ficha(
            inicio: _Insignia(_fechaCorta(c['fecha']), tono: Colors.green),
            titulo: '${c['agricultor'] ?? 'Sin nombre'}',
            detalle: [
              '${_estadosCafe[c['estado']] ?? c['estado']} · ${_kg(c['kg'])}',
              if (c['precio'] != null) '${_soles(c['precio'])}/kg', // dueños
              if (c['situacion'] == 'Pagado en parte' && c['debe'] != null) 'falta ${_soles(c['debe'])}',
              if (c['producto'] != null) '${c['producto']}',
              if (c['descuento'] == true) 'Con descuento',
            ].join(' · '),
            // Cada compra lleva su marca de pago a la derecha (General Manager, 3 nov 2026): Sin precio, Por pagar,
            // Pago solicitado, Pagado en parte, Pagado o Rechazado. El precio va en la línea de abajo.
            fin: _Pildora('${c['situacion'] ?? ''}', _colorSituacion[c['situacion']] ?? Colors.grey),
            onTap: () => _abrirCompra(c),
          ),
        if (_errorCompras != null)
          Padding(padding: const EdgeInsets.all(16), child: Text(_errorCompras!, textAlign: TextAlign.center))
        else if (_cargandoCompras || _hayMasCompras)
          const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()))
        else if (_compras.isEmpty)
          _vacio('Todavía no hay compras.')
      ];

  @override
  String get clave => 'compras';

  @override
  String get areaGastos => 'sourcing';
  @override
  String get vacioGastos => 'Todavía no hay gastos de Compras.';

  @override
  String? get rolProveedores => 'agricultor'; // en Compras, sólo quienes nos venden café
  @override
  String get vacioProveedores => 'Todavía no hay agricultores.';

  @override
  Widget build(BuildContext context) {
    return pantalla('Compras', (d) {
      return [
        // Sin resumen arriba (General Manager, 3 nov 2026): la tarjeta de Procesos ya lo muestra.
        // Todas del mismo tamaño; las de dinero sólo para dueños.
        _Acciones(acciones: [
          (Icons.move_to_inbox, _titulos['entrega']!, () => formulario('entrega')),
          (Icons.handshake, _titulos['adelanto']!, () => formulario('adelanto')),
          (Icons.person_add_alt_1, _titulos['proveedor']!, () => formulario('proveedor')),
          (Icons.receipt_long, _titulos['gasto']!, () => formulario('gasto', fijos: const {'area': 'sourcing'}, subtitulo: 'Área: Compras')),
        ]),
        _Pestanas(
          // Adelantos en lugar de En almacén (General Manager, 3 nov 2026).
          nombres: const ['Compras', 'Adelantos', 'Proveedores', 'Gastos'], // Gastos: General Manager, 4 nov 2026
          elegida: _pestana,
          onElegir: (i) {
            setState(() => _pestana = i);
            if (i == 2) abrirProveedores();
            if (i == 3) cargarGastos();
            if (i == 1 && _adelantos.isEmpty && _hayMasAdelantos) _masAdelantos();
          },
        ),
        if (_pestana == 3)
          ...listaGastos()
        else if (_pestana == 2)
          ..._listaProveedores()
        else if (_pestana == 0)
          ..._listaCompras()
        else
          ..._listaAdelantos(),
      ];
    },
        alFinal: _pestana == 3 ? null : (_pestana == 2 ? masProveedores : (_pestana == 0 ? _masCompras : _masAdelantos)),
        // Reporte en PDF, mensual o anual (General Manager, 4 nov 2026); el contenido lo decidió el área de Compras.
        botonFlotante: botonReporte());
  }

  @override
  String get nombreReporte => 'Compras';
  @override
  Future<ApiResponse<Map<String, dynamic>>> pedirReporte(DateTime desde, DateTime hasta) => AdministracionService.reporteCompras(desde, hasta);
  @override
  Future<Uint8List> armarPdf(Map<String, dynamic> reporte) => ComprasPdfService.generarBytes(reporte);
}

/// Detalle de un proveedor: quién es, qué vende, sus procesos y lo que le compramos. DNI o RUC, teléfono, cuentas
/// y dinero sólo para dueños (lo decide la base). Sólo información; cada compra reciente abre su detalle.
class _ProveedorDetalleScreen extends StatefulWidget {
  const _ProveedorDetalleScreen({required this.id});
  final String id;

  @override
  State<_ProveedorDetalleScreen> createState() => _ProveedorDetalleScreenState();
}

class _ProveedorDetalleScreenState extends State<_ProveedorDetalleScreen> {
  Map<String, dynamic>? _p;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final r = await AdministracionService.proveedor(widget.id);
    if (!mounted) return;
    setState(() {
      _error = r.isSuccess ? null : r.error;
      if (r.isSuccess) _p = _mapa(r.data!['proveedor']);
    });
  }

  bool _generando = false;

  Future<void> _formulario(String form, {Map<String, dynamic> fijos = const {}, Map<String, dynamic> iniciales = const {}, String? subtitulo}) async {
    if (await _abrirFormulario(context, form, fijos: {'proveedorId': widget.id, ...fijos}, iniciales: iniciales, subtitulo: subtitulo)) _cargar();
  }

  void _editarDatos(Map<String, dynamic> p) => _formulario('editarProveedor',
      iniciales: {
        for (final (k, v) in [
          ('nombre', p['nombre']),
          ('documento', p['documento']),
          ('telefono', p['telefono']),
          ('comunidad', p['comunidad']),
          ('notas', p['notas'])
        ])
          if (v != null) k: '$v',
      },
      subtitulo: '${p['nombre'] ?? ''}');

  /// Una cuenta: editarla (la anterior queda archivada) o quitarla (se archiva, nunca se borra).
  Future<void> _cuenta(Map<String, dynamic> c) async {
    final eleccion = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.edit_outlined), title: const Text('Editar cuenta'), onTap: () => Navigator.pop(ctx, 'editar')),
          ListTile(
              leading: Icon(Icons.remove_circle_outline, color: Colors.red.shade700),
              title: Text('Quitar cuenta', style: TextStyle(color: Colors.red.shade700)),
              onTap: () => Navigator.pop(ctx, 'quitar')),
        ]),
      ),
    );
    if (!mounted || eleccion == null) return;
    if (eleccion == 'editar') {
      await _formulario('cuentaProveedor',
          fijos: {'reemplazaId': c['id']},
          iniciales: {
            for (final (k, v) in [('tipo', c['tipo']), ('banco', c['banco']), ('numero', c['numero']), ('titular', c['titular'])])
              if (v != null) k: '$v',
          },
          subtitulo: 'La cuenta anterior queda guardada como archivada');
      return;
    }
    final si = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Quitar cuenta'),
        content: Text('${c['numero'] ?? ''} dejará de aparecer. Queda guardada como archivada.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Quitar cuenta')),
        ],
      ),
    );
    if (si != true || !mounted) return;
    final r = await AdministracionService.registrar('quitarCuenta', {'cuentaId': c['id']}, clave: AdministracionService.nuevaClave('quitarCuenta'));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(r.isSuccess ? 'Cuenta quitada ✓' : (r.error ?? 'No se pudo quitar'))));
    if (r.isSuccess) _cargar();
  }

  /// Generar reporte: el reporte se pide recién ahora (no al abrir el detalle) y se muestra el PDF para compartir.
  Future<void> _generarReporte() async {
    if (_generando) return;
    setState(() => _generando = true);
    final r = await AdministracionService.reporteProveedor(widget.id);
    if (!mounted) return;
    if (!r.isSuccess) {
      setState(() => _generando = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(r.error ?? 'No se pudo generar el reporte')));
      return;
    }
    try {
      final bytes = await ProveedorPdfService.generarBytes(_mapa(r.data!['reporte']));
      if (!mounted) return;
      await _abrirPantalla<void>(context, _ReportePdfScreen(bytes: bytes, archivo: 'proveedor_${widget.id}.pdf'));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No se pudo generar el PDF: revisa la señal.')));
      }
    } finally {
      if (mounted) setState(() => _generando = false);
    }
  }

  static const _vende = {'cherry': 'Cereza', 'parchment': 'Pergamino', 'both': 'Cereza y pergamino'};

  Widget _dato(String nombre, String? valor) => valor == null || valor.isEmpty || valor == 'null'
      ? const SizedBox.shrink()
      : Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.grey.shade300))),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 130, child: Text(nombre, style: TextStyle(color: Colors.grey.shade700))),
            Expanded(child: Text(valor, style: const TextStyle(fontWeight: FontWeight.w600))),
          ]),
        );

  Widget _panel(String titulo, List<Widget> filas) {
    final visibles = filas.where((w) => w is! SizedBox).toList();
    if (visibles.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
          padding: const EdgeInsets.fromLTRB(4, 16, 4, 6), child: Text(titulo, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(16)),
        child: Column(children: visibles),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final p = _p;
    final compras = p == null ? const <String, dynamic>{} : _mapa(p['compras']);
    final dinero = p == null || p['dinero'] == null ? null : _mapa(p['dinero']);
    final adelantos = p == null || p['adelantos'] == null ? null : _mapa(p['adelantos']);
    final cuentas = p == null ? const <Map<String, dynamic>>[] : _lista(p['cuentas']);
    final recientes = p == null ? const <Map<String, dynamic>>[] : _lista(p['recientes']);
    final listaAdelantos = p == null ? const <Map<String, dynamic>>[] : _lista(p['adelantos_lista']);
    final puedeEditar = p != null && p['puede_editar'] == true;
    final procesos = p == null ? const <String>[] : [for (final a in (p['procesos'] as List? ?? const [])) _areas['$a'] ?? '$a'];
    final es = p == null
        ? ''
        : [
            if (p['agricultor'] == true) 'Agricultor',
            if (p['comprador'] == true) 'Comprador',
            if (p['agricultor'] != true && p['comprador'] != true) 'Proveedor',
          ].join(' y ');
    return Scaffold(
      appBar: AppBar(title: const Text('Proveedor')),
      body: RefreshIndicator(
        onRefresh: _cargar,
        child: p == null
            ? ListView(children: [
                Padding(
                  padding: const EdgeInsets.all(32),
                  child: _error != null ? Text(_error!, textAlign: TextAlign.center) : const Center(child: CircularProgressIndicator()),
                ),
              ])
            : ListView(padding: const EdgeInsets.all(16), children: [
                Row(children: [
                  Expanded(child: Text('${p['nombre'] ?? ''}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold))),
                  _Pildora(es, p['agricultor'] == true ? Colors.green : Colors.blue),
                ]),
                Text('${p['id']}${p['tipo'] == 'business' ? ' · Empresa' : ' · Persona'}', style: TextStyle(color: Colors.grey.shade700)),
                const SizedBox(height: 12),
                _Acciones(acciones: [
                  (Icons.picture_as_pdf_outlined, _generando ? 'Generando…' : 'Generar reporte', _generarReporte),
                  if (puedeEditar) (Icons.edit_outlined, 'Editar datos', () => _editarDatos(p)),
                  if (puedeEditar)
                    (Icons.add_card_outlined, 'Agregar cuenta', () => _formulario('cuentaProveedor', subtitulo: '${p['nombre'] ?? ''}')),
                ]),
                _panel('Datos', [
                  _dato('Vende', _vende[p['vende']] ?? p['vende']?.toString()),
                  _dato('Lo recoge', p['recoge']?.toString()),
                  _dato('Comunidad', p['comunidad']?.toString()),
                  _dato('Procesos', procesos.isEmpty ? null : procesos.join(', ')),
                  _dato('DNI o RUC', p['documento']?.toString()),
                  _dato('Teléfono', p['telefono']?.toString()),
                  _dato('Notas', p['notas']?.toString()),
                ]),
                // Dueños: cada cuenta se toca para editarla o quitarla; sin dueño no llegan cuentas.
                if (puedeEditar) ...[
                  _encabezado('Cuentas para pagarle', ''),
                  for (final c in cuentas)
                    _Ficha(
                      inicio: const _InsigniaIcono(Icons.account_balance_outlined, tono: Colors.blue),
                      titulo: '${c['numero'] ?? ''}',
                      detalle: [
                        _tiposCuenta[c['tipo']] ?? '${c['tipo']}',
                        if (c['banco'] != null) '${c['banco']}',
                        if (c['titular'] != null) '${c['titular']}'
                      ].join(' · '),
                      onTap: () => _cuenta(c),
                    ),
                  if (cuentas.isEmpty) _vacio('Sin cuentas todavía.'),
                ],
                _panel('Lo que le compramos', [
                  _dato('Compras', '${compras['n'] ?? 0}'),
                  _dato('Kilos', _kg(compras['kg'])),
                  _dato('Última compra', compras['ultima'] == null ? null : _fechaCorta(compras['ultima'])),
                  _dato('Comprado', dinero == null ? null : _soles(dinero['comprado'])),
                  _dato('Le debemos', dinero == null ? null : _soles(dinero['debe'])),
                  _dato('Adelantos abiertos',
                      adelantos == null || (adelantos['n'] ?? 0) == 0 ? null : '${_soles(adelantos['saldo'])} (${adelantos['n']})'),
                ]),
                if (listaAdelantos.isNotEmpty) ...[
                  _encabezado('Adelantos', ''),
                  for (final a in listaAdelantos)
                    _Ficha(
                      inicio: _Insignia(_fechaCorta(a['fecha']), tono: Colors.orange),
                      titulo: '${_soles(a['monto'])} · ${a['id']}',
                      detalle:
                          'Usado en café ${_soles(a['usado'])}${((a['devuelto'] as num?) ?? 0) > 0 ? ' · Devuelto ${_soles(a['devuelto'])}' : ''}',
                      fin: Text(((a['saldo'] as num?) ?? num.tryParse('${a['saldo']}') ?? 0) > 0 ? 'Saldo ${_soles(a['saldo'])}' : 'Cerrado',
                          style: TextStyle(fontWeight: FontWeight.w600, color: Colors.grey.shade800)),
                    ),
                ],
                if (recientes.isNotEmpty) ...[
                  _encabezado('Últimas compras', ''),
                  for (final c in recientes)
                    _Ficha(
                      inicio: _Insignia(_fechaCorta(c['fecha']), tono: Colors.green),
                      titulo: '${_estadosCafe[c['estado']] ?? c['estado']} · ${_kg(c['kg'])}',
                      detalle: '${c['id']}',
                      onTap: () => _abrirPantalla<void>(context, _CompraDetalleScreen(id: '${c['id']}', esDueno: false, onCambio: _cargar)),
                    ),
                ],
              ]),
      ),
    );
  }
}

/// El reporte de un proveedor en PDF, con el botón de compartir (como el PDF del detalle de pedido).
/// Generar reporte (General Manager, 4 nov 2026; reunión con Compras, Finanzas y Tecnología; diseño de la General
/// Manager): Mensual con fecha de inicio y de fin (un mes, o un rango de hasta 12 meses, como la cosecha de mayo a
/// septiembre) o Anual (el año). Lo que se toca parece botón: Mensual | Anual, los dos campos de fecha (con flecha; se
/// abren aquí mismo con el año y los 12 meses) y Generar PDF. El período elegido es información: texto con una línea
/// fina, sin caja de color. Los meses futuros no se eligen; el aviso va justo encima del botón.
class _ReporteComprasForm extends StatefulWidget {
  const _ReporteComprasForm();

  @override
  State<_ReporteComprasForm> createState() => _ReporteComprasFormState();
}

class _ReporteComprasFormState extends State<_ReporteComprasForm> {
  static final _hoy = DateTime(DateTime.now().year, DateTime.now().month);
  bool _anual = false;
  late DateTime _desde = _hoy;
  late DateTime _hasta = _hoy;
  late int _anio = _hoy.year;
  int? _abierto; // 0 fecha de inicio, 1 fecha de fin: se abre uno a la vez

  int get _meses => (_hasta.year * 12 + _hasta.month) - (_desde.year * 12 + _desde.month) + 1;

  String? get _aviso {
    if (_anual) return null;
    if (_hasta.isBefore(_desde)) return 'La fecha de fin no puede ser antes de la fecha de inicio.';
    if (_meses > 12) return 'Un reporte cubre como máximo 12 meses.';
    return null;
  }

  static String _mesLargo(DateTime m) => '${ComprasPdfService.nombreMes(m.month)} ${m.year}';

  @override
  Widget build(BuildContext context) {
    final aviso = _aviso;
    const etiqueta = TextStyle(fontSize: 12, letterSpacing: 0.8, fontWeight: FontWeight.w600, color: FincasColors.textMuted);
    return Scaffold(
      backgroundColor: FincasColors.background,
      appBar: AppBar(
        backgroundColor: FincasColors.background,
        leading: IconButton(icon: const Icon(Icons.close), tooltip: 'Cancelar', onPressed: () => Navigator.of(context).pop()),
        title: const Text('Generar reporte'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          // Mensual | Anual: dos botones, el elegido relleno y con check.
          Row(children: [
            for (final (anual, texto) in [(false, 'Mensual'), (true, 'Anual')]) ...[
              if (anual) const SizedBox(width: 12),
              Expanded(child: _BotonTipo(texto: texto, elegido: _anual == anual, onTap: () => setState(() => _anual = anual))),
            ],
          ]),
          const SizedBox(height: 10),
          Text(_anual ? 'Genera el reporte de un año completo.' : 'Genera un reporte por rango de meses.',
              style: const TextStyle(color: FincasColors.textSecondary)),
          const SizedBox(height: 16),
          const Divider(height: 1, color: FincasColors.divider),
          const SizedBox(height: 20),
          Text(_anual ? 'Selecciona el año' : 'Selecciona el período', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 14),
          if (_anual)
            _CampoPeriodo(
              etiqueta: 'AÑO',
              valor: '$_anio',
              // El año se cambia con las flechas, aquí mismo; no se pasa del año actual.
              fin: Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(tooltip: 'Año anterior', icon: const Icon(Icons.chevron_left), onPressed: () => setState(() => _anio--)),
                IconButton(
                    tooltip: 'Año siguiente',
                    icon: const Icon(Icons.chevron_right),
                    onPressed: _anio >= _hoy.year ? null : () => setState(() => _anio++)),
              ]),
            )
          else ...[
            _CampoPeriodo(
              etiqueta: 'FECHA DE INICIO',
              valor: _mesLargo(_desde),
              abierto: _abierto == 0,
              onTap: () => setState(() => _abierto = _abierto == 0 ? null : 0),
              panel: _SelectorMes(
                valor: _desde,
                maximo: _hoy,
                onCambio: (m) => setState(() {
                  _desde = m;
                  if (_hasta.isBefore(m)) _hasta = m; // la fecha de fin sigue a la de inicio
                  _abierto = null;
                }),
              ),
            ),
            const SizedBox(height: 12),
            _CampoPeriodo(
              etiqueta: 'FECHA DE FIN',
              valor: _mesLargo(_hasta),
              abierto: _abierto == 1,
              onTap: () => setState(() => _abierto = _abierto == 1 ? null : 1),
              panel: _SelectorMes(
                valor: _hasta,
                maximo: _hoy,
                onCambio: (m) => setState(() {
                  _hasta = m;
                  _abierto = null;
                }),
              ),
            ),
          ],
          // El período: información, sin caja ni sombra (no se toca).
          const SizedBox(height: 24),
          const Divider(height: 1, color: FincasColors.divider),
          const SizedBox(height: 16),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Padding(padding: EdgeInsets.only(top: 2), child: const Icon(Icons.calendar_month_outlined, color: FincasColors.textMuted)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('PERÍODO DEL REPORTE', style: etiqueta),
                const SizedBox(height: 4),
                Text(_anual ? 'Año $_anio' : ComprasPdfService.periodo(_desde, _hasta),
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                if (!_anual && aviso == null) ...[
                  const SizedBox(height: 2),
                  Text(_meses == 1 ? '1 mes seleccionado' : '$_meses meses seleccionados', style: const TextStyle(color: FincasColors.textSecondary)),
                ],
              ]),
            ),
          ]),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (aviso != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(aviso, style: const TextStyle(color: FincasColors.error, fontWeight: FontWeight.w600)),
              ),
            FilledButton.icon(
              onPressed: aviso != null
                  ? null
                  : () => Navigator.of(context).pop(_anual ? (DateTime(_anio, 1), DateTime(_anio, 12)) : (_desde, _hasta)),
              style: FilledButton.styleFrom(
                backgroundColor: FincasColors.actionPrimary,
                foregroundColor: FincasColors.actionPrimaryText,
                disabledBackgroundColor: FincasColors.disabledBg,
                disabledForegroundColor: FincasColors.disabledText,
                minimumSize: const Size.fromHeight(56),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
              ),
              icon: const Icon(Icons.picture_as_pdf_outlined),
              label: const Text('Generar PDF'),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Uno de los dos botones Mensual | Anual: el elegido relleno con check, el otro con borde.
class _BotonTipo extends StatelessWidget {
  const _BotonTipo({required this.texto, required this.elegido, required this.onTap});
  final String texto;
  final bool elegido;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: elegido ? FincasColors.sand : FincasColors.surface,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12), side: BorderSide(color: elegido ? FincasColors.sand : FincasColors.border)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: SizedBox(
          height: 52,
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            if (elegido) ...[const Icon(Icons.check, size: 20, color: FincasColors.espresso), const SizedBox(width: 8)],
            Text(texto,
                style: TextStyle(
                    fontSize: 17, fontWeight: FontWeight.w600, color: elegido ? FincasColors.espresso : FincasColors.textSecondary)),
          ]),
        ),
      ),
    );
  }
}

/// Un campo de fecha que se toca: etiqueta, el mes elegido y una flecha; al tocarlo se abre aquí mismo [panel].
/// Con [fin] (el año del reporte anual) las flechas van dentro y el campo no se abre.
class _CampoPeriodo extends StatelessWidget {
  const _CampoPeriodo({required this.etiqueta, required this.valor, this.abierto = false, this.onTap, this.panel, this.fin});
  final String etiqueta;
  final String valor;
  final bool abierto;
  final VoidCallback? onTap;
  final Widget? panel;
  final Widget? fin;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: FincasColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: FincasColors.borderStrong)),
      clipBehavior: Clip.antiAlias,
      child: Column(children: [
        InkWell(
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, 12, fin == null ? 16 : 4, 14),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(etiqueta,
                      style: const TextStyle(fontSize: 12, letterSpacing: 0.8, fontWeight: FontWeight.w600, color: FincasColors.textMuted)),
                  const SizedBox(height: 6),
                  Row(children: [
                    const Icon(Icons.calendar_today_outlined, size: 22, color: FincasColors.textSecondary),
                    const SizedBox(width: 12),
                    // Si un mes largo no cabe (Septiembre 2026 con letra grande), se achica en vez de cortarse.
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(valor, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ]),
                ]),
              ),
              fin ?? Icon(abierto ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, color: FincasColors.textSecondary),
            ]),
          ),
        ),
        if (abierto && panel != null) ...[
          const Divider(height: 1, color: FincasColors.divider),
          Padding(padding: const EdgeInsets.fromLTRB(12, 4, 12, 12), child: panel!),
        ],
      ]),
    );
  }
}

/// Elegir un mes con un toque: el año con flechas y los 12 meses debajo; los meses después de [maximo] no se eligen.
class _SelectorMes extends StatefulWidget {
  const _SelectorMes({required this.valor, required this.maximo, required this.onCambio});
  final DateTime valor;
  final DateTime maximo;
  final ValueChanged<DateTime> onCambio;

  @override
  State<_SelectorMes> createState() => _SelectorMesState();
}

class _SelectorMesState extends State<_SelectorMes> {
  late int _anio = widget.valor.year;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        IconButton(tooltip: 'Año anterior', icon: const Icon(Icons.chevron_left), onPressed: () => setState(() => _anio--)),
        Expanded(child: Text('$_anio', textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600))),
        IconButton(
            tooltip: 'Año siguiente',
            icon: const Icon(Icons.chevron_right),
            onPressed: _anio >= widget.maximo.year ? null : () => setState(() => _anio++)),
      ]),
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (var m = 1; m <= 12; m++)
          ChoiceChip(
            label: SizedBox(width: 34, child: Text(ComprasPdfService.mesCorto(m), textAlign: TextAlign.center)),
            selected: widget.valor.year == _anio && widget.valor.month == m,
            onSelected: DateTime(_anio, m).isAfter(widget.maximo) ? null : (_) => widget.onCambio(DateTime(_anio, m)),
          ),
      ]),
    ]);
  }
}

class _ReportePdfScreen extends StatelessWidget {
  const _ReportePdfScreen({required this.bytes, required this.archivo, this.titulo = 'Reporte del proveedor'});
  final Uint8List bytes;
  final String archivo;
  final String titulo;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: Text(titulo),
        actions: [
          IconButton(
            tooltip: 'Compartir',
            icon: const Icon(Icons.share_rounded),
            onPressed: () => Printing.sharePdf(bytes: bytes, filename: archivo),
          ),
        ],
      ),
      body: PdfPreview(
        build: (_) => Future.value(bytes),
        allowSharing: false,
        allowPrinting: false,
        canChangeOrientation: false,
        canChangePageFormat: false,
        canDebug: false,
      ),
    );
  }
}

/// Detalle de una compra: sólo información (sin cajas que parezcan botones) y, abajo, lo que se puede hacer:
/// poner el precio si no tiene, o pagarla (dueños) si se debe.
class _CompraDetalleScreen extends StatefulWidget {
  const _CompraDetalleScreen({required this.id, required this.esDueno, required this.onCambio});
  final String id;
  final bool esDueno;
  final VoidCallback onCambio; // se puso precio o se pagó: la lista se recarga al volver

  @override
  State<_CompraDetalleScreen> createState() => _CompraDetalleScreenState();
}

class _CompraDetalleScreenState extends State<_CompraDetalleScreen> {
  Map<String, dynamic>? _c;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final r = await AdministracionService.compra(widget.id);
    if (!mounted) return;
    setState(() {
      _error = r.isSuccess ? null : r.error;
      if (r.isSuccess) _c = _mapa(r.data!['compra']);
    });
  }

  Future<void> _formulario(String form, Map<String, dynamic> fijos, String subtitulo) async {
    if (await _abrirFormulario(context, form, fijos: fijos, subtitulo: subtitulo)) {
      widget.onCambio();
      _cargar();
    }
  }

  /// Una pregunta antes de guardar; true si dijo que sí.
  Future<bool> _confirmar(String titulo, String texto, String si) async =>
      await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(titulo),
          content: Text(texto),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: Text(si)),
          ],
        ),
      ) ==
      true;

  Future<void> _guardar(String form, Map<String, dynamic> datos, String Function(Map<String, dynamic>) hecho) async {
    final r = await AdministracionService.registrar(form, datos, clave: AdministracionService.nuevaClave(form));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(r.isSuccess ? hecho(r.data ?? const {}) : (r.error ?? 'No se guardó'))));
    if (r.isSuccess) {
      widget.onCambio();
      _cargar();
    }
  }

  /// Solicitar pago completo (General Manager, 3 nov 2026): todo lo que se debe, por transferencia; Finanzas lo paga.
  Future<void> _solicitarCompleto(Map<String, dynamic> c) async {
    if (!await _confirmar(
        '¿Solicitar pago completo?', '${c['agricultor'] ?? ''}: ${_soles(c['debe'])} por transferencia. Finanzas lo pagará.', 'Solicitar')) {
      return;
    }
    await _guardar('solicitarPago', {'compraId': c['compra_id'], 'metodo': 'transfer'}, (_) => _hecho['solicitarPago']!);
  }

  /// Marcar como pagado desde adelantos (dueños): los adelantos abiertos del mismo agricultor, el más antiguo primero,
  /// hasta lo que se debe. Nunca es automático. No sale dinero del banco.
  Future<void> _pagarDesdeAdelantos(Map<String, dynamic> c, List<Map<String, dynamic>> adelantos) async {
    final lista = adelantos.map((a) => '${a['id']} (queda ${_soles(a['saldo'])})').join(', ');
    if (!await _confirmar('¿Marcar como pagado desde adelantos?',
        '${c['agricultor'] ?? ''} debe ${_soles(c['debe'])}. Se usa: $lista. No sale dinero del banco.', 'Marcar como pagado')) {
      return;
    }
    await _guardar('pagoDesdeAdelantos', {'compraId': c['compra_id']}, (res) {
      final falta = num.tryParse('${res['still_owed'] ?? 0}') ?? 0;
      return 'Pagado desde adelantos ✓ ${_soles(res['from_advances'])}${falta > 0 ? ' · falta ${_soles(falta)}' : ''}';
    });
  }

  Widget _dato(String nombre, String? valor) => valor == null || valor.isEmpty || valor == 'null'
      ? const SizedBox.shrink()
      : Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.grey.shade300))),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 140, child: Text(nombre, style: TextStyle(color: Colors.grey.shade700))),
            Expanded(child: Text(valor, style: const TextStyle(fontWeight: FontWeight.w600))),
          ]),
        );

  Widget _panel(String titulo, List<Widget> filas) {
    final visibles = filas.where((w) => w is! SizedBox).toList();
    if (visibles.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
          padding: const EdgeInsets.fromLTRB(4, 16, 4, 6), child: Text(titulo, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(16)),
        child: Column(children: visibles),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    final compra = c == null || c['compra'] == null ? null : _mapa(c['compra']);
    final revision = c == null || c['revision'] == null ? null : _mapa(c['revision']);
    final lote = c == null || c['lote'] == null ? null : _mapa(c['lote']);
    final pagos = c == null ? const <Map<String, dynamic>>[] : _lista(c['pagos']);
    final situacion = '${c?['situacion'] ?? ''}';
    return Scaffold(
      appBar: AppBar(title: const Text('Compra')),
      body: RefreshIndicator(
        onRefresh: _cargar,
        child: c == null
            ? ListView(children: [
                Padding(
                  padding: const EdgeInsets.all(32),
                  child: _error != null ? Text(_error!, textAlign: TextAlign.center) : const Center(child: CircularProgressIndicator()),
                ),
              ])
            : ListView(padding: const EdgeInsets.all(16), children: [
                Row(children: [
                  Expanded(child: Text('${c['agricultor'] ?? 'Sin nombre'}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold))),
                  _Pildora(situacion, _coloresCompra[situacion] ?? Colors.grey),
                ]),
                Text('${c['id']} · ${_fechaCorta(c['fecha'])}', style: TextStyle(color: Colors.grey.shade700)),
                _panel('Café', [
                  _dato('Café', _estadosCafe[c['estado']] ?? '${c['estado']}'),
                  _dato('Kilos', _kg(c['kg'])),
                  _dato('Producto vinculado', c['producto']?.toString()),
                  _dato('Lote', lote == null ? null : '${lote['id']} · calidad ${lote['calidad'] == 'pending' ? 'por revisar' : lote['calidad']}'),
                  _dato('Notas', c['notas']?.toString()),
                  _dato('Registrado por', c['registrado_por']?.toString()),
                ]),
                // La revisión al llegar, como la registró Calidad (aquí sólo se muestra; sólo Calidad la registra).
                _panel('Revisión de calidad', [
                  _dato('Decisión',
                      revision == null ? 'Sin revisión todavía' : (_decisiones[revision['decision']] ?? revision['decision']?.toString())),
                  _dato('Humedad', revision?['humedad'] == null ? null : '${revision!['humedad']} %'),
                  _dato('Cereza madura', revision?['maduro'] == null ? null : '${revision!['maduro']} %'),
                  _dato('Factor de rendimiento', revision?['rendimiento']?.toString()),
                  _dato('Defectos', revision?['defectos']?.toString()),
                  _dato('Olor', revision?['olor']?.toString()),
                  _dato('Muestra guardada', revision?['muestra'] == null ? null : (revision!['muestra'] == true ? 'Sí' : 'No')),
                  _dato('Revisado por', revision?['por']?.toString()),
                ]),
                if (compra != null)
                  _panel('Dinero', [
                    _dato('Precio por kilo', compra['precio'] == null ? null : _soles(compra['precio'])),
                    _dato('Total', compra['total'] == null ? null : _soles(compra['total'])),
                    _dato('De adelantos', compra['de_adelantos'] == null ? null : _soles(compra['de_adelantos'])),
                    _dato('Pagado', compra['pagado'] == null ? null : _soles(compra['pagado'])),
                    _dato('Falta pagar', compra['debe'] == null ? null : _soles(compra['debe'])),
                    _dato('Adelanto usado', c['adelanto']?.toString()),
                  ]),
                if (pagos.isNotEmpty) _panel('Pagos', [for (final p in pagos) _dato(_fechaCorta(p['fecha']), '${_soles(p['monto'])} · ${p['de']}')]),
                // Dueños: la evidencia del pago se carga recién al tocar (General Manager, 3 nov 2026).
                if (compra != null && c['compra_id'] != null) ...[
                  const SizedBox(height: 12),
                  _Ficha(
                    inicio: const _InsigniaIcono(Icons.photo_library_outlined, tono: Colors.indigo),
                    titulo: 'Evidencia',
                    detalle: 'Vouchers y recibos de esta compra',
                    onTap: () => _abrirPantalla<void>(
                        context, _EvidenciasScreen(tipo: 'purchase', id: '${c['compra_id']}', titulo: '${c['agricultor'] ?? ''} · ${c['id']}')),
                  ),
                ],
                const SizedBox(height: 20),
                // Lo que se puede hacer con esta compra (botones de verdad).
                if (situacion == 'Sin precio')
                  _Acciones(acciones: [
                    (Icons.sell_outlined, 'Poner precio', () => _formulario('precio', {'entregaId': c['id']}, '${c['id']} · ${_kg(c['kg'])}')),
                  ])
                else if (c['solicitado'] != null && (situacion == 'Pago solicitado' || situacion == 'Pagado en parte'))
                  // Ya se pidió: Finanzas lo paga (General Manager, 3 nov 2026). Sólo información, no un botón.
                  Row(children: [
                    Icon(Icons.schedule_send, color: Colors.indigo.shade700),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Pago solicitado a Finanzas el ${_fechaCorta(_mapa(c['solicitado'])['fecha'])}: '
                        '${_soles(_mapa(c['solicitado'])['monto'])} '
                        '${_mapa(c['solicitado'])['metodo'] == 'advance' ? 'con el adelanto ${_mapa(c['solicitado'])['adelanto']}' : 'por transferencia'}',
                        style: TextStyle(color: Colors.indigo.shade800, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ])
                else if ((situacion == 'Por pagar' || situacion == 'Pagado en parte') && c['compra_id'] != null)
                  // Compras no paga: pide el pago completo y Finanzas lo hace, o (dueños) lo marca pagado desde los
                  // adelantos del agricultor. Nunca es automático (General Manager, 3 nov 2026).
                  _Acciones(acciones: [
                    (Icons.schedule_send, 'Solicitar pago completo', () => _solicitarCompleto(c)),
                    if (widget.esDueno && _lista(c['adelantos']).isNotEmpty)
                      (Icons.savings_outlined, 'Marcar como pagado desde adelantos', () => _pagarDesdeAdelantos(c, _lista(c['adelantos']))),
                  ]),
              ]),
      ),
    );
  }
}

// ─── Evidencia ───────────────────────────────────────────────────────────────

/// Subir evidencia (General Manager, 3 nov 2026): una foto del voucher o del recibo, con la cámara o de la galería.
/// Sólo dueños (lo decide la base). true si se subió.
Future<bool> _subirEvidencia(BuildContext context, String tipo, String id) async {
  final fuente = await showModalBottomSheet<ImageSource>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const ListTile(title: Text('Subir evidencia', style: TextStyle(fontWeight: FontWeight.w600))),
        ListTile(
            leading: const Icon(Icons.photo_camera_outlined), title: const Text('Tomar foto'), onTap: () => Navigator.pop(ctx, ImageSource.camera)),
        ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Elegir de la galería'),
            onTap: () => Navigator.pop(ctx, ImageSource.gallery)),
      ]),
    ),
  );
  if (fuente == null || !context.mounted) return false;
  final foto = await ImagePicker().pickImage(source: fuente, maxWidth: 2000, imageQuality: 80); // siempre JPG
  if (foto == null || !context.mounted) return false;
  final bytes = await foto.readAsBytes();
  if (!context.mounted) return false;
  final mensajes = ScaffoldMessenger.of(context);
  mensajes.showSnackBar(const SnackBar(content: Text('Subiendo evidencia…'), duration: Duration(seconds: 30)));
  final r = await AdministracionService.subirEvidencia(tipo: tipo, id: id, bytes: bytes);
  mensajes.hideCurrentSnackBar();
  mensajes.showSnackBar(SnackBar(content: Text(r.isSuccess ? 'Evidencia subida ✓' : (r.error ?? 'No se subió'))));
  return r.isSuccess;
}

/// La evidencia de una compra, un gasto o un adelanto: fotos en cuadrícula; tocar una la abre en grande.
class _EvidenciasScreen extends StatefulWidget {
  const _EvidenciasScreen({required this.tipo, required this.id, required this.titulo});
  final String tipo;
  final String id;
  final String titulo;

  @override
  State<_EvidenciasScreen> createState() => _EvidenciasScreenState();
}

class _EvidenciasScreenState extends State<_EvidenciasScreen> {
  List<Map<String, dynamic>>? _items;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final r = await AdministracionService.evidencias(widget.tipo, widget.id);
    if (!mounted) return;
    setState(() {
      _error = r.isSuccess ? null : r.error;
      if (r.isSuccess) _items = _lista(r.data!['evidencias']);
    });
  }

  Future<void> _abrir(Map<String, dynamic> e) async {
    final url = e['url'] as String?;
    if (url == null) return;
    if (e['tipo'] == 'application/pdf') {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      return;
    }
    final quitada = await _abrirPantalla<bool>(context, _EvidenciaVista(evidencia: e));
    if (quitada == true) _cargar();
  }

  @override
  Widget build(BuildContext context) {
    final lista = _items;
    return Scaffold(
      appBar: AppBar(title: const Text('Evidencia')),
      body: RefreshIndicator(
        onRefresh: _cargar,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          Text(widget.titulo, style: TextStyle(color: Colors.grey.shade700)),
          const SizedBox(height: 12),
          _Acciones(acciones: [
            (
              Icons.add_a_photo_outlined,
              'Subir evidencia',
              () async {
                if (await _subirEvidencia(context, widget.tipo, widget.id)) _cargar();
              }
            ),
          ]),
          const SizedBox(height: 16),
          if (lista == null)
            Padding(
              padding: const EdgeInsets.all(32),
              child: _error != null ? Text(_error!, textAlign: TextAlign.center) : const Center(child: CircularProgressIndicator()),
            )
          else if (lista.isEmpty)
            _vacio('Todavía no hay evidencia.')
          else
            GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              children: [
                for (final e in lista)
                  InkWell(
                    onTap: () => _abrir(e),
                    borderRadius: BorderRadius.circular(10),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Stack(fit: StackFit.expand, children: [
                        e['tipo'] == 'application/pdf' || e['url'] == null
                            ? Container(
                                color: Colors.grey.shade200, child: Icon(Icons.picture_as_pdf_outlined, size: 36, color: Colors.grey.shade700))
                            : Image.network('${e['url']}',
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Container(color: Colors.grey.shade200, child: const Icon(Icons.broken_image_outlined))),
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: Container(
                            color: Colors.black54,
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child:
                                Text(_fechaCorta(e['fecha']), textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 12)),
                          ),
                        ),
                      ]),
                    ),
                  ),
              ],
            ),
        ]),
      ),
    );
  }
}

/// Una evidencia en grande (se puede acercar con los dedos) y Quitar evidencia (se archiva, nunca se borra).
class _EvidenciaVista extends StatelessWidget {
  const _EvidenciaVista({required this.evidencia});
  final Map<String, dynamic> evidencia;

  Future<void> _quitar(BuildContext context) async {
    final si = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Quitar evidencia'),
        content: const Text('Dejará de aparecer. Queda guardada como archivada.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Quitar evidencia')),
        ],
      ),
    );
    if (si != true || !context.mounted) return;
    final r = await AdministracionService.registrar('quitarEvidencia', {'evidenciaId': evidencia['id']},
        clave: AdministracionService.nuevaClave('quitarEvidencia'));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(r.isSuccess ? 'Evidencia quitada ✓' : (r.error ?? 'No se pudo quitar'))));
    if (r.isSuccess) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text([_fechaCorta(evidencia['fecha']), if (evidencia['por'] != null) '${evidencia['por']}'].join(' · '),
            style: const TextStyle(fontSize: 15)),
        actions: [IconButton(tooltip: 'Quitar evidencia', icon: const Icon(Icons.delete_outline), onPressed: () => _quitar(context))],
      ),
      body: Center(
        child: InteractiveViewer(
          maxScale: 5,
          child: Image.network('${evidencia['url']}',
              errorBuilder: (_, __, ___) => const Text('No se pudo abrir. Vuelve a entrar.', style: TextStyle(color: Colors.white))),
        ),
      ),
    );
  }
}

// ─── Comercialización ───────────────────────────────────────────────────────

/// Los 4 datos de ventas arriba y, debajo, el reporte de ventas de siempre (antes en Resumen).
class _ComercialScreen extends StatefulWidget {
  const _ComercialScreen();

  @override
  State<_ComercialScreen> createState() => _ComercialScreenState();
}

class _ComercialScreenState extends State<_ComercialScreen> {
  Map<String, dynamic>? _datos;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final r = await AdministracionService.procesos(solo: 'comercial');
    if (!mounted) return;
    setState(() {
      _error = r.isSuccess ? null : r.error;
      if (r.isSuccess && r.data!['comercial'] is! Map) _error = 'Este proceso no es de tus áreas.';
      if (r.isSuccess && r.data!['comercial'] is Map) _datos = _mapa(r.data!['comercial']);
    });
  }

  @override
  Widget build(BuildContext context) {
    final d = _datos;
    return Scaffold(
      appBar: AppBar(title: const Text('Comercialización')),
      body: ReportesTab(
        encabezado: d != null
            ? Column(children: [
                _CuatroDatos(indicadores: _indicadoresComercial(d), grande: true),
                const SizedBox(height: 16),
                _Acciones(acciones: [
                  (
                    Icons.receipt_long,
                    _titulos['gasto']!, // el mismo nombre en cada proceso; el área va fija (General Manager, 3 nov 2026)
                    () => _abrirFormulario(context, 'gasto', fijos: const {'area': 'commercial'}, subtitulo: 'Área: Comercial'),
                  ),
                ]),
              ])
            : Padding(
                padding: const EdgeInsets.all(16),
                child: _error != null ? Text(_error!) : const Center(child: CircularProgressIndicator()),
              ),
      ),
    );
  }
}

// ─── Producción ──────────────────────────────────────────────────────────────

class _ProduccionScreen extends StatefulWidget {
  const _ProduccionScreen();

  @override
  State<_ProduccionScreen> createState() => _ProduccionScreenState();
}

class _ProduccionScreenState extends _ProcesoState<_ProduccionScreen> with _ProveedoresDelProceso, _GastosDelArea, _ReporteDelProceso {
  int? _pestana; // 0 Lotes de tostado, 1 Café verde, 2 Proveedores, 3 Gastos; al abrir: Lotes de tostado si hay alguno, si no Café verde

  @override
  String get nombreReporte => 'Producción';
  @override
  Future<ApiResponse<Map<String, dynamic>>> pedirReporte(DateTime desde, DateTime hasta) =>
      AdministracionService.reporteProduccion(desde, hasta);
  @override
  Future<Uint8List> armarPdf(Map<String, dynamic> reporte) => ProduccionPdfService.generarBytes(reporte);

  @override
  String get areaGastos => 'production';
  @override
  String get vacioGastos => 'Todavía no hay gastos de Producción.';

  @override
  String? get areaProveedores => 'production';

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
    // Reporte en PDF como Compras (General Manager, 4 nov 2026); el contenido lo decidió el área de Producción.
    return pantalla('Producción', botonFlotante: botonReporte(), alFinal: () {
      if (_pestana == 2) masProveedores();
    }, (d) {
      final lotes = _lista(d['lotes_verdes']);
      final tuestes = _lista(d['tuestes']);
      final porProcesar = _lista(d['por_procesar']);
      final pestana = _pestana ?? (tuestes.isNotEmpty ? 0 : 1);
      return [
        // Sin resumen arriba, como Compras (General Manager, 4 nov 2026): la tarjeta de Procesos ya lo muestra.
        _Acciones(acciones: [
          (Icons.local_fire_department, 'Tostar café', _tostar),
          (
            Icons.receipt_long,
            _titulos['gasto']!, // el mismo nombre en cada proceso; el área va fija (General Manager, 3 nov 2026)
            () => formulario('gasto', fijos: const {'area': 'production'}, subtitulo: 'Área: Producción')
          ),
        ]),
        _Pestanas(
          // Gastos, y "Lotes de tostado" y "Café verde" en vez de Tuestes y Lotes: General Manager, 4 nov 2026
          nombres: const ['Lotes de tostado', 'Café verde', 'Proveedores', 'Gastos'],
          anchoPorNombre: true,
          elegida: pestana,
          onElegir: (i) {
            setState(() => _pestana = i);
            if (i == 2) abrirProveedores();
            if (i == 3) cargarGastos();
          },
        ),
        if (pestana == 3)
          ...listaGastos()
        else if (pestana == 2)
          ..._listaProveedores()
        else if (pestana == 0) ...[
          _encabezado('Lotes de tostado en curso y programados', '${tuestes.length}'),
          if (tuestes.isEmpty) _vacio('No hay lotes de tostado programados. Toca "Tostar café".'),
          for (final t in tuestes)
            _Ficha(
              inicio: _Insignia('${t['lote'] ?? '—'}', tono: t['estado'] == 'in_progress' ? Colors.deepOrange : Colors.blue),
              titulo: '${t['producto'] ?? 'Lote ${t['lote'] ?? ''}'}',
              detalle: '${t['estado'] == 'in_progress' ? 'Tostando' : 'Programado'} · ${_kg(t['kg_verde'])} · ${_fechaCorta(t['fecha'])}',
              fin: t['estado'] == 'in_progress'
                  ? ElevatedButton(onPressed: () => _finalizar(t), child: const Text('Finalizar'))
                  : OutlinedButton(onPressed: () => _iniciar(t), child: const Text('Iniciar')),
            ),
        ] else ...[
          _encabezado('Lotes de café verde', '${lotes.length} ${lotes.length == 1 ? 'lote' : 'lotes'}'),
          if (lotes.isEmpty) _vacio('No hay lotes de café verde con stock.'),
          for (final l in lotes) _FilaLote(lote: l),
          if (porProcesar.isNotEmpty) ...[
            _encabezado('Café comprado por procesar', '${porProcesar.length}'),
            for (final p in porProcesar)
              _Ficha(
                inicio: const _InsigniaIcono(Icons.inventory_2_outlined, tono: Colors.brown),
                titulo: _estadosCafe[p['estado']] ?? '${p['estado']}',
                detalle: '${p['lotes']} ${p['lotes'] == 1 ? 'lote' : 'lotes'} · calidad: ${p['calidad'] == 'pending' ? 'por revisar' : p['calidad']}',
                fin: Text(_kg(p['kg']), style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
          ],
        ],
      ];
    });
  }
}

/// Un lote verde en su ficha: código, variedad y cosecha, kilos que quedan de los que entraron, barra y %.
class _FilaLote extends StatelessWidget {
  const _FilaLote({required this.lote});
  final Map<String, dynamic> lote;

  @override
  Widget build(BuildContext context) {
    final ahora = (lote['kg_ahora'] as num?)?.toDouble() ?? 0;
    final inicial = (lote['kg_inicial'] as num?)?.toDouble() ?? 0;
    final parte = inicial > 0 ? (ahora / inicial).clamp(0.0, 1.0) : 0.0;
    final detalle = [if (lote['variedad'] != null) '${lote['variedad']}', if (lote['cosecha'] != null) 'cosecha ${lote['cosecha']}'];
    // Sólo información: sin caja blanca, una línea fina debajo.
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.grey.shade200))),
      child: Row(children: [
        _Insignia('${lote['codigo']}'),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                child: Text(detalle.isEmpty ? 'Café verde' : detalle.join(' · '),
                    style: const TextStyle(fontSize: 15), maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
              Text('${_kg(ahora).replaceAll(' kg', '')} kg / ${_kg(inicial)}', style: TextStyle(color: Colors.grey.shade800)),
            ]),
            const SizedBox(height: 6),
            Row(children: [
              Expanded(
                child: LinearProgressIndicator(
                  value: parte,
                  minHeight: 8,
                  borderRadius: BorderRadius.circular(4),
                  color: Colors.green.shade600,
                  backgroundColor: Colors.grey.shade200,
                ),
              ),
              const SizedBox(width: 10),
              _Pildora('${(parte * 100).round()}%', Colors.green),
            ]),
          ]),
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
      setState(() {
        _busqueda = texto.trim();
        _productos.clear();
        _pagina = 0;
        _hayMas = true;
        _error = null;
        _cargando = false;
        _pedido++;
      });
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
                    child: Text(_productos.isEmpty ? 'Ningún producto con ese nombre' : '',
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
