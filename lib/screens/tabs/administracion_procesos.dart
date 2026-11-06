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

/// "Lunes 2 de noviembre": el día de la semana, el día y el mes (General Manager, 4 nov 2026, para los lotes de tostado).
/// La fecha viene como "2026-11-02" (día de Lima); se lee tal cual, sin pasar por la hora del teléfono.
String _fechaLarga(dynamic iso) {
  final d = DateTime.tryParse('${iso ?? ''}');
  if (d == null) return '';
  const dias = ['Lunes', 'Martes', 'Miércoles', 'Jueves', 'Viernes', 'Sábado', 'Domingo'];
  const meses = ['enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', 'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre'];
  return '${dias[d.weekday - 1]} ${d.day} de ${meses[d.month - 1]}';
}

/// Ancho en píxeles para decodificar una foto que ocupa 1/[columnas] de la pantalla: una foto del teléfono pesa unos
/// 48 MB en memoria a tamaño completo y menos de 1 MB a este tamaño. Sólo en miniaturas; al abrirla se ve completa.
int _anchoMiniatura(BuildContext context, int columnas) =>
    (MediaQuery.sizeOf(context).width / columnas * MediaQuery.devicePixelRatioOf(context)).round();

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
  DateTime? _cargadoEn; // cuándo llegaron; al volver de un proceso se piden de nuevo sólo si algo cambió o ya pasó un minuto
  int _version = -1; // AdministracionService.version de esa carga

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
    final version = AdministracionService.version;
    final r = await AdministracionService.procesos();
    if (!mounted) return;
    setState(() {
      _error = r.isSuccess ? null : r.error;
      if (r.isSuccess) {
        _cargado = true;
        _cargadoEn = DateTime.now();
        _version = version;
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

  // Al volver de un proceso, los resúmenes se piden de nuevo sólo si dentro se guardó algo o tienen más de un minuto
  // (antes se pedían siempre: los seis procesos en cada vuelta).
  Future<void> _entrar(Widget pantalla) async {
    await _abrirPantalla<String>(context, pantalla);
    if (!mounted) return;
    final cargadoEn = _cargadoEn;
    if (_version != AdministracionService.version || cargadoEn == null || DateTime.now().difference(cargadoEn) > const Duration(minutes: 1)) {
      _cargar();
    }
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
          onTap: () => _entrar(_ComercialScreen(esDueno: widget.esDueno)),
        )
      ),
      (
        'production',
        _produccion,
        _TarjetaProceso(
          titulo: 'Producción',
          indicadores: _produccion == null ? null : _indicadoresProduccion(_produccion!),
          error: _error,
          onTap: () => _entrar(_ProduccionScreen(esDueno: widget.esDueno)),
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
    // El resumen que ya trajo su tarjeta se ve al instante (sin rueda de carga); igual se pide de nuevo enseguida,
    // así el dinero siempre lo confirma el servidor.
    datos = AdministracionService.procesoEnMemoria(clave);
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

  /// Otra vez desde el principio, por ejemplo después de Registrar proveedor.
  void recargarProveedores() {
    setState(() {
      _proveedores.clear();
      _hayMasProv = true;
      _totalProv = null;
      _errorProv = null;
      _cargandoProv = false;
      _pedidoProv++;
    });
    masProveedores();
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

class _LogisticaScreenState extends _ProcesoState<_LogisticaScreen> with _ProveedoresDelProceso, _GastosDelArea, _ReporteDelProceso {
  // Las mismas buenas prácticas de Compras y Producción (General Manager, 4 nov 2026; las pestañas y el reporte los
  // propuso el área de Logística): sin datos arriba, pestañas Por despachar | Entregados | Proveedores | Gastos.
  int _pestana = 0; // 0 Por despachar, 1 Entregados, 2 Proveedores, 3 Gastos

  @override
  String get clave => 'logistica';
  @override
  String? get areaProveedores => 'fulfillment';
  @override
  String get vacioProveedores => 'Todavía no hay proveedores de logística (empaque, transporte).';
  @override
  String get areaGastos => 'fulfillment';
  @override
  String get vacioGastos => 'Todavía no hay gastos de Logística.';
  @override
  bool get duenoGastos => widget.esDueno;

  @override
  String get nombreReporte => 'Logística';
  @override
  Future<ApiResponse<Map<String, dynamic>>> pedirReporte(DateTime desde, DateTime hasta) => AdministracionService.reporteLogistica(desde, hasta);
  @override
  Future<Uint8List> armarPdf(Map<String, dynamic> reporte) => LogisticaPdfService.generarBytes(reporte);

  // Los pedidos, de 20 en 20 desde el servidor, como la pestaña Pedidos: por despachar los más antiguos primero (son
  // los siguientes); entregados y cancelados, los más nuevos primero. Cada pedido abre su detalle completo.
  static const _vistas = ['PENDIENTES', 'HISTORIAL'];
  final _pedidos = [<Map<String, dynamic>>[], <Map<String, dynamic>>[]];
  final _paginas = [0, 0];
  final _hayMas = [true, true];
  final _cargandoPedidos = [false, false];
  final _errores = <String?>[null, null];
  int _vuelta = 0;

  @override
  Future<void> cargar() async {
    _vuelta++;
    for (var i = 0; i < 2; i++) {
      _pedidos[i].clear();
      _paginas[i] = 0;
      _hayMas[i] = true;
      _cargandoPedidos[i] = false;
      _errores[i] = null;
    }
    await Future.wait([super.cargar(), _masPedidos(_pestana < 2 ? _pestana : 0)]);
  }

  Future<void> _masPedidos(int i) async {
    if (_cargandoPedidos[i] || !_hayMas[i]) return;
    final vuelta = _vuelta;
    setState(() => _cargandoPedidos[i] = true);
    final r = await ApiService.getPedidos(vista: _vistas[i], pagina: _paginas[i] + 1, limite: 20, orden: i == 0 ? 'antiguos' : null);
    if (!mounted || vuelta != _vuelta) return;
    setState(() {
      _cargandoPedidos[i] = false;
      if (r.isSuccess && r.data != null) {
        _pedidos[i].addAll(r.data!.pedidos);
        _paginas[i]++;
        _hayMas[i] = r.data!.hayMas;
      } else {
        _errores[i] = r.error ?? 'No se pudieron cargar los pedidos.';
        _hayMas[i] = false;
      }
    });
  }

  List<Widget> _listaPedidos(int i) {
    final pedidos = _pedidos[i];
    return [
      if (pedidos.isEmpty && !_cargandoPedidos[i])
        _vacio(_errores[i] ?? (i == 0 ? 'No hay pedidos por despachar.' : 'Todavía no hay pedidos entregados.')),
      for (final p in pedidos) _fichaPedido(context, p, onActualizado: cargar),
      // Sin texto al final de la lista: sólo la carga mientras llega la siguiente página.
      if (_cargandoPedidos[i]) const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return pantalla('Logística', botonFlotante: botonReporte(), alFinal: () {
      if (_pestana < 2) _masPedidos(_pestana);
      if (_pestana == 2) masProveedores();
      if (_pestana == 3) masGastos();
    }, (d) {
      return [
        // Sin datos arriba, como Compras y Producción: la tarjeta de Procesos ya los muestra (4 nov 2026).
        _Acciones(acciones: [
          (
            Icons.receipt_long,
            _titulos['gasto']!, // el mismo nombre en cada proceso; el área va fija (General Manager, 3 nov 2026)
            () => formulario('gasto', fijos: const {'area': 'fulfillment'}, subtitulo: 'Área: Logística')
          ),
        ]),
        _Pestanas(
          nombres: const ['Por despachar', 'Entregados', 'Proveedores', 'Gastos'],
          anchoPorNombre: true,
          elegida: _pestana,
          onElegir: (i) {
            setState(() => _pestana = i);
            if (i < 2 && _pedidos[i].isEmpty) _masPedidos(i);
            if (i == 2) abrirProveedores();
            if (i == 3) cargarGastos();
          },
        ),
        if (_pestana == 3)
          ...listaGastos()
        else if (_pestana == 2)
          ..._listaProveedores()
        else
          ..._listaPedidos(_pestana),
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

class _FinanzasScreenState extends _ProcesoState<_FinanzasScreen> with _ReporteDelProceso {
  // Rediseñada con el área (General Manager, 4 nov 2026; la propuesta de Finanzas): sin datos arriba, los mismos pagos
  // y aprobaciones de siempre y el reporte en PDF. Sin pestaña "Gastos del área": Finanzas paga los gastos de todas las
  // áreas en Gastos. Movimientos en lugar de Proveedores (General Manager, 5 nov 2026).
  int _pestana = 0; // 0 Compras, 1 Gastos, 2 Adelantos, 3 Movimientos

  @override
  String get nombreReporte => 'Finanzas';
  @override
  Future<ApiResponse<Map<String, dynamic>>> pedirReporte(DateTime desde, DateTime hasta) => AdministracionService.reporteFinanzas(desde, hasta);
  @override
  Future<Uint8List> armarPdf(Map<String, dynamic> reporte) => FinanzasPdfService.generarBytes(reporte);

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
    _vueltaMov++;
    _movimientos.clear();
    _cargandoMov = false;
    _hayMasMov = true;
    _errorMov = null;
    _inicial = null;
    await Future.wait([super.cargar(), if (_pestana < 3) _mas(_pestana) else _masMovimientos()]);
  }

  // Movimientos (General Manager, 5 nov 2026): el estado de una cuenta, como el Estado de lote; lo que entra en verde y
  // lo que sale en naranja, con el saldo después de cada uno, de 20 en 20, y el saldo inicial al final.
  // Con el diseño de una app de banco (General Manager, 5 nov 2026, con una imagen): arriba el saldo disponible y lo que
  // entró y salió en el mes; la lista por día, con Buscar y Filtrar por estado. Sin Caja (efectivo): sólo el banco.
  Map<String, dynamic> _cuentaMov = const {};
  Map<String, dynamic>? _resumen;
  final List<Map<String, dynamic>> _movimientos = [];
  bool _cargandoMov = false;
  bool _hayMasMov = true;
  String? _errorMov;
  Map<String, dynamic>? _inicial;
  int _vueltaMov = 0; // al buscar o filtrar, las respuestas viejas se descartan
  bool _verSaldo = true;
  bool _buscando = false;
  final _buscar = TextEditingController();
  Timer? _esperaBuscar;
  String? _filtro; // un estado; null, todos

  static const _estadosMov = ['Conciliado', 'Falta en la app', 'No está en el banco', 'Ignorada'];

  @override
  void dispose() {
    _esperaBuscar?.cancel();
    _buscar.dispose();
    super.dispose();
  }

  Future<void> _masMovimientos() async {
    if (_cargandoMov || !_hayMasMov) return;
    _cargandoMov = true;
    final vuelta = _vuelta;
    final vueltaMov = _vueltaMov;
    final r = await AdministracionService.movimientosCuenta(offset: _movimientos.length, buscar: _buscar.text, estado: _filtro);
    if (!mounted || vuelta != _vuelta || vueltaMov != _vueltaMov) return;
    setState(() {
      _cargandoMov = false;
      if (r.isSuccess) {
        _cuentaMov = _mapa(r.data!['cuenta']);
        if (r.data!['resumen'] != null) _resumen = _mapa(r.data!['resumen']);
        _movimientos.addAll(_lista(r.data!['filas']));
        _hayMasMov = r.data!['hayMas'] == true;
        if (r.data!['inicial'] != null) _inicial = _mapa(r.data!['inicial']);
      } else {
        _errorMov = r.error;
        _hayMasMov = false;
      }
    });
  }

  /// La lista vuelve a empezar (después de conciliar, al buscar o al filtrar).
  void _reiniciarMovimientos() {
    if (!mounted) return;
    setState(() {
      _vueltaMov++;
      _movimientos.clear();
      _cargandoMov = false;
      _hayMasMov = true;
      _errorMov = null;
      _inicial = null;
    });
    _masMovimientos();
  }

  Future<void> _abrirMovimiento(Map<String, dynamic> m) =>
      _recargarSiCambio(_abrirPantalla<bool>(context, _MovimientoDetalleScreen(id: (m['movimiento'] as num).toInt())));

  Future<void> _abrirPago(String id) async {
    var cambio = false;
    await _abrirPantalla<void>(context, _PagoDetalleScreen(id: id, onCambio: () => cambio = true));
    await _recargarSiCambio(Future.value(cambio));
  }

  Future<void> _recargarSiCambio(Future<bool?> pantalla) async {
    if (await pantalla == true) _reiniciarMovimientos();
  }

  void _alternarBuscar() {
    final cerrar = _buscando;
    setState(() => _buscando = !_buscando);
    if (cerrar && _buscar.text.trim().isNotEmpty) {
      _buscar.clear();
      _reiniciarMovimientos();
    }
  }

  Future<void> _elegirFiltro() async {
    final elegido = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Align(alignment: Alignment.centerLeft, child: Text('Filtrar por estado', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)))),
          for (final e in ['Todos', ..._estadosMov])
            ListTile(
              title: Text(e),
              trailing: (e == 'Todos' ? _filtro == null : _filtro == e) ? Icon(Icons.check, color: Colors.blue.shade700) : null,
              onTap: () => Navigator.of(context).pop(e),
            ),
        ]),
      ),
    );
    if (elegido == null) return;
    _filtrar(elegido == 'Todos' ? null : elegido);
  }

  void _filtrar(String? estado) {
    if (estado == _filtro) return;
    _filtro = estado;
    _reiniciarMovimientos();
  }

  // Cada línea del banco abre su detalle, donde se concilia (General Manager, 5 nov 2026); los cargos del banco
  // (Impuesto ITF, Comisión del banco) no importan y no se abren.
  VoidCallback? _alTocar(Map<String, dynamic> m) => m['movimiento'] != null
      ? (const {'Impuesto ITF', 'Comisión del banco'}.contains(m['estado']) ? null : () => _abrirMovimiento(m))
      // Un pago de la app que el banco todavía no trae abre su detalle (evidencia, número de operación).
      : ('${m['id'] ?? ''}'.startsWith('PY-') ? () => _abrirPago('${m['id']}') : null);

  List<Widget> _listaMovimientos() {
    final listo = !_cargandoMov && !_hayMasMov && _errorMov == null;
    final filas = [
      ..._movimientos,
      if (listo && _inicial != null) {'tipo': 'Saldo inicial', 'fecha': _inicial!['fecha'], 'saldo': _inicial!['saldo']},
    ];
    // Por día, del más nuevo al más antiguo, como llegan.
    final dias = <String, List<Map<String, dynamic>>>{};
    for (final m in filas) {
      (dias['${m['fecha'] ?? ''}'] ??= []).add(m);
    }
    final buscado = _buscar.text.trim().isNotEmpty || _filtro != null;
    return [
      const SizedBox(height: 16),
      _TarjetaSaldo(cuenta: _cuentaMov, resumen: _resumen, visible: _verSaldo, onVer: () => setState(() => _verSaldo = !_verSaldo)),
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 20, 0, 4),
        child: Row(children: [
          const Expanded(child: Text('Movimientos', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold))),
          _BotonRedondo(icono: _buscando ? Icons.close : Icons.search, ayuda: _buscando ? 'Cerrar la búsqueda' : 'Buscar', onTap: _alternarBuscar),
          const SizedBox(width: 10),
          _BotonRedondo(icono: Icons.tune, ayuda: 'Filtrar por estado', activo: _filtro != null, onTap: _elegirFiltro),
        ]),
      ),
      if (_buscando)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: TextField(
            controller: _buscar,
            autofocus: true,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Nombre, monto u operación',
              prefixIcon: const Icon(Icons.search),
              isDense: true,
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onChanged: (_) {
              _esperaBuscar?.cancel();
              _esperaBuscar = Timer(const Duration(milliseconds: 400), _reiniciarMovimientos);
            },
            onSubmitted: (_) {
              _esperaBuscar?.cancel();
              _reiniciarMovimientos();
            },
          ),
        ),
      if (_filtro != null)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: InputChip(label: Text(_filtro!), onDeleted: () => _filtrar(null), deleteButtonTooltipMessage: 'Quitar el filtro'),
          ),
        ),
      for (final d in dias.entries) ...[
        _DiaMovimientos(fecha: d.key),
        _GrupoMovimientos(children: [for (final m in d.value) _LineaMovimiento(movimiento: m, onTap: _alTocar(m))]),
      ],
      if (_errorMov != null)
        Padding(padding: const EdgeInsets.all(16), child: Text(_errorMov!, textAlign: TextAlign.center))
      else if (_cargandoMov || _hayMasMov)
        const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()))
      else if (_movimientos.isEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: _vacio(buscado ? 'Ningún movimiento con esa búsqueda.' : 'Esta cuenta no tiene movimientos todavía.'),
        ),
    ];
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
  static bool _esperaFila(Map<String, dynamic> f) => f['estado'] == 'Pendiente' || f['estado'] == 'Urgente';
  static _Pildora _estado(Map<String, dynamic> f) => _Pildora('${f['estado'] ?? ''}', _coloresEstado[f['estado']] ?? Colors.grey);
  static String? _diasEsperando(Map<String, dynamic> f) {
    final d = (f['espera'] as num?)?.toInt();
    if (d == null || !_esperaFila(f)) return null;
    return d == 0 ? 'pedido hoy' : (d == 1 ? 'espera 1 día' : 'espera $d días');
  }

  static int _nEvidencias(Map<String, dynamic> f) => (f['evidencias'] as num?)?.toInt() ?? 0;
  static String _textoEvidencias(Map<String, dynamic> f) => _nEvidencias(f) == 1 ? '1 evidencia' : '${_nEvidencias(f)} evidencias';

  /// Tocar una fila abre su detalle (General Manager, 3 nov 2026); debajo, lo que se puede hacer: pagar o aprobar
  /// (sólo si espera), Subir evidencia y Ver evidencia. Al volver, si algo cambió, Finanzas se recarga.
  Future<void> _detalle(String tipo, Map<String, dynamic> f) async {
    final espera = _esperaFila(f);
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
    // A quién y dónde se paga, mientras el formulario se abre (General Manager, 5 nov 2026).
    final destino = AdministracionService.destinoPago(const {'purchase': 'compra', 'expense': 'gasto', 'advance_request': 'adelanto'}[tipo] ?? tipo, id);
    if (!await _abrirFormulario(ctx, form, fijos: fijos, subtitulo: subtitulo, iniciales: iniciales, destino: destino) || !ctx.mounted) {
      return false;
    }
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
    return pantalla('Finanzas', botonFlotante: datos?['solo_duenos'] == true ? null : botonReporte(), alFinal: () {
      if (_pestana < 3) _mas(_pestana);
      if (_pestana == 3) _masMovimientos();
    }, (d) {
      if (d['solo_duenos'] == true) return [_vacio('Finanzas es sólo para los dueños.')];
      final filas = _pestana < 3 ? _filas[_pestana] : const <Map<String, dynamic>>[];
      return [
        // Sin datos arriba (General Manager, 4 nov 2026): la tarjeta de Procesos ya los muestra.
        _Acciones(acciones: [
          (Icons.account_balance_wallet, _titulos['retiro']!, () => formulario('retiro')),
          (Icons.receipt_long, _titulos['gasto']!, () => formulario('gasto', fijos: const {'area': 'finance'}, subtitulo: 'Área: Finanzas')),
        ]),
        // Sin números en las pestañas: un número no parece botón (4 nov 2026). Cada lista trae primero lo que espera.
        _Pestanas(
          nombres: const ['Compras', 'Gastos', 'Adelantos', 'Movimientos'],
          anchoPorNombre: true,
          elegida: _pestana,
          onElegir: (i) {
            setState(() => _pestana = i);
            if (i < 3 && _filas[i].isEmpty) _mas(i);
            if (i == 3 && _movimientos.isEmpty) _masMovimientos();
          },
        ),
        if (_pestana == 3) ..._listaMovimientos(),
        if (_pestana < 3) const SizedBox(height: 12),
        for (final f in filas)
          if (_pestana == 0) _filaCompra(f) else if (_pestana == 1) _filaGasto(f) else _filaAdelanto(f),
        if (_pestana == 3)
          const SizedBox.shrink()
        else if (_errores[_pestana] != null)
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
    final espera = _esperaFila(c);
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
    final espera = _esperaFila(g);
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

class _FincaScreenState extends _ProcesoState<_FincaScreen> with _ProveedoresDelProceso, _GastosDelArea, _ReporteDelProceso {
  // Rediseñada con el área (General Manager, 4 nov 2026; la propuesta de Finca): sin datos arriba, Registrar gasto,
  // pestañas Gastos | Proveedores y el reporte en PDF. Parcelas, cosechas, labores, lluvia y plagas vendrán con sus
  // formularios; hoy no se muestran pestañas vacías.
  int _pestana = 0; // 0 Gastos, 1 Proveedores

  @override
  String get clave => 'finca';
  @override
  String? get areaProveedores => 'farm';
  @override
  String get areaGastos => 'farm';
  @override
  String get vacioGastos => 'Todavía no hay gastos de la finca.';
  @override
  bool get duenoGastos => widget.esDueno;

  @override
  String get nombreReporte => 'Finca';
  @override
  Future<ApiResponse<Map<String, dynamic>>> pedirReporte(DateTime desde, DateTime hasta) => AdministracionService.reporteFinca(desde, hasta);
  @override
  Future<Uint8List> armarPdf(Map<String, dynamic> reporte) => FincaPdfService.generarBytes(reporte);

  /// El resumen y, en la pestaña Gastos (la primera), sus gastos desde el comienzo (también después de Registrar gasto).
  @override
  Future<void> cargar() async {
    if (_pestana == 0) cargarGastos();
    await super.cargar();
  }

  @override
  Widget build(BuildContext context) {
    return pantalla('Finca', botonFlotante: botonReporte(), alFinal: () {
      if (_pestana == 0) masGastos();
      if (_pestana == 1) masProveedores();
    }, (d) {
      return [
        // Sin datos arriba (General Manager, 4 nov 2026): la tarjeta de Procesos ya los muestra.
        _Acciones(acciones: [
          (
            Icons.receipt_long,
            _titulos['gasto']!, // el mismo nombre en cada proceso; el área va fija (General Manager, 3 nov 2026)
            () => formulario('gasto', fijos: const {'area': 'farm'}, subtitulo: 'Área: Finca')
          ),
        ]),
        _Pestanas(
          nombres: const ['Gastos', 'Proveedores'],
          anchoPorNombre: true,
          elegida: _pestana,
          onElegir: (i) {
            setState(() => _pestana = i);
            if (i == 0) cargarGastos();
            if (i == 1) abrirProveedores();
          },
        ),
        if (_pestana == 1) ..._listaProveedores() else ...listaGastos(),
      ];
    });
  }
}

/// Botón flotante de reporte en PDF de un proceso (General Manager, 4 nov 2026: Compras, luego Producción): abre
/// Generar reporte (Mensual con fecha de inicio y de fin, o Anual), pide el reporte recién entonces y muestra el PDF
/// para compartir. Cada proceso dice su nombre, cómo pedir su reporte y cómo armar su PDF.
/// Generar reporte con el mismo formulario de Administración (Mensual o Anual, Desde y Hasta; como máximo 12 meses) y
/// el PDF en pantalla, para compartir. Lo usan los procesos y, desde el 5 nov 2026, el detalle de un cliente.
/// [alGenerar] avisa cuándo empieza (true) y termina (false), para mostrar la carga en el botón.
Future<void> generarReportePdf(
  BuildContext context, {
  required String nombre,
  required Future<ApiResponse<Map<String, dynamic>>> Function(DateTime desde, DateTime hasta) pedir,
  required Future<Uint8List> Function(Map<String, dynamic> reporte) armar,
  ValueChanged<bool>? alGenerar,
}) async {
  final rango = await _abrirPantalla<(DateTime, DateTime)>(context, const _ReporteComprasForm());
  if (rango == null || !context.mounted) return;
  final (desde, hasta) = rango;
  alGenerar?.call(true);
  try {
    final r = await pedir(desde, hasta);
    if (!context.mounted) return;
    if (!r.isSuccess) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(r.error ?? 'No se pudo generar el reporte')));
      return;
    }
    final bytes = await armar(_mapa(r.data!['reporte']));
    if (!context.mounted) return;
    String m(DateTime d) => '${d.year}_${d.month.toString().padLeft(2, '0')}';
    final base = nombre.toLowerCase().replaceAll('ó', 'o').replaceAll(RegExp(r'[^a-z0-9]+'), '_');
    final archivo = desde == hasta ? '${base}_${m(desde)}.pdf' : '${base}_${m(desde)}_a_${m(hasta)}.pdf';
    await _abrirPantalla<void>(context, _ReportePdfScreen(bytes: bytes, archivo: archivo, titulo: '$nombre · ${ComprasPdfService.periodo(desde, hasta)}'));
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No se pudo generar el PDF: revisa la señal.')));
    }
  } finally {
    alGenerar?.call(false);
  }
}

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

  Future<void> _elegirReporte() => generarReportePdf(context,
      nombre: nombreReporte,
      pedir: pedirReporte,
      armar: armarPdf,
      alGenerar: (g) {
        if (mounted) setState(() => _generando = g);
      });
}

