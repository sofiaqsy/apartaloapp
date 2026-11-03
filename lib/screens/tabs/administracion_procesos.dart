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

Future<T?> _abrirPantalla<T>(BuildContext context, Widget pantalla) =>
    Navigator.of(context).push<T>(CupertinoPageRoute(builder: (_) => pantalla));

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

  @override
  Widget build(BuildContext context) {
    // Una tarjeta por proceso, en el orden del café: se cultiva, se compra, se produce, se vende.
    // Registrar gasto y el retiro de efectivo están dentro de cada proceso (General Manager, 3 nov 2026).
    // Sólo se ven las de las áreas marcadas en Perfil → Mis áreas (General Manager, 3 nov 2026).
    final tarjetas = <(String, Object?, Widget)>[
      ('farm', _finca, _TarjetaProceso(
        titulo: 'Finca',
        indicadores: _finca == null ? null : _indicadoresFinca(_finca!, widget.esDueno),
        error: _error,
        onTap: () => _entrar(_FincaScreen(esDueno: widget.esDueno)),
      )),
      ('sourcing', _compras, _TarjetaProceso(
        titulo: 'Compras',
        indicadores: _compras == null ? null : _indicadoresCompras(_compras!, widget.esDueno),
        error: _error,
        onTap: () => _entrar(_ComprasScreen(esDueno: widget.esDueno)),
      )),
      ('production', _produccion, _TarjetaProceso(
        titulo: 'Producción',
        indicadores: _produccion == null ? null : _indicadoresProduccion(_produccion!),
        error: _error,
        onTap: () => _entrar(const _ProduccionScreen()),
      )),
      ('commercial', _comercial, _TarjetaProceso(
        titulo: 'Comercialización',
        indicadores: _comercial == null ? null : _indicadoresComercial(_comercial!),
        error: _error,
        onTap: () => _entrar(const _ComercialScreen()),
      )),
    ];
    final areas = _areas;
    // Marcada en Perfil y, ya cargado, con datos del servidor (que no manda procesos de áreas ajenas).
    final visibles = areas == null
        ? <Widget>[]
        : [for (final (area, datos, t) in tarjetas) if (areas.contains(area) && (!_cargado || datos != null)) t];
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

const _meses = [
  'enero',
  'febrero',
  'marzo',
  'abril',
  'mayo',
  'junio',
  'julio',
  'agosto',
  'septiembre',
  'octubre',
  'noviembre',
  'diciembre'
];

/// Finca: siempre 4. Dueños: gastos del mes, por pagar, gastos del año y cosecha del año.
/// El equipo no ve dinero: cuántos gastos, parcelas, actividades del mes y cosecha.
List<_Indicador> _indicadoresFinca(Map<String, dynamic> f, bool esDueno) {
  final mes = _mapa(f['gastos_mes']);
  final anio = _mapa(f['gastos_anio']);
  final cosecha = _mapa(f['cosecha']);
  final nMes = (mes['n'] as num?)?.toInt() ?? 0;
  final gastos = (int n) => '$n ${n == 1 ? 'gasto' : 'gastos'}';
  final cosechaInd = _Indicador(Icons.agriculture, _kg(cosecha['kg']), 'Cosecha', tono: Colors.green,
      nota: 'cereza · ${cosecha['anio'] ?? DateTime.now().year}');
  if (esDueno && mes['total'] != null) {
    final porPagar = (_mapa(f['por_pagar'])['total'] as num?) ?? 0;
    return [
      _Indicador(Icons.receipt_long, _soles(mes['total']), 'Gastos este mes', tono: Colors.orange,
          nota: '${_meses[DateTime.now().month - 1]} · ${gastos(nMes)}'),
      _Indicador(Icons.account_balance_wallet, _soles(porPagar), 'Por pagar', tono: Colors.blue, atencion: porPagar > 0,
          nota: porPagar > 0 ? 'gastos de finca' : 'todo pagado'),
      _Indicador(Icons.calendar_month, _soles(anio['total']), 'Gastos en el año', tono: Colors.purple,
          nota: '${DateTime.now().year} · ${gastos((anio['n'] as num?)?.toInt() ?? 0)}'),
      cosechaInd,
    ];
  }
  final parcelas = _mapa(f['parcelas']);
  final nAct = (f['actividades_mes'] as num?)?.toInt() ?? 0;
  return [
    _Indicador(Icons.receipt_long, '$nMes', 'Gastos este mes', tono: Colors.orange, nota: 'registrados'),
    _Indicador(Icons.landscape, '${parcelas['n'] ?? 0}', 'Parcelas', tono: Colors.brown,
        nota: '${parcelas['hectareas'] ?? 0} ha'),
    _Indicador(Icons.event_note, '$nAct', 'Labores del mes', tono: Colors.blue, nota: 'en las parcelas'),
    cosechaInd,
  ];
}

/// Compras: siempre 4. Dueños: lo recibido, lo que falta precio, lo que se debe y los adelantos.
/// El equipo no ve dinero: en su lugar, el café en almacén y el último recibido.
List<_Indicador> _indicadoresCompras(Map<String, dynamic> c, bool esDueno) {
  final mes = _mapa(c['mes']);
  final sinPrecio = _mapa(c['sin_precio']);
  final nRecibidos = (mes['recibidos'] as num?)?.toInt() ?? 0;
  final nSinPrecio = (sinPrecio['n'] as num?)?.toInt() ?? 0;
  final recibido = _Indicador(Icons.move_to_inbox, _kg(mes['kg']), 'Recibido',
      tono: Colors.green, nota: '${_meses[DateTime.now().month - 1]} · $nRecibidos ${nRecibidos == 1 ? 'entrega' : 'entregas'}');
  final precio = _Indicador(Icons.sell_outlined, '$nSinPrecio', 'Sin precio',
      tono: Colors.orange, nota: nSinPrecio == 0 ? 'todo con precio' : _kg(sinPrecio['kg']), atencion: nSinPrecio > 0);
  if (esDueno && c['por_pagar'] != null) {
    final porPagar = _mapa(c['por_pagar']);
    final adelantos = _mapa(c['adelantos']);
    final nPagar = (porPagar['n'] as num?)?.toInt() ?? 0;
    final nAdel = (adelantos['n'] as num?)?.toInt() ?? 0;
    return [
      recibido,
      precio,
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
    _Indicador(Icons.event, c['ultimo'] == null ? '—' : _fechaCorta(c['ultimo']), 'Último recibido', tono: Colors.blue),
  ];
}

/// Producción: siempre 4. Café verde, café tostado, tuestes del mes y merma.
List<_Indicador> _indicadoresProduccion(Map<String, dynamic> p) {
  final lotes = _lista(p['lotes_verdes']);
  final tuestes = _lista(p['tuestes']);
  final mes = _mapa(p['mes']);
  final enCurso = tuestes.where((t) => t['estado'] == 'in_progress').length;
  final programados = tuestes.length - enCurso;
  return [
    _Indicador(Icons.eco, _kg(p['verde_kg']), 'Café verde',
        tono: Colors.green, nota: '${lotes.length} ${lotes.length == 1 ? 'lote' : 'lotes'}'),
    _Indicador(Icons.coffee, _kg(p['tostado_kg']), 'Café tostado', tono: Colors.orange, nota: 'disponible'),
    _Indicador(Icons.local_fire_department, '${mes['tuestes'] ?? 0}', 'Tuestes este mes',
        tono: Colors.blue,
        nota: enCurso > 0 ? '$enCurso tostando ahora' : (programados > 0 ? '$programados programados' : 'ninguno programado'),
        atencion: enCurso > 0),
    _Indicador(Icons.trending_down, mes['merma_pct'] != null ? '${mes['merma_pct']}%' : '—', 'Merma',
        tono: Colors.red, nota: '${_kg(mes['kg_verde'])} → ${_kg(mes['kg_tostado'])}'),
  ];
}

/// Comercialización: siempre 4, de las ventas de la tienda por mes (pedidos no cancelados).
/// "Por cobrar" no va aquí: el estado de pago de los pedidos en la base no coincide con el reporte;
/// la lista de clientes por cobrar está dentro, en el reporte de ventas.
List<_Indicador> _indicadoresComercial(Map<String, dynamic> c) {
  final meses = _lista(c['meses']);
  final hoy = DateTime.now();
  String clave(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}';
  Map<String, dynamic> mes(DateTime d) =>
      meses.firstWhere((m) => '${m['month']}'.startsWith(clave(d)), orElse: () => <String, dynamic>{});
  num n(dynamic v) => v is num ? v : num.tryParse('${v ?? ''}') ?? 0;
  final actual = mes(hoy);
  final anterior = mes(DateTime(hoy.year, hoy.month - 1));
  final pedidos = n(actual['orders']);
  final anio = meses.where((m) => '${m['month']}'.startsWith('${hoy.year}-'));
  final pedidosAnio = anio.fold<num>(0, (t, m) => t + n(m['orders']));
  String plural(num k) => '$k ${k == 1 ? 'pedido' : 'pedidos'}';
  return [
    _Indicador(Icons.point_of_sale, _soles(n(actual['total'])), 'Vendido este mes', tono: Colors.green,
        nota: '${_meses[hoy.month - 1]} · ${plural(pedidos)}'),
    _Indicador(Icons.history, _soles(n(anterior['total'])), 'Mes anterior', tono: Colors.blue,
        nota: '${_meses[DateTime(hoy.year, hoy.month - 1).month - 1]} · ${plural(n(anterior['orders']))}'),
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
              _CuatroDatos(indicadores: datos),
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
    // En la tarjeta los datos no van en cajas (General Manager, 3 nov 2026: parecían botones): sólo líneas finas
    // entre ellos. Toda la tarjeta es el único botón.
    final linea = Colors.blue.shade100;
    final filas = <Widget>[];
    for (var i = 0; i < indicadores.length; i += 2) {
      if (i > 0) filas.add(grande ? const SizedBox(height: 10) : Divider(height: 1, thickness: 1, color: linea));
      filas.add(IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(child: _DatoCaja(indicadores[i], grande: grande)),
          grande ? const SizedBox(width: 10) : VerticalDivider(width: 17, thickness: 1, color: linea),
          Expanded(child: i + 1 < indicadores.length ? _DatoCaja(indicadores[i + 1], grande: grande) : const SizedBox()),
        ]),
      ));
    }
    return Column(children: filas);
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
    return Container(
      padding: grande ? const EdgeInsets.all(12) : const EdgeInsets.symmetric(vertical: 8),
      decoration: grande ? BoxDecoration(color: d.tono.shade50, borderRadius: BorderRadius.circular(16)) : null,
      child: Row(crossAxisAlignment: grande ? CrossAxisAlignment.center : CrossAxisAlignment.start, children: [
        grande
            ? Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                child: Icon(d.icono, size: 24, color: color),
              )
            : Padding(padding: const EdgeInsets.only(top: 2), child: Icon(d.icono, size: 20, color: color)),
        SizedBox(width: grande ? 10 : 8),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child:
                  Text(d.valor, style: TextStyle(fontSize: grande ? 21 : 18, height: 1.15, fontWeight: FontWeight.bold, color: valorColor)),
            ),
            Text(d.nombre,
                style: TextStyle(fontSize: 13, height: 1.2, color: Colors.grey.shade800), maxLines: 1, overflow: TextOverflow.ellipsis),
            if (d.nota != null && d.nota!.isNotEmpty)
              Text(d.nota!,
                  style: TextStyle(fontSize: 12, height: 1.2, color: Colors.grey.shade600), maxLines: 1, overflow: TextOverflow.ellipsis),
          ]),
        ),
      ]),
    );
  }
}

