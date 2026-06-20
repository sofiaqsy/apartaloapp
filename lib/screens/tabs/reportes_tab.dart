import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/api_service.dart';
import 'pedidos/helpers/estado_pago_helper.dart';

class ReportesTab extends StatefulWidget {
  const ReportesTab({super.key});

  @override
  State<ReportesTab> createState() => _ReportesTabState();
}

class _ReportesTabState extends State<ReportesTab> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _pedidos = [];

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() { _loading = true; _error = null; });
    // Traer historial grande para los reportes (completados + pendientes de cobro)
    final results = await Future.wait([
      ApiService.getPedidos(vista: 'HISTORIAL', limite: 300),
      ApiService.getPedidos(vista: 'PENDIENTES', limite: 200),
    ]);
    if (!mounted) return;
    final historial = results[0].isSuccess ? results[0].data!.pedidos : <Map<String, dynamic>>[];
    final pendientes = results[1].isSuccess ? results[1].data!.pedidos : <Map<String, dynamic>>[];
    // Merge deduplicado por id
    final ids = <String>{};
    final merged = <Map<String, dynamic>>[];
    for (final p in [...historial, ...pendientes]) {
      final id = p['id']?.toString() ?? '';
      if (ids.add(id)) merged.add(p);
    }
    setState(() {
      _pedidos = merged;
      _loading = false;
      if (results[0].error != null && results[1].error != null) _error = results[0].error;
    });
  }

  // ── Helpers de fechas ─────────────────────────────────────────────────────

  DateTime? _parseFecha(dynamic raw) {
    if (raw == null) return null;
    final s = raw.toString();
    if (s.isEmpty) return null;
    try {
      if (s.contains('T') || s.contains('-')) return DateTime.parse(s).toLocal();
      if (s.contains('/')) {
        final p = s.split('/');
        if (p.length == 3) {
          var y = int.parse(p[2]);
          if (y < 100) y += 2000;
          return DateTime(y, int.parse(p[1]), int.parse(p[0]));
        }
      }
    } catch (_) {}
    return null;
  }

  // ── Estadísticas ──────────────────────────────────────────────────────────

  Map<String, dynamic> _resumenPeriodo(DateTime desde) {
    double total = 0;
    double cobrado = 0;
    int count = 0;
    for (final p in _pedidos) {
      final estado = (p['estado'] ?? '').toString().toUpperCase();
      if (estado == 'CANCELADO') continue;
      final fecha = _parseFecha(p['fechaCreacion'] ?? p['fecha']);
      if (fecha == null || fecha.isBefore(desde)) continue;
      final t = (p['total'] ?? 0).toDouble();
      total += t;
      count++;
      final ep = EstadoPagoHelper.determinarEstadoPago(p);
      if (ep == EstadoPagoHelper.PAGADO) cobrado += t;
      else cobrado += (p['montoPagado'] ?? 0).toDouble();
    }
    return {'total': total, 'cobrado': cobrado, 'count': count};
  }

  // Clientes con pedidos completados sin pagar (por cobrar)
  List<Map<String, dynamic>> get _porCobrar {
    final Map<String, Map<String, dynamic>> byClient = {};
    for (final p in _pedidos) {
      final estado = (p['estado'] ?? '').toString().toUpperCase();
      if (!['COMPLETADO', 'ENTREGADO'].contains(estado)) continue;
      final ep = EstadoPagoHelper.determinarEstadoPago(p);
      if (ep == EstadoPagoHelper.PAGADO) continue;
      final ws = (p['whatsapp'] ?? '').toString();
      final total = (p['total'] ?? 0).toDouble();
      final pagado = (p['montoPagado'] ?? 0).toDouble();
      final pendiente = total - pagado;
      if (pendiente <= 0) continue;
      if (!byClient.containsKey(ws)) {
        byClient[ws] = {
          'cliente': p['cliente'] ?? 'Sin nombre',
          'whatsapp': ws,
          'pendiente': 0.0,
          'pedidos': 0,
          'ultimaFecha': p['fechaCreacion'] ?? p['fecha'],
        };
      }
      byClient[ws]!['pendiente'] = (byClient[ws]!['pendiente'] as double) + pendiente;
      byClient[ws]!['pedidos'] = (byClient[ws]!['pedidos'] as int) + 1;
    }
    final lista = byClient.values.toList();
    lista.sort((a, b) => (b['pendiente'] as double).compareTo(a['pendiente'] as double));
    return lista;
  }

  // Clientes inactivos: pagaron todo pero no han pedido en 30+ días
  List<Map<String, dynamic>> get _clientesInactivos {
    final ahora = DateTime.now();
    final Map<String, Map<String, dynamic>> byClient = {};

    for (final p in _pedidos) {
      final ws = (p['whatsapp'] ?? '').toString();
      if (ws.isEmpty) continue;
      final fecha = _parseFecha(p['fechaCreacion'] ?? p['fecha']);
      if (fecha == null) continue;

      if (!byClient.containsKey(ws)) {
        byClient[ws] = {
          'cliente': p['cliente'] ?? 'Sin nombre',
          'whatsapp': ws,
          'ultimaFecha': fecha,
          'tienePendiente': false,
        };
      } else {
        final prev = byClient[ws]!['ultimaFecha'] as DateTime;
        if (fecha.isAfter(prev)) byClient[ws]!['ultimaFecha'] = fecha;
      }

      final estado = (p['estado'] ?? '').toString().toUpperCase();
      if (['COMPLETADO', 'ENTREGADO'].contains(estado)) {
        final ep = EstadoPagoHelper.determinarEstadoPago(p);
        if (ep != EstadoPagoHelper.PAGADO) {
          byClient[ws]!['tienePendiente'] = true;
        }
      }
    }

    final inactivos = byClient.values.where((c) {
      if (c['tienePendiente'] == true) return false;
      final ultima = c['ultimaFecha'] as DateTime;
      return ahora.difference(ultima).inDays >= 30;
    }).toList();

    inactivos.sort((a, b) {
      final da = ahora.difference(a['ultimaFecha'] as DateTime).inDays;
      final db = ahora.difference(b['ultimaFecha'] as DateTime).inDays;
      return db.compareTo(da);
    });
    return inactivos.take(20).toList();
  }

  // Top productos más vendidos
  List<Map<String, dynamic>> get _topProductos {
    final Map<String, Map<String, dynamic>> counts = {};
    for (final p in _pedidos) {
      final estado = (p['estado'] ?? '').toString().toUpperCase();
      if (estado == 'CANCELADO') continue;
      final detalle = p['productosDetalle'];
      if (detalle is! List) continue;
      for (final item in detalle) {
        final nombre = (item['nombre'] ?? '').toString();
        if (nombre.isEmpty) continue;
        final qty = (item['cantidad'] as num?)?.toDouble() ?? 1;
        final subtotal = (item['subtotal'] as num?)?.toDouble() ?? 0;
        counts[nombre] ??= {'nombre': nombre, 'cantidad': 0.0, 'revenue': 0.0};
        counts[nombre]!['cantidad'] = (counts[nombre]!['cantidad'] as double) + qty;
        counts[nombre]!['revenue'] = (counts[nombre]!['revenue'] as double) + subtotal;
      }
    }
    final lista = counts.values.toList();
    lista.sort((a, b) => (b['cantidad'] as double).compareTo(a['cantidad'] as double));
    return lista.take(5).toList();
  }

  // Resumen por mes
  List<Map<String, dynamic>> get _porMes {
    final Map<String, Map<String, dynamic>> meses = {};
    for (final p in _pedidos) {
      final estado = (p['estado'] ?? '').toString().toUpperCase();
      if (estado == 'CANCELADO') continue;
      final fecha = _parseFecha(p['fechaCreacion'] ?? p['fecha']);
      if (fecha == null) continue;
      final key = '${fecha.year}-${fecha.month.toString().padLeft(2, '0')}';
      final total = (p['total'] ?? 0).toDouble();
      final ep = EstadoPagoHelper.determinarEstadoPago(p);
      final pagado = ep == EstadoPagoHelper.PAGADO ? total : (p['montoPagado'] ?? 0).toDouble();
      meses[key] ??= {'key': key, 'year': fecha.year, 'month': fecha.month, 'total': 0.0, 'cobrado': 0.0, 'count': 0};
      meses[key]!['total'] = (meses[key]!['total'] as double) + total;
      meses[key]!['cobrado'] = (meses[key]!['cobrado'] as double) + pagado;
      meses[key]!['count'] = (meses[key]!['count'] as int) + 1;
    }
    final lista = meses.values.toList();
    lista.sort((a, b) => (b['key'] as String).compareTo(a['key'] as String));
    return lista.take(6).toList();
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return _buildError();

    final ahora = DateTime.now();
    final inicioSemana = ahora.subtract(Duration(days: ahora.weekday - 1));
    final inicioMes = DateTime(ahora.year, ahora.month, 1);
    final inicioMesAnterior = DateTime(ahora.year, ahora.month - 1, 1);
    final finMesAnterior = DateTime(ahora.year, ahora.month, 0, 23, 59, 59);

    final semana = _resumenPeriodo(inicioSemana);
    final mesActual = _resumenPeriodo(inicioMes);
    // Solo mes anterior (sin incluir el mes actual)
    double maPrevTotal = 0; int maPrevCount = 0;
    for (final p in _pedidos) {
      final fecha = _parseFecha(p['fechaCreacion'] ?? p['fecha']);
      if (fecha == null) continue;
      if (fecha.isBefore(inicioMesAnterior) || fecha.isAfter(finMesAnterior)) continue;
      final t = (p['total'] ?? 0).toDouble();
      maPrevTotal += t;
      maPrevCount++;
    }

    final porCobrar = _porCobrar;
    final inactivos = _clientesInactivos;
    final topProductos = _topProductos;
    final porMes = _porMes;

    return RefreshIndicator(
      onRefresh: _cargar,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Header ──
          Row(
            children: [
              const Text('Reportes', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              const Spacer(),
              Text('${_pedidos.length} pedidos', style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
            ],
          ),
          const SizedBox(height: 16),

          // ── Cards de resumen ──
          Row(
            children: [
              Expanded(child: _statCard('Esta semana', semana['total'], semana['count'], Colors.blue)),
              const SizedBox(width: 8),
              Expanded(child: _statCard('Este mes', mesActual['total'], mesActual['count'], Colors.green)),
              const SizedBox(width: 8),
              Expanded(child: _statCard('Mes anterior', maPrevTotal, maPrevCount, Colors.purple)),
            ],
          ),
          const SizedBox(height: 20),

          // ── Top productos ──
          _sectionHeader(Icons.star_rounded, 'Productos más vendidos', Colors.amber, ''),
          if (topProductos.isEmpty)
            _emptyCard('Sin datos aún', Icons.inventory_2_outlined, Colors.grey)
          else
            _topProductosCard(topProductos),
          const SizedBox(height: 20),

          // ── Por mes ──
          _sectionHeader(Icons.calendar_month_rounded, 'Últimos meses', Colors.indigo, ''),
          ...porMes.map((m) => _mesCard(m)),
          const SizedBox(height: 20),

          // ── Clientes inactivos ──
          _sectionHeader(Icons.person_off_outlined, 'Clientes silenciosos', Colors.orange, '${inactivos.length}'),
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'Pagaron todo pero no han pedido en 30+ días. Puede ser buen momento para contactarlos.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ),
          if (inactivos.isEmpty)
            _emptyCard('Sin clientes inactivos', Icons.people_outline, Colors.orange)
          else
            ...inactivos.map((c) => _inactivoCard(c, ahora)),
          const SizedBox(height: 20),

          // ── Por cobrar ──
          _sectionHeader(Icons.warning_amber_rounded, 'Por cobrar', Colors.red, '${porCobrar.length}'),
          if (porCobrar.isEmpty)
            _emptyCard('Todo al día', Icons.check_circle_outline, Colors.green)
          else
            ...porCobrar.map((c) => _porCobrarCard(c)),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  // ── Widgets ───────────────────────────────────────────────────────────────

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 48, color: Colors.red.shade300),
          const SizedBox(height: 12),
          Text(_error!, style: TextStyle(color: Colors.grey.shade600)),
          const SizedBox(height: 16),
          ElevatedButton(onPressed: _cargar, child: const Text('Reintentar')),
        ],
      ),
    );
  }

  Widget _statCard(String label, dynamic total, dynamic count, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(
            'S/ ${(total as double).toStringAsFixed(0)}',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color),
          ),
          Text('${count as int} pedidos', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
        ],
      ),
    );
  }

  Widget _sectionHeader(IconData icon, String title, Color color, String badge) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 8),
          Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          if (badge.isNotEmpty && badge != '0') ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(20)),
              child: Text(badge, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _emptyCard(String msg, IconData icon, Color color) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Text(msg, style: TextStyle(color: Colors.grey.shade600)),
        ],
      ),
    );
  }

  Widget _porCobrarCard(Map<String, dynamic> c) {
    final pendiente = (c['pendiente'] as double?) ?? 0.0;
    final ws = c['whatsapp'].toString();
    final nombre = c['cliente'].toString();
    final pedidos = c['pedidos'] as int;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.shade100),
      ),
      child: Row(
        children: [
          Container(
            width: 42, height: 42,
            decoration: BoxDecoration(color: Colors.red.shade100, borderRadius: BorderRadius.circular(10)),
            child: Center(child: Text(nombre.isNotEmpty ? nombre[0].toUpperCase() : '?',
                style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red.shade700))),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(nombre, style: const TextStyle(fontWeight: FontWeight.w600)),
                Text('$pedidos pedido${pedidos != 1 ? 's' : ''} sin cobrar',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('S/ ${pendiente.toStringAsFixed(2)}',
                  style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red.shade700, fontSize: 15)),
              if (ws.isNotEmpty)
                GestureDetector(
                  onTap: () => _abrirWhatsApp(ws, '¡Hola $nombre! Te recordamos que tienes un pago pendiente. ¿Cuándo podrías cancelarlo? 🙏'),
                  child: Text('Recordar', style: TextStyle(fontSize: 11, color: Colors.green.shade700, fontWeight: FontWeight.w600)),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _inactivoCard(Map<String, dynamic> c, DateTime ahora) {
    final ultima = c['ultimaFecha'] as DateTime;
    final dias = ahora.difference(ultima).inDays;
    final ws = c['whatsapp'].toString();
    final nombre = c['cliente'].toString();

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.shade100),
      ),
      child: Row(
        children: [
          Container(
            width: 42, height: 42,
            decoration: BoxDecoration(color: Colors.orange.shade100, borderRadius: BorderRadius.circular(10)),
            child: Center(child: Text(nombre.isNotEmpty ? nombre[0].toUpperCase() : '?',
                style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange.shade700))),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(nombre, style: const TextStyle(fontWeight: FontWeight.w600)),
                Text('Sin pedir hace $dias días',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              ],
            ),
          ),
          if (ws.isNotEmpty)
            GestureDetector(
              onTap: () => _abrirWhatsApp(ws,
                  '¡Hola $nombre! 👋 ¿Cómo estás? Hace un tiempo que no sabemos de ti. ¿Te podemos ayudar con algo? ¿Quieres hacer un pedido?'),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.green.shade600,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text('Contactar', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _topProductosCard(List<Map<String, dynamic>> productos) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: productos.asMap().entries.map((e) {
          final i = e.key;
          final p = e.value;
          final qty = (p['cantidad'] as double).toInt();
          final revenue = p['revenue'] as double;
          final max = (productos.first['cantidad'] as double);
          final pct = max > 0 ? (p['cantidad'] as double) / max : 0.0;
          final colors = [Colors.amber, Colors.grey.shade400, Colors.brown.shade300, Colors.blue.shade300, Colors.green.shade300];

          return Padding(
            padding: EdgeInsets.only(bottom: i < productos.length - 1 ? 12 : 0),
            child: Row(
              children: [
                Container(
                  width: 24, height: 24,
                  decoration: BoxDecoration(color: colors[i].withOpacity(0.2), shape: BoxShape.circle),
                  child: Center(child: Text('${i + 1}', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: colors[i]))),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(p['nombre'].toString(), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 3),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: pct,
                          backgroundColor: Colors.grey.shade100,
                          valueColor: AlwaysStoppedAnimation(colors[i]),
                          minHeight: 5,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('$qty uds', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                    Text('S/ ${revenue.toStringAsFixed(0)}', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                  ],
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _mesCard(Map<String, dynamic> m) {
    final meses = ['', 'Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun', 'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic'];
    final total = m['total'] as double;
    final cobrado = m['cobrado'] as double;
    final pendiente = total - cobrado;
    final pct = total > 0 ? cobrado / total : 1.0;
    final mes = meses[m['month'] as int];
    final year = m['year'] as int;
    final isThisMonth = m['month'] == DateTime.now().month && year == DateTime.now().year;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isThisMonth ? Colors.indigo.shade50 : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isThisMonth ? Colors.indigo.shade200 : Colors.transparent),
      ),
      child: Row(
        children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              color: isThisMonth ? Colors.indigo.shade100 : Colors.grey.shade200,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(mes, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold,
                    color: isThisMonth ? Colors.indigo.shade700 : Colors.grey.shade600)),
                Text('$year', style: TextStyle(fontSize: 9, color: Colors.grey.shade500)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('S/ ${total.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    const SizedBox(width: 6),
                    Text('· ${m['count']} pedidos', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                  ],
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: pct.clamp(0.0, 1.0),
                    backgroundColor: Colors.red.shade100,
                    valueColor: const AlwaysStoppedAnimation(Colors.green),
                    minHeight: 5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (pendiente > 0)
                Text('−S/ ${pendiente.toStringAsFixed(0)}',
                    style: TextStyle(fontSize: 12, color: Colors.red.shade400, fontWeight: FontWeight.w600))
              else
                Icon(Icons.check_circle, size: 16, color: Colors.green.shade400),
              Text('${(pct * 100).toInt()}% cobrado',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _abrirWhatsApp(String numero, String mensaje) async {
    final ws = numero.replaceAll(RegExp(r'[^0-9]'), '');
    if (ws.isEmpty) return;
    final url = 'https://wa.me/$ws?text=${Uri.encodeComponent(mensaje)}';
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