/// Pestaña Gastos de un proceso (General Manager, 4 nov 2026: Compras, luego Producción): los gastos de su área con su
/// estado, los últimos 30 (de Mi área, que ya respeta las áreas de la persona); el monto lo dice la base.
mixin _GastosDelArea<T extends StatefulWidget> on State<T> {
  String get areaGastos; // 'sourcing', 'production', 'fulfillment', 'farm'
  String get vacioGastos;
  bool get duenoGastos => false; // los dueños ven y suben la evidencia en el detalle
  // De 20 en 20 desde el servidor al llegar al final, lo más nuevo primero (4 nov 2026); cada gasto abre su detalle.
  final List<Map<String, dynamic>> _gastos = [];
  bool _cargandoGastos = false;
  bool _hayMasGastos = true;
  bool _gastosPedidos = false;
  String? _errorGastos;
  int _vueltaGastos = 0;

  /// Vuelve a empezar la lista (al abrir la pestaña).
  Future<void> cargarGastos() async {
    _vueltaGastos++;
    _gastos.clear();
    _cargandoGastos = false;
    _hayMasGastos = true;
    _errorGastos = null;
    _gastosPedidos = true;
    await masGastos();
  }

  Future<void> masGastos() async {
    if (_cargandoGastos || !_hayMasGastos) return;
    final vuelta = _vueltaGastos;
    setState(() => _cargandoGastos = true);
    final r = await AdministracionService.gastosArea(areaGastos, desde: _gastos.length);
    if (!mounted || vuelta != _vueltaGastos) return;
    setState(() {
      _cargandoGastos = false;
      if (r.isSuccess) {
        _gastos.addAll(_lista(r.data!['gastos']));
        _hayMasGastos = r.data!['hayMas'] == true;
      } else {
        _errorGastos = r.error ?? 'No se pudo cargar';
        _hayMasGastos = false;
      }
    });
  }

  List<Widget> listaGastos() {
    if (_errorGastos != null && _gastos.isEmpty) return [Padding(padding: const EdgeInsets.all(16), child: Text(_errorGastos!, textAlign: TextAlign.center))];
    return [
      const SizedBox(height: 8),
      if (_gastos.isEmpty && !_cargandoGastos && _gastosPedidos) _vacio(vacioGastos),
      for (final g in _gastos)
        _Ficha(
          inicio: _Insignia(_fechaCorta(g['expense_date']), tono: Colors.orange),
          titulo: '${g['category'] ?? 'Gasto'}',
          detalle: [
            _soles(g['amount']),
            if ((g['description'] ?? '').toString().isNotEmpty) '${g['description']}',
          ].join(' · '),
          // La base dice "Pagado" o "Pendiente de pago"; el mismo naranja que lo que espera en Finanzas.
          fin: g['status'] == 'Pagado' ? const _Pildora('Pagado', Colors.green) : const _Pildora('Pendiente', Colors.orange),
          onTap: () => _abrirPantalla<void>(context, _GastoDetalleScreen(gasto: g, esDueno: duenoGastos)),
        ),
      // Sin texto al final de la lista: sólo la carga mientras llega la siguiente página.
      if (_cargandoGastos || !_gastosPedidos) const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
    ];
  }
}