/// Botones grandes de acción, dos por fila.
class _Acciones extends StatelessWidget {
  const _Acciones({required this.acciones, this.compactas = false});
  final List<(IconData, String, VoidCallback)> acciones;
  final bool compactas; // una fila baja: ícono y texto lado a lado

  @override
  Widget build(BuildContext context) {
    if (compactas) {
      // Con tres botones no cabe el texto al lado del ícono: va debajo.
      final debajo = acciones.length > 2;
      return IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final (i, (icono, texto, onTap)) in acciones.indexed) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: Material(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: onTap,
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: debajo ? 6 : 10, vertical: debajo ? 10 : 14),
                  child: debajo
                      ? Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Icon(icono, size: 22, color: Colors.blue.shade700),
                          const SizedBox(height: 4),
                          Text(texto, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600), maxLines: 2),
                        ])
                      : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Icon(icono, size: 22, color: Colors.blue.shade700),
                          const SizedBox(width: 6),
                          Flexible(child: Text(texto, style: const TextStyle(fontWeight: FontWeight.w600), maxLines: 2)),
                        ]),
                ),
              ),
            ),
          ),
        ],
        if (acciones.length == 1) const Expanded(child: SizedBox()),
      ]));
    }
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
      if (r.isSuccess && r.data![clave] is! Map) error = 'Este proceso no es de tus áreas.';
      if (r.isSuccess && r.data![clave] is Map) datos = _mapa(r.data![clave]);
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