/// Detalle de un gasto de un área (4 nov 2026): sus datos y, para los dueños, su evidencia. Sólo Finanzas paga: aquí no
/// hay botón de pagar (General Manager, 3 nov 2026).
class _GastoDetalleScreen extends StatelessWidget {
  const _GastoDetalleScreen({required this.gasto, required this.esDueno});
  final Map<String, dynamic> gasto;
  final bool esDueno;

  @override
  Widget build(BuildContext context) {
    final g = gasto;
    final pagado = g['status'] == 'Pagado';
    Widget dato(String nombre, String? valor) => valor == null || valor.isEmpty || valor == 'null'
        ? const SizedBox.shrink()
        : Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.grey.shade300))),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(width: 130, child: Text(nombre, style: TextStyle(color: Colors.grey.shade700))),
              Expanded(child: Text(valor, style: const TextStyle(fontWeight: FontWeight.w600))),
            ]),
          );
    return Scaffold(
      appBar: AppBar(title: const Text('Gasto')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Row(children: [
          Expanded(child: Text('${g['category'] ?? 'Gasto'}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold))),
          _Pildora(pagado ? 'Pagado' : 'Pendiente', pagado ? Colors.green : Colors.orange),
        ]),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(16)),
          child: Column(children: [
            dato('Monto', g['amount'] == null ? null : _soles(g['amount'])),
            dato('Fecha', g['expense_date'] == null ? null : _fechaLarga(g['expense_date'])),
            dato('Descripción', g['description']?.toString()),
            dato('Gasto', g['id']?.toString()),
            dato('Registrado por', g['created_by']?.toString()),
          ].where((w) => w is! SizedBox).toList()),
        ),
        if (!pagado)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text('Lo paga Finanzas.', style: TextStyle(color: Colors.grey.shade700)),
          ),
        if (esDueno && g['id'] != null) ...[
          const SizedBox(height: 16),
          SizedBox(
            height: 48,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.attach_file),
              label: const Text('Ver evidencia'),
              onPressed: () => _abrirPantalla<void>(context, _EvidenciasScreen(tipo: 'expense', id: '${g['id']}', titulo: '${g['category'] ?? 'Gasto'}')),
            ),
          ),
        ],
      ]),
    );
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
  bool get duenoGastos => widget.esDueno;

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
        alFinal: _pestana == 3 ? masGastos : (_pestana == 2 ? masProveedores : (_pestana == 0 ? _masCompras : _masAdelantos)),
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
                                cacheWidth: _anchoMiniatura(context, 3),
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
  const _ComercialScreen({this.esDueno = false});
  final bool esDueno;

  @override
  State<_ComercialScreen> createState() => _ComercialScreenState();
}

/// Comercialización como los demás procesos (General Manager, 4 nov 2026; lo propuso el área Comercial y la General
/// Manager lo ajustó el mismo día): sin datos arriba, Registrar gasto, pestañas Clientes | Proveedores | Gastos |
/// Últimos pagos (de 20 en 20) y el reporte en PDF. Sin pestañas Pedidos ni Productos, ni Registrar pedido. Sin "Por
/// cobrar": el estado de pago de los pedidos todavía no cuadra.
class _ComercialScreenState extends _ProcesoState<_ComercialScreen> with _ProveedoresDelProceso, _GastosDelArea, _ReporteDelProceso {
  // Primero Clientes, luego Gastos y al final Últimos pagos (General Manager, 4 nov 2026); Proveedores después de
  // Clientes, como en los demás procesos (General Manager, 6 nov 2026).
  int _pestana = 0; // 0 Clientes, 1 Proveedores, 2 Gastos, 3 Últimos pagos

  /// La lista de cada pestaña: 0 pagos, 1 clientes (Proveedores y Gastos tienen la suya).
  static int? _listaDe(int pestana) => pestana == 0 ? 1 : (pestana == 3 ? 0 : null);

  @override
  String get clave => 'comercial';
  @override
  String? get areaProveedores => 'commercial';
  @override
  String get vacioProveedores => 'Todavía no hay proveedores de Comercialización.';
  @override
  String get areaGastos => 'commercial';
  @override
  String get vacioGastos => 'Todavía no hay gastos de Comercialización.';
  @override
  bool get duenoGastos => widget.esDueno;

  @override
  String get nombreReporte => 'Comercialización';
  @override
  Future<ApiResponse<Map<String, dynamic>>> pedirReporte(DateTime desde, DateTime hasta) => AdministracionService.reporteComercial(desde, hasta);
  @override
  Future<Uint8List> armarPdf(Map<String, dynamic> reporte) => ComercialPdfService.generarBytes(reporte);

  // Pagos y clientes: de 20 en 20 desde el servidor, al llegar al final.
  final _filas = [<Map<String, dynamic>>[], <Map<String, dynamic>>[]];
  final _cargandoFilas = [false, false];
  final _hayMasFilas = [true, true];
  final _erroresFilas = <String?>[null, null];
  int _vuelta = 0;

  @override
  Future<void> cargar() async {
    _vuelta++;
    for (var i = 0; i < 2; i++) {
      _filas[i].clear();
      _cargandoFilas[i] = false;
      _hayMasFilas[i] = true;
      _erroresFilas[i] = null;
    }
    final l = _listaDe(_pestana);
    if (_pestana == 1) recargarProveedores();
    if (_pestana == 2) cargarGastos();
    await Future.wait([super.cargar(), if (l != null) _mas(l)]);
  }

  Future<void> _mas(int i) async {
    if (_cargandoFilas[i] || !_hayMasFilas[i]) return;
    final vuelta = _vuelta;
    setState(() => _cargandoFilas[i] = true);
    final r = i == 0
        ? await AdministracionService.pagosComercial(desde: _filas[0].length)
        : await AdministracionService.clientesComercial(desde: _filas[1].length);
    if (!mounted || vuelta != _vuelta) return;
    setState(() {
      _cargandoFilas[i] = false;
      if (r.isSuccess) {
        _filas[i].addAll(_lista(r.data![i == 0 ? 'pagos' : 'clientes']));
        _hayMasFilas[i] = r.data!['hay_mas'] == true;
      } else {
        _erroresFilas[i] = r.error ?? 'No se pudo cargar.';
        _hayMasFilas[i] = false;
      }
    });
  }

  /// Un pago registrado en un pedido: cuándo, el cliente, el pedido y el monto (dueños); si tiene comprobante
  /// verificado. Abre el pedido completo, el mismo detalle que la pestaña Pedidos.
  Widget _filaPago(Map<String, dynamic> p) {
    final verificado = p['verificado'] == true;
    final comprobantes = (p['comprobantes'] as num?)?.toInt() ?? 0;
    final pedido = p['pedido'] is Map ? Map<String, dynamic>.from(p['pedido'] as Map) : null;
    return _Ficha(
      inicio: _Insignia(_fechaCorta(p['fecha']), tono: Colors.green),
      titulo: '${p['cliente'] ?? 'Sin nombre'}',
      detalle: ['Pedido ${p['numero'] ?? ''}', if (p['monto'] != null) _soles(p['monto'])].join(' · '),
      fin: verificado
          ? const _Pildora('Verificado', Colors.green)
          : comprobantes > 0
              ? const _Pildora('Por verificar', Colors.orange)
              : const _Pildora('Sin comprobante', Colors.grey),
      onTap: pedido == null
          ? null
          : () => showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                backgroundColor: Colors.transparent,
                builder: (_) => DetallePedidoSheet(pedido: pedido, onActualizado: cargar),
              ),
    );
  }

  List<Widget> _listaComercial(int i) {
    final filas = _filas[i];
    return [
      if (filas.isEmpty && !_cargandoFilas[i])
        _vacio(_erroresFilas[i] ?? const ['Todavía no hay pagos registrados.', 'Todavía no hay clientes.'][i]),
      for (final f in filas)
        if (i == 0)
          _filaPago(f)
        else
          _Ficha(
            inicio: _Insignia(_fechaCorta(f['ultimo']), tono: Colors.blue),
            titulo: '${f['nombre'] ?? 'Sin nombre'}',
            detalle: [
              '${f['pedidos']} ${f['pedidos'] == 1 ? 'pedido' : 'pedidos'}',
              if (f['total'] != null) _soles(f['total']),
              if (f['primero'] != null) 'desde ${_fechaCorta(f['primero'])}',
            ].join(' · '),
            onTap: () => _abrirPantalla<void>(context, _ClienteComercialScreen(cliente: f)),
          ),
      if (_cargandoFilas[i]) const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return pantalla('Comercialización', botonFlotante: botonReporte(), alFinal: () {
      final l = _listaDe(_pestana);
      if (l != null) _mas(l);
      if (_pestana == 1) masProveedores();
      if (_pestana == 2) masGastos();
    }, (d) {
      return [
        // Sin datos arriba (General Manager, 4 nov 2026): la tarjeta de Procesos ya los muestra.
        _Acciones(acciones: [
          (
            Icons.receipt_long,
            _titulos['gasto']!, // el mismo nombre en cada proceso; el área va fija (General Manager, 3 nov 2026)
            () => formulario('gasto', fijos: const {'area': 'commercial'}, subtitulo: 'Área: Comercial')
          ),
          // Registrar proveedor (General Manager, 6 nov 2026): el proveedor queda en Comercialización (su pestaña
          // Proveedores); el área va fija y "Proveedor de insumos" ya viene elegido.
          (
            Icons.person_add_alt_1,
            _titulos['proveedor']!,
            () => formulario('proveedor', fijos: const {'area': 'commercial'}, subtitulo: 'Área: Comercial', iniciales: const {'rol': 'supplier'})
          ),
        ]),
        _Pestanas(
          nombres: const ['Clientes', 'Proveedores', 'Gastos', 'Últimos pagos'],
          anchoPorNombre: true,
          elegida: _pestana,
          onElegir: (i) {
            setState(() => _pestana = i);
            final l = _listaDe(i);
            if (l != null && _filas[l].isEmpty) _mas(l);
            if (i == 1) abrirProveedores();
            if (i == 2) cargarGastos();
          },
        ),
        if (_pestana == 1)
          ..._listaProveedores()
        else if (_pestana == 2)
          ...listaGastos()
        else
          ..._listaComercial(_listaDe(_pestana)!),
      ];
    });
  }
}

/// Un pedido de la tienda en una lista (Logística, Comercialización): fecha, cliente, número y estado; abre el mismo
/// detalle que la pestaña Pedidos.
const _estadosPedido = {
  'PENDIENTE': 'Pendiente',
  'CONFIRMADO': 'Confirmado',
  'EN_PREPARACION': 'Preparando',
  'LISTO': 'Listo',
  'ENVIADO': 'En camino',
  'ENTREGADO': 'Entregado',
  'COMPLETADO': 'Completado',
  'CANCELADO': 'Cancelado',
};

String _fechaPedidoCorta(dynamic f) {
  final p = '${f ?? ''}'.split('/');
  if (p.length != 3) return '${f ?? ''}';
  final d = DateTime.tryParse('${p[2]}-${p[1].padLeft(2, '0')}-${p[0].padLeft(2, '0')}');
  return d == null ? '${f ?? ''}' : _fechaCorta(d.toIso8601String());
}

Widget _fichaPedido(BuildContext context, Map<String, dynamic> p, {required VoidCallback onActualizado}) {
  final estado = '${p['estado'] ?? ''}';
  final color = estado == 'ENTREGADO' || estado == 'COMPLETADO'
      ? Colors.green
      : estado == 'CANCELADO'
          ? Colors.grey
          : estado == 'ENVIADO'
              ? Colors.blue
              : Colors.orange;
  return _Ficha(
    inicio: _Insignia(_fechaPedidoCorta(p['fecha']), tono: color),
    titulo: '${(p['cliente'] ?? '').toString().isEmpty ? 'Sin nombre' : p['cliente']}',
    detalle: 'Pedido ${p['id'] ?? ''}',
    fin: _Pildora(_estadosPedido[estado] ?? estado, color),
    onTap: () => showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DetallePedidoSheet(pedido: p, onActualizado: onActualizado),
    ),
  );
}

/// Un pedido en el detalle de un cliente (General Manager, 5 nov 2026, en lugar de Estadísticas): la fecha, el número,
/// el total y si está pagado, en parte o sin pagar (por los pagos registrados), y su estado; abre el mismo detalle que
/// la pestaña Pedidos.
Widget fichaPedidoCliente(BuildContext context, Map<String, dynamic> p, {required VoidCallback onActualizado}) {
  final estado = '${p['estado'] ?? ''}';
  final color = estado == 'ENTREGADO' || estado == 'COMPLETADO'
      ? Colors.green
      : estado == 'CANCELADO'
          ? Colors.grey
          : estado == 'ENVIADO'
              ? Colors.blue
              : Colors.orange;
  final total = num.tryParse('${p['total']}') ?? 0;
  final pagado = num.tryParse('${p['montoPagado']}') ?? 0;
  final pago = estado == 'CANCELADO'
      ? null
      : pagado >= total && total > 0
          ? 'Pagado'
          : pagado > 0
              ? 'Parcial · debe ${_soles(total - pagado)}'
              : 'Sin pagar';
  return _Ficha(
    inicio: _Insignia(_fechaPedidoCorta(p['fecha']), tono: color),
    titulo: 'Pedido ${p['id'] ?? ''}',
    detalle: [_soles(total), if (pago != null) pago].join(' · '),
    fin: _Pildora(_estadosPedido[estado] ?? estado, color),
    onTap: () => showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DetallePedidoSheet(pedido: p, onActualizado: onActualizado),
    ),
  );
}

/// Un cliente de Comercialización (4 nov 2026): sus datos (teléfono y total sólo para dueños) y sus pedidos, de 20 en
/// 20; cada pedido abre su detalle.
class _ClienteComercialScreen extends StatefulWidget {
  const _ClienteComercialScreen({required this.cliente});
  final Map<String, dynamic> cliente;

  @override
  State<_ClienteComercialScreen> createState() => _ClienteComercialScreenState();
}

class _ClienteComercialScreenState extends State<_ClienteComercialScreen> {
  final _pedidos = <Map<String, dynamic>>[];
  int _pagina = 0;
  bool _hayMas = true;
  bool _cargando = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _mas();
  }

  Future<void> _mas() async {
    if (_cargando || !_hayMas) return;
    setState(() => _cargando = true);
    final r = await ApiService.getPedidos(cliente: '${widget.cliente['nombre'] ?? ''}', pagina: _pagina + 1, limite: 20);
    if (!mounted) return;
    setState(() {
      _cargando = false;
      if (r.isSuccess && r.data != null) {
        _pedidos.addAll(r.data!.pedidos);
        _pagina++;
        _hayMas = r.data!.hayMas;
      } else {
        _error = r.error ?? 'No se pudieron cargar los pedidos.';
        _hayMas = false;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.cliente;
    Widget dato(String nombre, String? valor) => valor == null || valor.isEmpty
        ? const SizedBox.shrink()
        : Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.grey.shade300))),
            child: Row(children: [
              SizedBox(width: 130, child: Text(nombre, style: TextStyle(color: Colors.grey.shade700))),
              Expanded(child: Text(valor, style: const TextStyle(fontWeight: FontWeight.w600))),
            ]),
          );
    return Scaffold(
      appBar: AppBar(title: const Text('Cliente')),
      body: NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (n.metrics.extentAfter < 300) _mas();
          return false;
        },
        child: ListView(padding: const EdgeInsets.all(16), children: [
          Text('${c['nombre'] ?? 'Sin nombre'}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(16)),
            child: Column(children: [
              dato('Pedidos', '${c['pedidos'] ?? 0}'),
              dato('Total comprado', c['total'] == null ? null : _soles(c['total'])),
              dato('Primer pedido', c['primero'] == null ? null : _fechaLarga(c['primero'])),
              dato('Último pedido', c['ultimo'] == null ? null : _fechaLarga(c['ultimo'])),
              dato('Teléfono', c['telefono']?.toString()),
              dato('Correo', c['email']?.toString()),
            ].where((w) => w is! SizedBox).toList()),
          ),
          _encabezado('Pedidos', ''),
          if (_pedidos.isEmpty && !_cargando) _vacio(_error ?? 'Sin pedidos.'),
          for (final p in _pedidos) _fichaPedido(context, p, onActualizado: () {}),
          if (_cargando) const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
        ]),
      ),
    );
  }
}

// ─── Producción ──────────────────────────────────────────────────────────────

class _ProduccionScreen extends StatefulWidget {
  const _ProduccionScreen({this.esDueno = false});
  final bool esDueno; // Cerrar lote y Agregar café al lote: sólo dueños (la base de datos también lo revisa)

  @override
  State<_ProduccionScreen> createState() => _ProduccionScreenState();
}

class _ProduccionScreenState extends _ProcesoState<_ProduccionScreen> with _ProveedoresDelProceso, _GastosDelArea, _ReporteDelProceso {
  int? _pestana; // 0 Café verde, 1 Tostado, 2 Proveedores, 3 Gastos; abre en Café verde (General Manager, 4 nov 2026)

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
  bool get duenoGastos => widget.esDueno;

  @override
  String? get areaProveedores => 'production';

  @override
  String get clave => 'produccion';

  /// Tostar café: se elige el producto (el café que sale del tueste) y se abre el formulario para empezar a tostar, con
  /// el lote del producto ya elegido; el evento se crea por dentro y se inicia en el mismo paso (General Manager, 5 nov
  /// 2026).
  Future<void> _tostar() async {
    final producto = await _abrirPantalla<Map<String, dynamic>>(context, const _ElegirProducto());
    if (producto == null || !mounted) return;
    final r = await AdministracionService.loteDelProducto('${producto['codigo'] ?? ''}');
    if (!mounted) return;
    final lote = r.isSuccess ? _mapa(r.data!['lote']) : const <String, dynamic>{};
    await abrirProgramarTueste(context, producto,
        onCreado: cargar, iniciarAhora: true, loteId: lote['id']?.toString(), loteCodigo: lote['codigo']?.toString());
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

  Future<void> _abrirLote(Map<String, dynamic> lote) async {
    final cambio = await _abrirPantalla<bool>(context, _LoteVerdeDetalleScreen(id: '${lote['id']}', esDueno: widget.esDueno));
    if (cambio == true) cargar();
  }

  void _aviso(String texto) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(texto)));
  }

  /// Un tueste en curso o programado, con Iniciar o Finalizar. Bajo su producto no repite el nombre.
  Widget _filaTueste(Map<String, dynamic> t, {bool conProducto = false}) {
    final tostando = t['estado'] == 'in_progress';
    final estado = tostando ? 'Tostando' : 'Programado';
    return _Ficha(
      inicio: _Insignia('${t['lote'] ?? '—'}', tono: tostando ? Colors.deepOrange : Colors.blue),
      titulo: conProducto ? estado : '${t['producto'] ?? 'Lote ${t['lote'] ?? ''}'}',
      detalle: '${conProducto ? '' : '$estado · '}${_kg(t['kg_verde'])} verde · ${_fechaCorta(t['fecha'])}',
      fin: tostando
          ? ElevatedButton(onPressed: () => _finalizar(t), child: const Text('Finalizar'))
          : OutlinedButton(onPressed: () => _iniciar(t), child: const Text('Iniciar')),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Reporte en PDF como Compras (General Manager, 4 nov 2026); el contenido lo decidió el área de Producción.
    return pantalla('Producción', botonFlotante: botonReporte(), alFinal: () {
      if (_pestana == 2) masProveedores();
      if (_pestana == 3) masGastos();
    }, (d) {
      final lotes = _lista(d['lotes_verdes']);
      final tuestes = _lista(d['tuestes']);
      // El café tostado se maneja por producto, como en la pantalla del producto (General Manager, 4 nov 2026):
      // cada producto con su tostado disponible, sus lotes y sus tuestes (production_summary_v2).
      final productos = _lista(d['productos']);
      final conProducto = {for (final p in productos) for (final t in _lista(p['tuestes'])) '${t['id']}'};
      final sinProducto = tuestes.where((t) => !conProducto.contains('${t['id']}')).toList();
      final pestana = _pestana ?? 0;
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
        // Lo que se está tostando, con su contador, debajo de los dos botones y en cualquier pestaña: al iniciar un
        // tueste la persona se queda en Producción y lo ve en marcha (General Manager, 5 nov 2026).
        for (final t in tuestes.where((t) => t['estado'] == 'in_progress'))
          Padding(padding: const EdgeInsets.only(top: 10), child: _ContadorTueste(tueste: t, onFinalizar: () => _finalizar(t))),
        _Pestanas(
          // Gastos, y "Lotes de tostado" y "Café verde" en vez de Tuestes y Lotes: General Manager, 4 nov 2026
          // Café verde antes que Tostado (antes "Lotes de tostado"; General Manager, 4 nov 2026).
          nombres: const ['Café verde', 'Tostado', 'Proveedores', 'Gastos'],
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
        else if (pestana == 1) ...[
          // Sin título ni total arriba (General Manager, 4 nov 2026): los productos en el orden de la pestaña Productos.
          if (productos.isEmpty && sinProducto.isEmpty) _vacio('No hay café tostado ni lotes de tostado programados. Toca "Tostar café".'),
          for (final p in productos) ...[
            // Los kilos una sola vez: en cada lote; el total del producto sólo si tiene más de un lote.
            _NombreProducto(nombre: '${p['nombre'] ?? 'Producto'}', kg: _lista(p['lotes']).length > 1 ? _kg(p['kg_tostado']) : null),
            if (_lista(p['lotes']).isEmpty && _lista(p['tuestes']).isEmpty) _vacio('Sin lotes tostados disponibles.'),
            for (final l in _lista(p['lotes']))
              _Ficha(
                inicio: _Insignia('${l['lote'] ?? '—'}', tono: Colors.orange),
                // Sólo la fecha, sin "Tostado el": en esta pestaña todo es tostado; como "Lunes 2 de noviembre" (General Manager, 4 nov 2026).
                titulo: _fechaLarga(l['fecha']),
                fin: Text(_kg(l['kg']), style: const TextStyle(fontWeight: FontWeight.w600)),
                // Cada lote tostado abre su detalle (General Manager, 4 nov 2026).
                onTap: l['id'] == null
                    ? null
                    : () => _abrirPantalla<void>(
                        context, _TostadoDetalleScreen(id: '${l['id']}', producto: '${p['nombre'] ?? ''}', productoId: p['id']?.toString())),
              ),
            for (final t in _lista(p['tuestes'])) _filaTueste(t, conProducto: true),
          ],
          // Un tueste sin producto (no debería pasar) se ve igual, para poder iniciarlo o finalizarlo.
          if (sinProducto.isNotEmpty) ...[
            _NombreProducto(nombre: 'Sin producto'),
            for (final t in sinProducto) _filaTueste(t),
          ],
        ] else ...[
          _encabezado('Lotes de café verde', '${lotes.length} ${lotes.length == 1 ? 'lote' : 'lotes'}'),
          if (lotes.isEmpty) _vacio('No hay lotes de café verde con stock.'),
          // Cada lote abre su detalle, y las acciones están adentro (General Manager, 4 nov 2026).
          for (final l in lotes)
            _FilaLote(lote: l, onTap: () => _abrirLote(l)),
          // Sin "Café comprado por procesar" (General Manager, 4 nov 2026).
        ],
      ];
    });
  }
}