Widget _vacio(String texto) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(texto, style: TextStyle(color: Colors.grey.shade600)),
    );

// ─── Partes de la pantalla de un proceso ─────────────────────────────────────
// Estándar (General Manager, 3 nov 2026, de su ejemplo de Producción): los 4 datos con su color, dos
// botones grandes con la acción principal, pestañas para las listas, y cada fila es una ficha blanca.

/// Pestañas debajo de las acciones: el texto elegido en azul y subrayado.
class _Pestanas extends StatelessWidget {
  const _Pestanas({required this.nombres, required this.elegida, required this.onElegir});
  final List<String> nombres;
  final int elegida;
  final ValueChanged<int> onElegir;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 20),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.grey.shade300))),
      child: Row(children: [
        for (final (i, n) in nombres.indexed)
          Expanded(
            child: InkWell(
              onTap: () => onElegir(i),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: i == elegida ? Colors.blue.shade700 : Colors.transparent, width: 3)),
                ),
                child: Text(n,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: i == elegida ? Colors.blue.shade700 : Colors.grey.shade600,
                    )),
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
      child: Text(texto, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: tono.shade800)),
    );
  }
}

/// Ficha blanca de una fila. Sin flecha: las filas de estas listas no abren otra pantalla.
class _Ficha extends StatelessWidget {
  const _Ficha({required this.inicio, required this.titulo, this.detalle, this.fin});
  final Widget inicio;
  final String titulo;
  final String? detalle;
  final Widget? fin;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration:
            BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.grey.shade200)),
        child: Row(children: [
          inicio,
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(titulo, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
              if (detalle != null)
                Text(detalle!, style: TextStyle(fontSize: 13, color: Colors.grey.shade700), maxLines: 2, overflow: TextOverflow.ellipsis),
            ]),
          ),
          if (fin != null) ...[const SizedBox(width: 8), fin!],
        ]),
      ),
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