/// Detalle de un lote de tostado (General Manager, 4 nov 2026): qué entró y salió, la merma, para cada producto lo
/// asignado, vendido y disponible, los datos del tueste que se registraron, el lote verde, las notas y las fotos.
/// Sólo lectura: todo es información (roast_lot_detail).
class _TostadoDetalleScreen extends StatefulWidget {
  const _TostadoDetalleScreen({required this.id, required this.producto, this.productoId});
  final String id;
  final String producto;
  final String? productoId; // para su Estado de lote: lo que se tostó para este producto y lo que se vendió

  @override
  State<_TostadoDetalleScreen> createState() => _TostadoDetalleScreenState();
}

class _TostadoDetalleScreenState extends State<_TostadoDetalleScreen> {
  Map<String, dynamic>? _t;
  String? _error;
  // Estado de lote (General Manager, 4 nov 2026): el tueste suma y cada venta resta; del servidor de 20 en 20.
  final _lineas = <Map<String, dynamic>>[];
  Map<String, dynamic> _cuenta = const {};
  bool _hayMas = false;
  bool _cargandoMas = false;
  int _pedido = 0;
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _cargar();
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 200) _masLineas();
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _masLineas({bool desdeCero = false}) async {
    if (widget.productoId == null) return;
    if (!desdeCero && (_cargandoMas || !_hayMas)) return;
    final pedido = desdeCero ? ++_pedido : _pedido;
    setState(() => _cargandoMas = true);
    final r = await AdministracionService.cuentaTostado(widget.id, widget.productoId!, desde: desdeCero ? 0 : _lineas.length);
    if (!mounted || pedido != _pedido) return;
    setState(() {
      _cargandoMas = false;
      if (!r.isSuccess) {
        _hayMas = false;
        return;
      }
      final c = _mapa(r.data!['cuenta']);
      if (desdeCero) _lineas.clear();
      _lineas.addAll(_lista(c['lineas']));
      _cuenta = c;
      _hayMas = c['hay_mas'] == true;
    });
  }

  Future<void> _cargar() async {
    _masLineas(desdeCero: true);
    final r = await AdministracionService.tostado(widget.id);
    if (!mounted) return;
    setState(() {
      _error = r.isSuccess ? null : (r.error ?? 'No se pudo cargar el lote de tostado.');
      if (r.isSuccess) _t = _mapa(r.data!['tostado']);
    });
  }

  static String? _minutos(dynamic s) {
    final n = num.tryParse('${s ?? ''}');
    if (n == null) return null;
    final m = n ~/ 60, r = (n % 60).round();
    return '$m:${r.toString().padLeft(2, '0')} min';
  }

  static String? _fechaHora(dynamic iso) {
    final d = DateTime.tryParse('${iso ?? ''}')?.toLocal();
    if (d == null) return null;
    return '${_fechaCorta(iso)} ${d.year}, ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  Widget _dato(String nombre, String? valor) => valor == null || valor.isEmpty || valor == 'null'
      ? const SizedBox.shrink()
      : Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.grey.shade300))),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 150, child: Text(nombre, style: TextStyle(color: Colors.grey.shade700))),
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

  String? _num(dynamic v, String unidad) => v == null ? null : '$v $unidad';

  @override
  Widget build(BuildContext context) {
    final t = _t;
    final verde = t == null ? const <String, dynamic>{} : _mapa(t['verde']);
    final productos = t == null ? const <Map<String, dynamic>>[] : _lista(t['productos']);
    final media = t == null ? const <dynamic>[] : (t['media'] is List ? t['media'] as List : const <dynamic>[]);
    final sensoriales = t == null || t['notas_sensoriales'] is! List ? null : (t['notas_sensoriales'] as List).join(', ');
    return Scaffold(
      appBar: AppBar(title: const Text('Lote de tostado')),
      body: RefreshIndicator(
        onRefresh: _cargar,
        child: t == null
            ? ListView(children: [
                Padding(
                  padding: const EdgeInsets.all(32),
                  child: _error != null ? Text(_error!, textAlign: TextAlign.center) : const Center(child: CircularProgressIndicator()),
                ),
              ])
            : ListView(controller: _scroll, padding: const EdgeInsets.all(16), children: [
                Row(children: [
                  Expanded(child: Text(widget.producto, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold))),
                  _Insignia('${t['lote'] ?? '—'}', tono: Colors.orange),
                ]),
                const SizedBox(height: 4),
                Text('Tostado el ${_fechaCorta(t['tostado_el'])}', style: TextStyle(color: Colors.grey.shade700)),
                _panel('Café', [
                  _dato('Café verde que entró', t['kg_verde'] == null ? null : _kg(t['kg_verde'])),
                  _dato('Café tostado que salió', t['kg_tostado'] == null ? null : _kg(t['kg_tostado'])),
                  _dato('Merma', t['merma_pct'] == null ? null : '${t['merma_pct']}%'),
                ]),
                for (final p in productos)
                  _panel(productos.length > 1 ? '${p['nombre'] ?? 'Producto'}' : 'Para el producto', [
                    _dato('Asignado', _kg(p['asignado'])),
                    _dato('Vendido', _kg(p['vendido'])),
                    _dato('Disponible', _kg(p['disponible'])),
                  ]),
                _panel('Tueste', [
                  _dato('Empezó', _fechaHora(t['tostado_el'])),
                  _dato('Terminó', _fechaHora(t['terminado_el'])),
                  _dato('Tostadora', t['tostadora']?.toString()),
                  _dato('Nivel de tueste', t['nivel']?.toString()),
                  _dato('Temperatura de carga', _num(t['temp_carga'], '°C')),
                  _dato('Temperatura de salida', _num(t['temp_salida'], '°C')),
                  _dato('Tiempo total', _minutos(t['tiempo_s'])),
                  _dato('Primer crack', _minutos(t['primer_crack_s'])),
                  _dato('Notas sensoriales', sensoriales),
                ]),
                _panel('Lote verde', [
                  _dato('Lote', verde['lote']?.toString()),
                  _dato('Variedad', verde['variedad']?.toString()),
                  _dato('Cosecha', verde['cosecha']?.toString()),
                  _dato('Origen', verde['origen']?.toString()),
                ]),
                if (t['notas'] != null)
                  _panel('Notas', [
                    Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: SizedBox(width: double.infinity, child: Text('${t['notas']}'))),
                  ]),
                if (media.isNotEmpty) ...[
                  const Padding(
                      padding: EdgeInsets.fromLTRB(4, 16, 4, 6),
                      child: Text('Fotos y videos', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
                  GridView.count(
                    crossAxisCount: 3,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 6,
                    crossAxisSpacing: 6,
                    children: [
                      for (final u in media.map((e) => '$e'))
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: RegExp(r'\.(mp4|mov)$', caseSensitive: false).hasMatch(u)
                              ? Container(
                                  color: Colors.orange.shade50,
                                  child: Icon(Icons.videocam_outlined, color: Colors.orange.shade700, size: 32))
                              : Image.network(u,
                                  fit: BoxFit.cover,
                                  cacheWidth: _anchoMiniatura(context, 3),
                                  errorBuilder: (_, __, ___) =>
                                      Container(color: Colors.grey.shade200, child: Icon(Icons.broken_image_outlined, color: Colors.grey.shade500))),
                        ),
                    ],
                  ),
                ],
                // Estado de lote al final, porque se carga de 20 en 20 al llegar abajo (General Manager, 4 nov 2026).
                if (widget.productoId != null) ...[
                  _encabezado('Estado de lote', _cuenta['total'] == null ? '' : '${_cuenta['total']}'),
                  // Sin panel de saldo: "Para el producto" ya muestra asignado, vendido y disponible (los kilos una sola vez).
                  for (final m in _lineas) _LineaCuenta(linea: m),
                  if (_lineas.isEmpty && !_cargandoMas) _vacio('Este lote todavía no tiene movimientos.'),
                  if (_cargandoMas) const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
                ],
                const SizedBox(height: 24),
              ]),
      ),
    );
  }
}

/// Una línea del estado de cuenta de un lote verde: qué fue y cuándo a la izquierda; a la derecha los kilos con su signo
/// (+ entra en verde, − sale en naranja) y, debajo, el saldo después de esa línea. Sólo información: sin caja ni flecha.
class _LineaCuenta extends StatelessWidget {
  const _LineaCuenta({required this.linea});
  final Map<String, dynamic> linea;

  @override
  Widget build(BuildContext context) {
    final kg = num.tryParse('${linea['kg']}') ?? 0;
    final entra = kg > 0;
    final iconos = {
      'inicio': Icons.flag_outlined,
      'compra': Icons.add_shopping_cart,
      'anulada': Icons.remove_shopping_cart_outlined,
      'tueste': Icons.local_fire_department_outlined,
      'venta': Icons.storefront_outlined,
      'cierre': Icons.inventory_2_outlined,
      'diferencia': Icons.help_outline,
    };
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.grey.shade200))),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _InsigniaIcono(iconos[linea['tipo']] ?? Icons.circle_outlined, tono: entra ? Colors.green : Colors.orange),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${linea['titulo'] ?? ''}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600), maxLines: 2, overflow: TextOverflow.ellipsis),
            Text([_fechaLarga(linea['fecha']), if (linea['detalle'] != null) '${linea['detalle']}'].where((t) => t.isNotEmpty).join(' · '),
                style: TextStyle(fontSize: 13, color: Colors.grey.shade700), maxLines: 2, overflow: TextOverflow.ellipsis),
          ]),
        ),
        const SizedBox(width: 8),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('${entra ? '+' : '−'}${_kg(kg.abs())}',
              style: TextStyle(fontWeight: FontWeight.w700, color: entra ? Colors.green.shade800 : Colors.orange.shade800)), // lo que sale, en naranja (General Manager, 4 nov 2026)
          Text('Saldo ${_kg(linea['saldo'])}', style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
        ]),
      ]),
    );
  }
}

/// Soles siempre con céntimos, como el banco ("S/ 6,104.27"), para Movimientos.
String _solesBanco(dynamic v) {
  final n = (v is num) ? v.toDouble() : double.tryParse('${v ?? ''}') ?? 0;
  return 'S/ ${n.toStringAsFixed(2).replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',')}';
}

/// Arriba de Movimientos (General Manager, 5 nov 2026, con una imagen): el saldo disponible de la cuenta, que se puede
/// ocultar con el ojo, y lo que entró y salió en el mes. Es información, no se toca (sólo el ojo).
class _TarjetaSaldo extends StatelessWidget {
  const _TarjetaSaldo({required this.cuenta, required this.resumen, required this.visible, required this.onVer});
  final Map<String, dynamic> cuenta;
  final Map<String, dynamic>? resumen;
  final bool visible;
  final VoidCallback onVer;

  @override
  Widget build(BuildContext context) {
    const meses = ['enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', 'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre'];
    final r = resumen ?? const {};
    final mes = DateTime.tryParse('${r['mes'] ?? ''}');
    String oculto(String t) => visible ? t : 'S/ ••••';
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(
            flex: 3,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
              Text('Saldo disponible', style: TextStyle(fontSize: 14, color: Colors.grey.shade700)),
              Row(children: [
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(r['saldo'] == null ? '—' : oculto(_solesBanco(r['saldo'])),
                        style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
                  ),
                ),
                IconButton(
                  onPressed: onVer,
                  tooltip: visible ? 'Ocultar el saldo' : 'Mostrar el saldo',
                  icon: Icon(visible ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                ),
              ]),
              if (cuenta['nombre'] != null)
                Text('Cuenta ${cuenta['nombre']}', style: TextStyle(fontSize: 13, color: Colors.grey.shade700), maxLines: 1, overflow: TextOverflow.ellipsis),
            ]),
          ),
          VerticalDivider(width: 24, color: Colors.grey.shade300),
          Expanded(
            flex: 2,
            child: Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisAlignment: MainAxisAlignment.center, children: [
              if (mes != null) Text('En ${meses[mes.month - 1]}', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              Text('Ingresos', style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(oculto('+ ${_solesBanco(r['ingresos'])}'),
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.green.shade800)),
              ),
              const SizedBox(height: 6),
              Text('Gastos', style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(oculto('− ${_solesBanco(r['gastos'])}'),
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.orange.shade800)),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// Buscar y Filtrar en Movimientos: acciones, por eso sí parecen botones.
class _BotonRedondo extends StatelessWidget {
  const _BotonRedondo({required this.icono, required this.ayuda, required this.onTap, this.activo = false});
  final IconData icono;
  final String ayuda;
  final VoidCallback onTap;
  final bool activo; // un filtro elegido

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: ayuda,
      child: Material(
        color: activo ? Colors.blue.shade50 : Colors.white,
        shape: StadiumBorder(side: BorderSide(color: activo ? Colors.blue.shade200 : Colors.grey.shade300)),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: SizedBox(width: 56, height: 44, child: Icon(icono, color: activo ? Colors.blue.shade700 : Colors.grey.shade800)),
        ),
      ),
    );
  }
}

/// El día de un grupo de movimientos: "Hoy · Jueves 5 de noviembre", "Ayer · …" o "Martes 3 de noviembre".
class _DiaMovimientos extends StatelessWidget {
  const _DiaMovimientos({required this.fecha});
  final String fecha;

  @override
  Widget build(BuildContext context) {
    final d = DateTime.tryParse(fecha);
    final hoy = DateTime.now();
    final dia = d == null ? null : DateTime(hoy.year, hoy.month, hoy.day).difference(DateTime(d.year, d.month, d.day)).inDays;
    final cerca = dia == 0 ? 'Hoy' : (dia == 1 ? 'Ayer' : null);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
      child: Text.rich(
        TextSpan(children: [
          if (cerca != null) TextSpan(text: '$cerca · ', style: const TextStyle(fontWeight: FontWeight.bold)),
          TextSpan(text: _fechaLarga(fecha), style: cerca != null ? TextStyle(color: Colors.grey.shade700) : const TextStyle(fontWeight: FontWeight.bold)),
        ]),
        style: const TextStyle(fontSize: 16),
      ),
    );
  }
}

/// La tarjeta blanca con los movimientos de un día, separados por una línea.
class _GrupoMovimientos extends StatelessWidget {
  const _GrupoMovimientos({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 3))],
      ),
      child: Column(children: [
        for (final (i, c) in children.indexed) ...[
          if (i > 0) Divider(height: 1, indent: 72, color: Colors.grey.shade200),
          c,
        ],
      ]),
    );
  }
}

/// El estado de una línea del banco, en una etiqueta de color (Conciliado con su check). Es información, no se toca.
class _EstadoMovimiento extends StatelessWidget {
  const _EstadoMovimiento(this.estado);
  final String estado;

  @override
  Widget build(BuildContext context) {
    final tono = switch (estado) {
      'Conciliado' => Colors.green,
      'Falta en la app' || 'No está en el banco' => Colors.orange,
      _ => Colors.grey,
    };
    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: tono.shade50, borderRadius: BorderRadius.circular(6)),
      // Un solo texto (el check dentro): en una pantalla angosta se corta con "…" en vez de desbordar.
      child: Text.rich(
        TextSpan(children: [
          if (estado == 'Conciliado')
            WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: Padding(padding: const EdgeInsets.only(right: 4), child: Icon(Icons.check, size: 14, color: tono.shade800))),
          TextSpan(text: estado),
        ]),
        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: tono.shade800),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

/// Una línea del estado de una cuenta (Finanzas → Movimientos), con el diseño de una app de banco (General Manager,
/// 5 nov 2026): el ícono de lo que fue, el nombre, cómo se pagó y su estado; a la derecha el monto (lo que entra en
/// verde, lo que sale en naranja) y el saldo después. La última es el saldo inicial.
/// En el banco cada línea dice si cruzó (General Manager, 5 nov 2026): Conciliado (está en el banco y en la app),
/// Falta en la app (está en el banco y nadie lo registró), No está en el banco (registrado en la app, el banco todavía
/// no lo trae: no mueve el saldo) o Ignorada. Los cargos del banco (Impuesto ITF, Comisión del banco) no llevan estado.
class _LineaMovimiento extends StatelessWidget {
  const _LineaMovimiento({required this.movimiento, this.onTap});
  final Map<String, dynamic> movimiento;
  final VoidCallback? onTap; // una línea del banco abre su detalle

  @override
  Widget build(BuildContext context) {
    final m = movimiento;
    final monto = num.tryParse('${m['monto']}');
    final entra = (monto ?? 0) > 0;
    final estado = m['estado']?.toString();
    final cargo = estado == 'Impuesto ITF' || estado == 'Comisión del banco';
    final inicial = m['tipo'] == 'Saldo inicial';
    final tipo = m['tipo']?.toString();
    final banco = m['banco']?.toString();
    final icono = inicial
        ? Icons.outlined_flag
        : cargo
            ? Icons.receipt_long_outlined
            : switch (tipo) {
                'Venta' => Icons.storefront_outlined,
                'Gasto' => m['categoria'] == 'Combustible' ? Icons.local_gas_station_outlined : Icons.receipt_long_outlined,
                'Compra' => Icons.add_shopping_cart,
                'Adelanto' || 'Devolución de adelanto' => Icons.savings_outlined,
                'Retiro' => Icons.account_balance_wallet_outlined,
                _ => entra ? Icons.arrow_downward : Icons.swap_horiz,
              };
    final quien = tipo == 'Gasto' ? m['categoria'] : (m['quien'] ?? m['otra_cuenta']);
    // Una línea del banco que nadie registró se nombra con el texto del banco.
    final titulo = inicial ? 'Saldo inicial' : (tipo == null && banco != null ? banco : [tipo ?? 'Movimiento', if (quien != null) quien].join(' · '));
    final como = inicial
        ? 'Apertura de cuenta'
        : cargo
            ? estado
            : tipo == 'Venta'
                ? 'Venta'
                : (m['metodo'] != null && m['metodo'] != 'withdrawal')
                    ? (_metodosPago[m['metodo']] ?? '${m['metodo']}')
                    : tipo == 'Retiro'
                        ? 'Retiro'
                        : (banco != null && banco.toUpperCase().startsWith('TRAN') ? 'Transferencia' : null);
    final linea = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Row(children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: inicial ? Colors.blueGrey.shade50 : (entra ? Colors.green.shade50 : Colors.orange.shade50),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icono, color: inicial ? Colors.blueGrey.shade700 : (entra ? Colors.green.shade700 : Colors.orange.shade700)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(titulo, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600), maxLines: 2, overflow: TextOverflow.ellipsis),
            if (como != null) Text(como, style: TextStyle(fontSize: 13, color: Colors.grey.shade700), maxLines: 1, overflow: TextOverflow.ellipsis),
            if (estado != null && !cargo) _EstadoMovimiento(estado),
          ]),
        ),
        const SizedBox(width: 8),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          if (monto != null) ...[
            Text('${entra ? '+' : '−'} ${_solesBanco(monto.abs())}',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: entra ? Colors.green.shade800 : Colors.orange.shade800)),
            Text('Saldo: ${_solesBanco(m['saldo'])}', style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
          ] else
            Text(_solesBanco(m['saldo']), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        ]),
        if (onTap != null) Padding(padding: const EdgeInsets.only(left: 4), child: Icon(Icons.chevron_right, color: Colors.grey.shade600)),
      ]),
    );
    return onTap == null ? linea : InkWell(onTap: onTap, child: linea);
  }
}

/// El detalle de una línea del banco (General Manager, 5 nov 2026): sus datos y con qué se concilió; si no está
/// conciliada, los registros de la app del mismo monto que podrían ser, cada uno con Conciliar; si no hay ninguno, lo
/// dice. Un gasto o una compra se pagan con esta línea al conciliar. Vuelve con true si se concilió.
class _MovimientoDetalleScreen extends StatefulWidget {
  const _MovimientoDetalleScreen({required this.id});
  final int id;

  @override
  State<_MovimientoDetalleScreen> createState() => _MovimientoDetalleScreenState();
}

class _MovimientoDetalleScreenState extends State<_MovimientoDetalleScreen> {
  Map<String, dynamic>? _m;
  String? _error;
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final r = await AdministracionService.movimiento(widget.id);
    if (!mounted) return;
    setState(() {
      if (r.isSuccess) {
        _m = _mapa(r.data!['movimiento']);
      } else {
        _error = r.error;
      }
    });
  }

  Future<void> _conciliar(Map<String, dynamic> s) async {
    final m = _m!;
    final paga = s['tipo'] == 'gasto' || s['tipo'] == 'compra';
    final monto = _soles((num.tryParse('${m['monto']}') ?? 0).abs());
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('¿Conciliar?'),
        content: Text(paga
            ? 'Se registra el pago de ${s['titulo']} por $monto con esta línea del banco (transferencia del '
                '${_fechaCorta(m['fecha'])}${m['operacion'] != null ? ', operación ${m['operacion']}' : ''}).'
            : 'Esta línea del banco y ${s['titulo']} quedan conciliadas.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancelar')),
          ElevatedButton(onPressed: () => Navigator.pop(d, true), child: const Text('Conciliar')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _guardando = true);
    final r = await AdministracionService.conciliarMovimiento(widget.id, '${s['tipo']}', '${s['ref']}',
        clave: AdministracionService.nuevaClave('conciliar'));
    if (!mounted) return;
    setState(() => _guardando = false);
    // Un pedido conciliado deja su comprobante verificado (el sello verde del pedido, General Manager 5 nov 2026).
    final verificados = (r.data?['comprobantes_verificados'] as num?)?.toInt();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(!r.isSuccess
            ? (r.error ?? 'No se guardó')
            : verificados == null || verificados == 0
                ? 'Conciliado ✓'
                : verificados < 0
                    ? 'Conciliado ✓ · el comprobante no se pudo marcar como verificado'
                    : 'Conciliado ✓ · comprobante verificado')));
    if (r.isSuccess) Navigator.of(context).pop(true); // Movimientos se recarga
  }

  @override
  Widget build(BuildContext context) {
    final m = _m;
    if (m == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Movimiento')),
        body: Center(
            child: _error != null
                ? Padding(padding: const EdgeInsets.all(16), child: Text(_error!, textAlign: TextAlign.center))
                : const CircularProgressIndicator()),
      );
    }
    final monto = num.tryParse('${m['monto']}') ?? 0;
    final pago = _mapa(m['pago']);
    final pedido = _mapa(m['pedido']);
    final datos = <(String, String?)>[
      ('Estado', m['estado']?.toString()),
      ('Monto', '${monto > 0 ? '+' : '−'}${_soles(monto.abs())}'),
      ('Fecha', _fechaLarga(m['fecha'])),
      ('En el banco', m['banco']?.toString()),
      ('Operación', m['operacion']?.toString()),
      ('Cuenta', m['cuenta']?.toString()),
      if (pago.isNotEmpty) ('Conciliado con', [pago['tipo'], pago['quien'] ?? pago['categoria'], pago['id']].where((t) => t != null).join(' · ')),
      if (pedido.isNotEmpty) ('Conciliado con', ['Pedido ${pedido['numero'] ?? ''}', pedido['cliente']].where((t) => t != null).join(' · ')),
      ('Cómo', m['como']?.toString()),
      ('Conciliado por', m['conciliado_por']?.toString()),
      ('Nota', m['nota']?.toString()),
    ].where((d) => d.$2 != null && d.$2!.isNotEmpty).toList();
    final sugerencias = _lista(m['sugerencias']);
    return Scaffold(
      appBar: AppBar(title: Text('${monto > 0 ? 'Ingreso' : 'Salida'} · ${_fechaCorta(m['fecha'])}')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(16)),
          child: Column(children: [
            for (final d in datos)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.grey.shade300))),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SizedBox(width: 120, child: Text(d.$1, style: TextStyle(color: Colors.grey.shade700))),
                  Expanded(child: Text(d.$2!, style: const TextStyle(fontWeight: FontWeight.w600))),
                ]),
              ),
          ]),
        ),
        if (pago.isNotEmpty) _Evidencia(evidencia: _mapa(pago['evidencia']), titulo: datos.first.$2 ?? 'Movimiento'),
        if (pedido.isNotEmpty) _PagoDelPedido(pedidoApp: _mapa(pedido['pedido_app']), seccion: _mapa(pedido['pago_pedido']), fechaBanco: m['fecha']),
        // Sin nada que se le parezca, se dice aquí (General Manager, 5 nov 2026).
        if (m['sin_coincidencias'] == true) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(12)),
            child: Text(
                'Sin coincidencias: no hay en la app ningún ${monto > 0 ? 'pago de un pedido' : 'gasto, compra o pago'} de '
                '${_soles(monto.abs())} cerca de esta fecha. Regístralo en su proceso y vuelve a abrir esta línea.',
                style: TextStyle(color: Colors.orange.shade900)),
          ),
        ],
        if (sugerencias.isNotEmpty) ...[
          const SizedBox(height: 20),
          const Text('Puede ser', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          for (final s in sugerencias)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration:
                  BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade300)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${s['titulo'] ?? ''}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                Text(
                    [
                      if (s['detalle'] != null) '${s['detalle']}',
                      _fechaLarga(s['fecha']),
                      _soles(s['monto']),
                      if (s['tipo'] == 'gasto' || s['tipo'] == 'compra') 'por pagar',
                    ].where((t) => t.isNotEmpty).join(' · '),
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
                // Para conciliar bien, los datos y la foto del pago (General Manager, 5 nov 2026).
                if (s['por'] != null || s['nota'] != null)
                  Text([if (s['nota'] != null) '${s['nota']}', if (s['por'] != null) 'registró ${s['por']}'].join(' · '),
                      style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
                if (s['tipo'] == 'pedido')
                  _PagoDelPedido(pedidoApp: _mapa(s['pedido_app']), seccion: _mapa(s['pago_pedido']), fechaBanco: m['fecha'])
                else
                  _Evidencia(evidencia: _mapa(s['evidencia']), titulo: '${s['titulo'] ?? ''}'),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _guardando ? null : () => _conciliar(s),
                    icon: const Icon(Icons.link),
                    label: const Text('Conciliar'),
                  ),
                ),
              ]),
            ),
        ],
      ]),
    );
  }
}