class _FincaScreenState extends _ProcesoState<_FincaScreen> {
  @override
  String get clave => 'finca';

  @override
  Widget build(BuildContext context) {
    return pantalla('Finca', (d) {
      final recientes = _lista(d['recientes']);
      return [
        _CuatroDatos(indicadores: _indicadoresFinca(d, widget.esDueno), grande: true), // los mismos 4 de la tarjeta
        const SizedBox(height: 16),
        _Acciones(acciones: [
          (Icons.receipt_long, 'Registrar gasto de finca', () => formulario('gasto', fijos: const {'area': 'farm'}, subtitulo: 'Área: Finca')),
        ]),
        _encabezado('Últimos gastos de la finca', '${recientes.length}'),
        if (recientes.isEmpty) _vacio('Todavía no hay gastos de la finca.'),
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

// ─── Compras ─────────────────────────────────────────────────────────────────

class _ComprasScreen extends StatefulWidget {
  const _ComprasScreen({required this.esDueno});
  final bool esDueno;

  @override
  State<_ComprasScreen> createState() => _ComprasScreenState();
}

class _ComprasScreenState extends _ProcesoState<_ComprasScreen> {
  int _pestana = 0; // 0 Recibidos, 1 En almacén

  @override
  String get clave => 'compras';

  @override
  Widget build(BuildContext context) {
    return pantalla('Compras', (d) {
      final almacen = _lista(d['almacen']);
      final recientes = _lista(d['recientes']);
      return [
        _CuatroDatos(indicadores: _indicadoresCompras(d, widget.esDueno), grande: true), // los mismos 4 de la tarjeta
        const SizedBox(height: 16),
        // Las dos acciones de todos los días, grandes; las demás debajo, en una fila baja.
        _Acciones(acciones: [
          (Icons.move_to_inbox, _titulos['entrega']!, () => formulario('entrega')),
          (Icons.handshake, _titulos['adelanto']!, () => formulario('adelanto')),
        ]),
        const SizedBox(height: 10),
        _Acciones(compactas: true, acciones: [
          (Icons.person_add_alt_1, _titulos['proveedor']!, () => formulario('proveedor')),
          (Icons.receipt_long, _titulos['gasto']!, () => formulario('gasto', fijos: const {'area': 'sourcing'}, subtitulo: 'Área: Compras')),
        ]),
        // Sólo dueños mueven dinero.
        if (widget.esDueno) ...[
          const SizedBox(height: 10),
          _Acciones(compactas: true, acciones: [
            (Icons.payments, 'Pagar compras', () => Navigator.of(context).pop('pendientes')),
            (Icons.account_balance_wallet, _titulos['retiro']!, () => formulario('retiro')),
          ]),
        ],
        _Pestanas(nombres: const ['Recibidos', 'En almacén'], elegida: _pestana, onElegir: (i) => setState(() => _pestana = i)),
        if (_pestana == 0) ...[
          _encabezado('Últimos recibidos', '${recientes.length} ${recientes.length == 1 ? 'entrega' : 'entregas'}'),
          if (recientes.isEmpty) _vacio('Todavía no hay café recibido.'),
          for (final r in recientes)
            _Ficha(
              inicio: _Insignia(_fechaCorta(r['fecha']), tono: Colors.green),
              titulo: '${r['agricultor'] ?? 'Sin nombre'}',
              detalle: '${_estadosCafe[r['estado']] ?? r['estado']} · ${_kg(r['kg'])}',
              fin: r['precio'] != null
                  ? _Pildora('${_soles(r['precio'])}/kg', Colors.green)
                  : (widget.esDueno ? const _Pildora('Sin precio', Colors.orange) : null),
            ),
        ] else ...[
          _encabezado('Café en almacén', '${almacen.length} ${almacen.length == 1 ? 'estado' : 'estados'}'),
          if (almacen.isEmpty) _vacio('No hay café de compras guardado.'),
          for (final a in almacen)
            _Ficha(
              inicio: const _InsigniaIcono(Icons.inventory_2_outlined, tono: Colors.brown),
              titulo: _estadosCafe[a['estado']] ?? '${a['estado']}',
              detalle: '${a['lotes']} ${a['lotes'] == 1 ? 'lote' : 'lotes'}',
              fin: Text(_kg(a['kg']), style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
        ],
      ];
    });
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
    final r = await AdministracionService.procesos();
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
                _Acciones(compactas: true, acciones: [
                  (
                    Icons.receipt_long,
                    'Registrar gasto de comercialización',
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

class _ProduccionScreenState extends _ProcesoState<_ProduccionScreen> {
  int? _pestana; // 0 Tuestes, 1 Lotes; al abrir: Tuestes si hay alguno, si no Lotes

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
      final porProcesar = _lista(d['por_procesar']);
      final pestana = _pestana ?? (tuestes.isNotEmpty ? 0 : 1);
      return [
        _CuatroDatos(indicadores: _indicadoresProduccion(d), grande: true), // los mismos 4 de la tarjeta
        const SizedBox(height: 16),
        _Acciones(acciones: [
          (Icons.local_fire_department, 'Tostar café', _tostar),
          (
            Icons.receipt_long,
            'Registrar gasto de producción',
            () => formulario('gasto', fijos: const {'area': 'production'}, subtitulo: 'Área: Producción')
          ),
        ]),
        _Pestanas(nombres: const ['Tuestes', 'Lotes de café verde'], elegida: pestana, onElegir: (i) => setState(() => _pestana = i)),
        if (pestana == 0) ...[
          _encabezado('Tuestes en curso y programados', '${tuestes.length}'),
          if (tuestes.isEmpty) _vacio('No hay tuestes programados. Toca "Tostar café".'),
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
                detalle:
                    '${p['lotes']} ${p['lotes'] == 1 ? 'lote' : 'lotes'} · calidad: ${p['calidad'] == 'pending' ? 'por revisar' : p['calidad']}',
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
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
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
        if (_error != null)
          Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: const TextStyle(color: Colors.red))),
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
                  if (_cargando || _hayMas)
                    return const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()));
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