/// La foto de un pago para conciliar (General Manager, 5 nov 2026): Ver evidencia (n) del gasto, compra o adelanto.
/// Sin foto lo dice, sin parecer botón. Los comprobantes de un pedido de la tienda se ven en _PagoPedido.
class _Evidencia extends StatelessWidget {
  const _Evidencia({required this.evidencia, required this.titulo});
  final Map<String, dynamic> evidencia;
  final String titulo;

  @override
  Widget build(BuildContext context) {
    final n = (evidencia['n'] as num?)?.toInt() ?? 0;
    final botones = <Widget>[
      if (n > 0)
        OutlinedButton.icon(
          onPressed: () => _abrirPantalla<void>(context, _EvidenciasScreen(tipo: '${evidencia['tipo']}', id: '${evidencia['id']}', titulo: titulo)),
          icon: const Icon(Icons.photo_library_outlined),
          label: Text('Ver evidencia ($n)'),
        ),
    ];
    if (botones.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text('Sin foto del pago', style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
      );
    }
    return Padding(padding: const EdgeInsets.only(top: 8), child: Wrap(spacing: 8, runSpacing: 8, children: botones));
  }
}

/// La parte de Pago de un pedido con el mismo diseño que el detalle del pedido (General Manager, 5 nov 2026: "just
/// re-use this design, it is more understandable"): SeccionPagoWidget sólo para ver, con el pedido como lo trae la
/// pestaña Pedidos. Si el servidor no pudo traerlo, el resumen de la base (_PagoPedido).
class _PagoDelPedido extends StatelessWidget {
  const _PagoDelPedido({required this.pedidoApp, required this.seccion, required this.fechaBanco});
  final Map<String, dynamic> pedidoApp;
  final Map<String, dynamic> seccion;
  final dynamic fechaBanco;

  @override
  Widget build(BuildContext context) {
    if (pedidoApp.isEmpty) return _PagoPedido(seccion: seccion, fechaBanco: fechaBanco);
    final vistas = <String>{};
    final evidencias = _lista(pedidoApp['evidencias']).where((e) => vistas.add('${e['url'] ?? ''}')).toList();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: SeccionPagoWidget(
        pedido: pedidoApp,
        estadoPago: EstadoPagoHelper.determinarEstadoPago(pedidoApp),
        montoPagado: ((pedidoApp['montoPagado'] ?? 0) as num).toDouble(),
        pagos: _lista(pedidoApp['pagos']),
        evidencias: evidencias,
        actualizando: false,
        subiendoEvidencia: false,
        onCambiarEstadoPago: (_, {monto, esNuevoPago}) {},
        onAgregarComprobante: (_, {paymentId}) async {},
        soloLectura: true,
      ),
    );
  }
}

/// La parte de Pago de un pedido de la tienda, dentro del detalle de la línea del banco (General Manager, 5 nov 2026:
/// "show the image of the comprobante, I don't want to go to another link", y luego toda la parte de Pago del pedido):
/// total, pagado y lo que debe; cada pago registrado con su monto y su día, y sus comprobantes como imagen, con el día
/// en que se subieron y si están verificados. El pago del mismo monto a 7 días del banco se marca "este pago".
class _PagoPedido extends StatelessWidget {
  const _PagoPedido({required this.seccion, required this.fechaBanco});
  final Map<String, dynamic> seccion;
  final dynamic fechaBanco;

  bool _esEste(Map<String, dynamic> p) {
    final a = DateTime.tryParse('${p['fecha'] ?? ''}');
    final b = DateTime.tryParse('${fechaBanco ?? ''}');
    return p['coincide'] == true && a != null && b != null && a.difference(b).inDays.abs() <= 7;
  }

  void _verImagen(BuildContext context, String url) {
    showDialog<void>(
      context: context,
      builder: (d) => Dialog(
        insetPadding: const EdgeInsets.all(12),
        child: Stack(children: [
          InteractiveViewer(child: Image.network(url, fit: BoxFit.contain)),
          Positioned(
            top: 4,
            right: 4,
            child: IconButton(tooltip: 'Cerrar', icon: const Icon(Icons.close), onPressed: () => Navigator.pop(d)),
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pagos = _lista(seccion['pagos']);
    final gris = TextStyle(fontSize: 13, color: Colors.grey.shade700);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(
            [
              if (seccion['total'] != null) 'Total ${_soles(seccion['total'])}',
              'Pagado ${_soles(seccion['pagado'])}',
              if (seccion['debe'] != null) 'Debe ${_soles(seccion['debe'])}',
            ].join(' · '),
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        if (pagos.isEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text('Sin pagos registrados en el pedido', style: gris)),
        for (final p in pagos) ...[
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: Text('Pago de ${_soles(p['monto'])} · ${_fechaLarga(p['fecha'])}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600))),
            if (_esEste(p)) Text('este pago', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.green.shade700)),
          ]),
          if (_lista(p['comprobantes']).isEmpty) Text('Sin comprobante', style: gris),
          for (final c in _lista(p['comprobantes'])) ...[
            const SizedBox(height: 6),
            GestureDetector(
              onTap: () => _verImagen(context, '${c['url']}'),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.network(
                  '${c['url']}',
                  height: 220,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  cacheWidth: _anchoMiniatura(context, 1),
                  loadingBuilder: (_, child, progreso) =>
                      progreso == null ? child : const SizedBox(height: 220, child: Center(child: CircularProgressIndicator())),
                  errorBuilder: (_, __, ___) => Container(
                    height: 60,
                    alignment: Alignment.center,
                    color: Colors.grey.shade100,
                    child: Text('No se pudo cargar la imagen', style: gris),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
                [
                  'Subido el ${_fechaLarga(c['subido'])}',
                  c['verificado'] == true
                      ? 'verificado${c['monto_verificado'] != null ? ' ${_soles(c['monto_verificado'])}' : ''}'
                      : 'sin verificar',
                  if (c['operacion'] != null) 'operación ${c['operacion']}',
                ].join(' · '),
                style: gris),
          ],
        ],
      ]),
    );
  }
}

/// Un pago de la app en Movimientos (General Manager, 5 nov 2026): sus datos, su estado frente al banco y su foto; si
/// el banco todavía no lo trae, Agregar número de operación (opcional: los formularios nunca lo piden), que lo cruza
/// con la línea del banco que tenga ese número. Avisa con onCambio si algo cambió (Movimientos se recarga al volver).
class _PagoDetalleScreen extends StatefulWidget {
  const _PagoDetalleScreen({required this.id, required this.onCambio});
  final String id;
  final VoidCallback onCambio;

  @override
  State<_PagoDetalleScreen> createState() => _PagoDetalleScreenState();
}

class _PagoDetalleScreenState extends State<_PagoDetalleScreen> {
  Map<String, dynamic>? _p;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final r = await AdministracionService.pago(widget.id);
    if (!mounted) return;
    setState(() {
      if (r.isSuccess) {
        _p = _mapa(r.data!['pago']);
      } else {
        _error = r.error;
      }
    });
  }

  Future<void> _agregarOperacion() async {
    final operacion = await showDialog<String>(context: context, builder: (_) => const _OperacionDialog());
    if (operacion == null || !mounted) return;
    final r = await AdministracionService.operacionPago(widget.id, operacion, clave: AdministracionService.nuevaClave('operacion'));
    if (!mounted) return;
    final conciliado = r.isSuccess && r.data!['conciliado'] == true;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(!r.isSuccess
            ? (r.error ?? 'No se guardó')
            : conciliado
                ? 'Conciliado ✓ con la línea del banco de ese número'
                : 'Guardado ✓ se conciliará cuando el archivo del banco traiga ese número')));
    if (r.isSuccess) {
      widget.onCambio();
      _cargar();
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _p;
    return Scaffold(
        appBar: AppBar(title: Text(p == null ? 'Pago' : '${p['tipo'] ?? 'Pago'} · ${_fechaCorta(p['fecha'])}')),
        body: p == null
            ? Center(
                child: _error != null
                    ? Padding(padding: const EdgeInsets.all(16), child: Text(_error!, textAlign: TextAlign.center))
                    : const CircularProgressIndicator())
            : ListView(padding: const EdgeInsets.all(16), children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(16)),
                  child: Column(children: [
                    for (final d in <(String, String?)>[
                      ('Estado', p['estado']?.toString()),
                      ('Monto', '${(num.tryParse('${p['monto']}') ?? 0) > 0 ? '+' : '−'}${_soles((num.tryParse('${p['monto']}') ?? 0).abs())}'),
                      ('Fecha', _fechaLarga(p['fecha'])),
                      ('Para', (p['quien'] ?? p['categoria'])?.toString()),
                      ('Descripción', p['descripcion']?.toString()),
                      ('Cómo', p['metodo'] == null ? null : (_metodosPago[p['metodo']] ?? '${p['metodo']}')),
                      ('Cuenta', p['cuenta']?.toString()),
                      ('Operación', p['operacion']?.toString()),
                      ('Nota', p['nota']?.toString()),
                      ('Registró', p['por']?.toString()),
                      ('Código', '${p['id']}'),
                    ].where((d) => d.$2 != null && d.$2!.isNotEmpty))
                      Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.grey.shade300))),
                        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          SizedBox(width: 120, child: Text(d.$1, style: TextStyle(color: Colors.grey.shade700))),
                          Expanded(child: Text(d.$2!, style: const TextStyle(fontWeight: FontWeight.w600))),
                        ]),
                      ),
                  ]),
                ),
                _Evidencia(evidencia: _mapa(p['evidencia']), titulo: '${p['tipo'] ?? 'Pago'} · ${p['id']}'),
                if (p['puede_operacion'] == true) ...[
                  const SizedBox(height: 20),
                  _Acciones(acciones: [(Icons.tag, p['operacion'] == null ? 'Agregar número de operación' : 'Cambiar número de operación', _agregarOperacion)]),
                ],
              ]),
    );
  }
}

/// El número de operación, como lo muestra el banco (sólo números; los ceros de adelante no importan).
class _OperacionDialog extends StatefulWidget {
  const _OperacionDialog();

  @override
  State<_OperacionDialog> createState() => _OperacionDialogState();
}

class _OperacionDialogState extends State<_OperacionDialog> {
  final _c = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _guardar() {
    final t = _c.text.trim();
    if (!RegExp(r'\d').hasMatch(t)) {
      setState(() => _error = 'Escribe el número de operación del banco.');
      return;
    }
    Navigator.pop(context, t);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Número de operación'),
      content: TextField(
        controller: _c,
        autofocus: true,
        keyboardType: TextInputType.number,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _guardar(),
        decoration: InputDecoration(labelText: 'Como lo muestra el banco', errorText: _error),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        ElevatedButton(onPressed: _guardar, child: const Text('Guardar')),
      ],
    );
  }
}

/// Cerrar lote (General Manager, 4 nov 2026, tras la reunión de lotes): sólo después del conteo. El lote se cierra
/// (archivado, nunca borrado) sólo si el conteo encontró 0 kg; los kilos que mostraba quedan escritos con el motivo.
class _CerrarLoteDialog extends StatefulWidget {
  const _CerrarLoteDialog({required this.lote});
  final Map<String, dynamic> lote;

  @override
  State<_CerrarLoteDialog> createState() => _CerrarLoteDialogState();
}

class _CerrarLoteDialogState extends State<_CerrarLoteDialog> {
  final _contados = TextEditingController();
  final _motivo = TextEditingController();
  final _clave = AdministracionService.nuevaClave('cerrarLote');
  String? _error;
  bool _guardando = false;

  @override
  void dispose() {
    _contados.dispose();
    _motivo.dispose();
    super.dispose();
  }

  Future<void> _cerrar() async {
    final kg = num.tryParse(_contados.text.trim().replaceAll(',', '.'));
    if (kg == null) return setState(() => _error = 'Escribe los kilos que encontró el conteo.');
    if (kg > 0) return setState(() => _error = 'El conteo encontró café: el lote no se cierra. Tuéstalo primero.');
    if (_motivo.text.trim().isEmpty) return setState(() => _error = 'Escribe por qué se cierra.');
    setState(() {
      _guardando = true;
      _error = null;
    });
    final r = await AdministracionService.cerrarLote('${widget.lote['id']}', kg, _motivo.text.trim(), clave: _clave);
    if (!mounted) return;
    if (r.isSuccess) return Navigator.pop(context, true);
    setState(() {
      _guardando = false;
      _error = r.error ?? 'No se cerró.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final lote = widget.lote;
    return AlertDialog(
      title: Text('¿Cerrar el lote ${lote['codigo']}?'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('La app muestra ${_kg(lote['kg_ahora'])}. Ciérralo sólo después de pesar los sacos: si el conteo encontró 0 kg.'),
          const SizedBox(height: 12),
          TextField(
            controller: _contados,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Kilos que encontró el conteo', suffixText: 'kg', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 16), // campos separados, nunca pegados (General Manager, 4 nov 2026)
          TextField(
            controller: _motivo,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Motivo', hintText: 'Conteo del 5 nov: sin sacos', border: OutlineInputBorder()),
          ),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: const TextStyle(color: Colors.red))),
        ]),
      ),
      actions: [
        TextButton(onPressed: _guardando ? null : () => Navigator.pop(context, false), child: const Text('Cancelar')),
        ElevatedButton(onPressed: _guardando ? null : _cerrar, child: Text(_guardando ? 'Cerrando…' : 'Cerrar lote')),
      ],
    );
  }
}

/// Nombre de un producto con su café tostado disponible a la derecha (información, no botón).
class _NombreProducto extends StatelessWidget {
  const _NombreProducto({required this.nombre, this.kg});
  final String nombre;
  final String? kg;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 14, 4, 2),
        child: Row(children: [
          Expanded(child: Text(nombre, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700), maxLines: 2)),
          if (kg != null) Text(kg!, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.orange.shade800)),
        ]),
      );
}

/// Un lote verde en su ficha: código, variedad y cosecha, kilos que quedan de los que entraron, barra y %.
class _FilaLote extends StatelessWidget {
  const _FilaLote({required this.lote, this.onTap});
  final Map<String, dynamic> lote;
  final VoidCallback? onTap; // abre el detalle del lote: ficha blanca con flecha

  @override
  Widget build(BuildContext context) {
    final ahora = (lote['kg_ahora'] as num?)?.toDouble() ?? 0;
    final inicial = (lote['kg_inicial'] as num?)?.toDouble() ?? 0;
    final parte = inicial > 0 ? (ahora / inicial).clamp(0.0, 1.0) : 0.0;
    final detalle = [if (lote['variedad'] != null) '${lote['variedad']}', if (lote['cosecha'] != null) 'cosecha ${lote['cosecha']}'];
    final fila = Row(children: [
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
            // El producto que usa este lote, y si es el lote del Blend (General Manager, 4 nov 2026).
            if (lote['producto'] != null || lote['crece'] == true)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                    [if (lote['producto'] != null) '${lote['producto']}', if (lote['crece'] == true) 'lote del Blend: crece con café pilado'].join(' · '),
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
              ),
            // Cada compra del Blend suma sola un estimado de verde al lote: 80% del pergamino (General Manager, 4 nov 2026).
            if (lote['compras_n'] != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                    '${lote['compras_n']} ${lote['compras_n'] == 1 ? 'compra' : 'compras'} · ${_kg(lote['estimado_kg'])} de verde estimado',
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
              ),
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
        if (onTap != null) Icon(Icons.chevron_right, color: Colors.grey.shade600),
      ]);
    // Sin acción: sólo información, sin caja blanca y una línea fina debajo. Con acción (abre el detalle): ficha blanca
    // con flecha, como las demás filas que se tocan.
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

/// Detalle de un lote verde (General Manager, 4 nov 2026: "add the detail of each lote, and inside put the actions"):
/// sus datos, el producto que lo usa, lo agregado y el cierre, y sus últimos tuestes. Las acciones van aquí, para los
/// dueños: Agregar café al lote (sólo el lote del Blend) y Cerrar lote (sólo un lote que no es el café de un producto).
class _LoteVerdeDetalleScreen extends StatefulWidget {
  const _LoteVerdeDetalleScreen({required this.id, required this.esDueno});
  final String id;
  final bool esDueno;

  @override
  State<_LoteVerdeDetalleScreen> createState() => _LoteVerdeDetalleScreenState();
}

class _LoteVerdeDetalleScreenState extends State<_LoteVerdeDetalleScreen> {
  Map<String, dynamic>? _l;
  String? _error;
  bool _cambio = false;
  // El estado de cuenta llega del servidor de 20 en 20, al acercarse al final (General Manager, 4 nov 2026).
  final _lineas = <Map<String, dynamic>>[];
  Map<String, dynamic> _cuenta = const {};
  bool _hayMas = false;
  bool _cargandoMas = false;
  int _pedido = 0;
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _cargar();
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 200) _masLineas();
    });
  }

  /// La siguiente página del estado de cuenta (o la primera, al cargar).
  Future<void> _masLineas({bool desdeCero = false}) async {
    if (!desdeCero && (_cargandoMas || !_hayMas)) return;
    final pedido = desdeCero ? ++_pedido : _pedido;
    setState(() => _cargandoMas = true);
    final r = await AdministracionService.cuentaLote(widget.id, desde: desdeCero ? 0 : _lineas.length);
    if (!mounted || pedido != _pedido) return;
    setState(() {
      _cargandoMas = false;
      if (!r.isSuccess) {
        _hayMas = false;
        return;
      }
      final c = _mapa(r.data!['cuenta']);
      if (desdeCero) _lineas.clear();
      _lineas.addAll(_lista(c['lineas']));
      _cuenta = c;
      _hayMas = c['hay_mas'] == true;
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    _masLineas(desdeCero: true);
    final r = await AdministracionService.loteVerde(widget.id);
    if (!mounted) return;
    setState(() {
      _error = r.isSuccess ? null : (r.error ?? 'No se pudo cargar el lote.');
      if (r.isSuccess) _l = _mapa(r.data!['lote']);
    });
  }

  Future<void> _cerrar(Map<String, dynamic> l) async {
    if (await showDialog<bool>(context: context, builder: (_) => _CerrarLoteDialog(lote: l)) == true) {
      _cambio = true;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lote ${l['codigo']} cerrado ✓')));
      Navigator.pop(context, true); // un lote cerrado ya no está en Café verde
    }
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

  Widget _panel(List<Widget> filas) {
    final visibles = filas.where((w) => w is! SizedBox).toList();
    if (visibles.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(16)),
      child: Column(children: visibles),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = _l;
    final cuenta = _cuenta;
    final abierto = l != null && l['estado'] == 'available';
    final puedeCerrar = widget.esDueno && abierto && l['crece'] != true && l['producto'] == null;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.pop(context, _cambio);
      },
      child: Scaffold(
        appBar: AppBar(title: Text(l == null ? 'Lote verde' : 'Lote ${l['codigo']}')),
        body: RefreshIndicator(
          onRefresh: _cargar,
          child: l == null
              ? ListView(children: [
                  Padding(
                    padding: const EdgeInsets.all(32),
                    child: _error != null ? Text(_error!, textAlign: TextAlign.center) : const Center(child: CircularProgressIndicator()),
                  ),
                ])
              : ListView(controller: _scroll, padding: const EdgeInsets.all(16), children: [
                  Row(children: [
                    Expanded(
                        child: Text('${l['producto'] ?? 'Sin producto'}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold))),
                    _Insignia('${l['codigo']}'),
                  ]),
                  if (l['crece'] == true)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text('Lote del Blend: crece con café pilado', style: TextStyle(color: Colors.grey.shade700)),
                    ),
                  if (!abierto) Padding(padding: const EdgeInsets.only(top: 4), child: _Pildora('Cerrado', Colors.grey)),
                  // Las acciones, dentro del detalle (General Manager, 4 nov 2026).
                  // Agregar café al lote ya no hace falta: las compras del Blend suman solas su estimado (4 nov 2026).
                  if (puedeCerrar) ...[
                    const SizedBox(height: 16),
                    SizedBox(
                      height: 48,
                      child: OutlinedButton.icon(
                          onPressed: () => _cerrar(l), icon: const Icon(Icons.inventory_2_outlined), label: const Text('Cerrar lote')),
                    ),
                  ],
                  _panel([
                    // Como un estado de cuenta (General Manager, 4 nov 2026): el saldo es el café verde de ahora.
                    _dato('Saldo', _kg(cuenta['saldo'] ?? l['kg_ahora'])),
                    _dato('Entradas', cuenta['entradas'] == null ? null : '+${_kg(cuenta['entradas'])}'),
                    _dato('Salidas', cuenta['salidas'] == null ? null : '−${_kg(cuenta['salidas'])}'),
                    _dato('Variedad', l['variedad']?.toString()),
                    _dato('Cosecha', l['cosecha']?.toString()),
                    _dato('Origen', l['origen']?.toString()),
                    _dato('Llegó', l['llego'] == null ? null : _fechaLarga(l['llego'])),
                  ]),
                  // Una sola lista, el estado de lote, como un estado de cuenta (General Manager, 4 nov 2026): las compras suman (+) y los tuestes,
                  // las ventas de verde y el cierre restan (−), con el saldo después de cada línea; lo más nuevo arriba.
                  _encabezado('Estado de lote', cuenta['total'] == null ? '' : '${cuenta['total']}'), // antes "Estado de cuenta" (4 nov 2026)
                  if (_lineas.isEmpty && !_cargandoMas) _vacio('Este lote todavía no tiene movimientos.'),
                  for (final m in _lineas) _LineaCuenta(linea: m),
                  // Sin texto al final de la lista: sólo la carga mientras llega la siguiente página.
                  if (_cargandoMas) const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
                  const SizedBox(height: 24),
                ]),
        ),
      ),
    );
  }
}

/// Finalizar tueste: cuántos kilos de café tostado salieron, y notas.
/// Un tueste en marcha (General Manager, 5 nov 2026): el producto, el lote y los kilos de verde, y un contador que corre
/// cada segundo desde que se inició, con Finalizar al lado. El contador es información; sólo Finalizar es un botón.
class _ContadorTueste extends StatefulWidget {
  const _ContadorTueste({required this.tueste, required this.onFinalizar});
  final Map<String, dynamic> tueste;
  final VoidCallback onFinalizar;

  @override
  State<_ContadorTueste> createState() => _ContadorTuesteState();
}

class _ContadorTuesteState extends State<_ContadorTueste> {
  Timer? _reloj;

  @override
  void initState() {
    super.initState();
    _reloj = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _reloj?.cancel();
    super.dispose();
  }

  static String _duracion(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.tueste;
    final inicio = DateTime.tryParse('${t['fecha'] ?? ''}')?.toLocal();
    final pasado = inicio == null ? Duration.zero : DateTime.now().difference(inicio);
    final hora = inicio == null ? null : '${inicio.hour.toString().padLeft(2, '0')}:${inicio.minute.toString().padLeft(2, '0')}';
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      decoration: BoxDecoration(
        color: Colors.deepOrange.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.deepOrange.shade200),
      ),
      child: Row(children: [
        Icon(Icons.local_fire_department, color: Colors.deepOrange.shade700, size: 30),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(['Tostando', if (t['producto'] != null) '${t['producto']}'].join(' · '),
                style: TextStyle(fontWeight: FontWeight.w700, color: Colors.deepOrange.shade900), maxLines: 1, overflow: TextOverflow.ellipsis),
            Text([if (t['lote'] != null) '${t['lote']}', '${_kg(t['kg_verde'])} verde', if (hora != null) 'desde $hora'].join(' · '),
                style: TextStyle(fontSize: 13, color: Colors.grey.shade800), maxLines: 1, overflow: TextOverflow.ellipsis),
            Text(_duracion(pasado.isNegative ? Duration.zero : pasado),
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: Colors.deepOrange.shade800,
                    fontFeatures: const [FontFeature.tabularFigures()])),
          ]),
        ),
        ElevatedButton(onPressed: widget.onFinalizar, child: const Text('Finalizar')),
      ]),
    );
  }
}

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
        const SizedBox(height: 16), // campos separados, nunca pegados (General Manager, 4 nov 2026)
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
