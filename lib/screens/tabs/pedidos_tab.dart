import 'dart:async';
import 'package:flutter/material.dart';
import '../../services/api_service.dart';
import '../crear_pedido_screen.dart';
import 'pedidos/helpers/estado_pago_helper.dart';
import 'pedidos/widgets/pedido_card.dart';
import 'pedidos/widgets/detalle_pedido/detalle_pedido_sheet.dart';
import 'pedidos/widgets/reportes_sheet.dart';
import '../crear_preventa_screen.dart';

class PedidosTab extends StatefulWidget {
  final String? businessName;
  const PedidosTab({super.key, this.businessName});

  @override
  State<PedidosTab> createState() => _PedidosTabState();
}

class _PedidosTabState extends State<PedidosTab> with SingleTickerProviderStateMixin {
  late AnimationController _shimmerCtrl;
  // Data
  List<Map<String, dynamic>> _pedidos = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  String? _error;
  
  // Paginación
  int _paginaActual = 1;
  int _totalPedidos = 0;
  int _totalPaginas = 1;
  bool _hayMas = false;
  static const int _limite = 50;
  
  // Filtros
  String _busqueda = '';
  String _filtroEstado = 'PENDIENTES'; // PENDIENTES | HISTORIAL
  String _subFiltroHistorial = 'TODOS'; // TODOS | PAGADOS | PENDIENTE_PAGO
  final _searchFocus = FocusNode();

  // Contadores server-side (se actualizan al cambiar de vista)
  int _countPendientes = 0;
  int _countHistorial = 0;
  int _countPagados = 0;
  int _countPorCobrar = 0;
  // Scroll controller para infinite scroll
  final ScrollController _scrollController = ScrollController();
  Timer? _searchTimer;

  // Cache de estadísticas — se recalcula solo cuando cambia _pedidos
  Map<String, dynamic> _statsCache = {'totalVendido': 0.0, 'totalCobrado': 0.0, 'totalPendiente': 0.0, 'pendientesPago': 0};

  @override
  void initState() {
    super.initState();
    _shimmerCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);
    _scrollController.addListener(_onScroll);
    _cargarPedidos();
    _cargarContadores();
  }

  @override
  void dispose() {
    _shimmerCtrl.dispose();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _searchTimer?.cancel();
    _searchFocus.dispose();
    super.dispose();
  }
  
  // Detectar scroll al fondo para cargar más
  void _onScroll() {
    if (_scrollController.position.pixels >= 
        _scrollController.position.maxScrollExtent - 200) {
      if (!_isLoadingMore && _hayMas) {
        _cargarMasPedidos();
      }
    }
  }

  /// Vista actual según filtros seleccionados
  String get _vistaActual {
    if (_filtroEstado == 'PENDIENTES') return 'PENDIENTES';
    // HISTORIAL con subfiltros
    switch (_subFiltroHistorial) {
      case 'PAGADOS': return 'PAGADOS';
      case 'PENDIENTE_PAGO': return 'POR_COBRAR';
      default: return 'HISTORIAL'; // TODOS
    }
  }

  /// Cargar primera página de pedidos
  Future<void> _cargarPedidos() async {
    setState(() {
      _isLoading = true;
      _error = null;
      _paginaActual = 1;
      _pedidos = [];
    });

    final result = await ApiService.getPedidos(
      vista: _vistaActual,
      cliente: _busqueda.isNotEmpty ? _busqueda : null,
      tipo: null,
      pagina: 1,
      limite: _limite,
    );

    setState(() {
      _isLoading = false;
      if (result.isSuccess) {
        final data = result.data!;
        _pedidos = data.pedidos;
        _totalPedidos = data.total;
        _totalPaginas = data.totalPaginas;
        _hayMas = data.hayMas;
        _paginaActual = data.pagina;
        _recalcularStats();
      } else {
        _error = result.error;
      }
    });
  }
  
  /// Cargar siguiente página (scroll infinito)
  Future<void> _cargarMasPedidos() async {
    if (_isLoadingMore || !_hayMas) return;
    
    setState(() => _isLoadingMore = true);
    
    final result = await ApiService.getPedidos(
      vista: _vistaActual,
      cliente: _busqueda.isNotEmpty ? _busqueda : null,
      tipo: null,
      pagina: _paginaActual + 1,
      limite: _limite,
    );
    
    setState(() {
      _isLoadingMore = false;
      if (result.isSuccess) {
        final data = result.data!;
        _pedidos.addAll(data.pedidos);
        _totalPedidos = data.total;
        _totalPaginas = data.totalPaginas;
        _hayMas = data.hayMas;
        _paginaActual = data.pagina;
        _recalcularStats();
      }
    });
  }
  
  /// Cargar contadores para los chips (llamadas ligeras)
  Future<void> _cargarContadores() async {
    final futures = await Future.wait([
      ApiService.getPedidos(vista: 'PENDIENTES', pagina: 1, limite: 1),
      ApiService.getPedidos(vista: 'HISTORIAL', pagina: 1, limite: 1),
      ApiService.getPedidos(vista: 'PAGADOS', pagina: 1, limite: 1),
      ApiService.getPedidos(vista: 'POR_COBRAR', pagina: 1, limite: 1),
    ]);

    if (mounted) {
      setState(() {
        if (futures[0].isSuccess) _countPendientes = futures[0].data!.total;
        if (futures[1].isSuccess) _countHistorial = futures[1].data!.total;
        if (futures[2].isSuccess) _countPagados = futures[2].data!.total;
        if (futures[3].isSuccess) _countPorCobrar = futures[3].data!.total;
      });
    }
  }

  void _recalcularStats() {
    double totalVendido = 0;
    double totalCobrado = 0;
    int pendientesPago = 0;
    for (var p in _pedidos) {
      if ((p['estado'] ?? '').toString().toUpperCase() != 'COMPLETADO') continue;
      final total = (p['total'] ?? 0).toDouble();
      totalVendido += total;
      final ep = EstadoPagoHelper.determinarEstadoPago(p);
      if (ep == EstadoPagoHelper.PAGADO) {
        totalCobrado += total;
      } else if (ep == EstadoPagoHelper.PARCIAL) {
        totalCobrado += (p['montoPagado'] ?? 0).toDouble();
        pendientesPago++;
      } else {
        pendientesPago++;
      }
    }
    _statsCache = {
      'totalVendido': totalVendido,
      'totalCobrado': totalCobrado,
      'totalPendiente': totalVendido - totalCobrado,
      'pendientesPago': pendientesPago,
    };
  }

  void _buscar(String query) {
    _busqueda = query;
    _cargarPedidos(); // Recargar con búsqueda server-side
  }

  void _mostrarReportes() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => ReportesSheet(pedidos: _pedidos),
    );
  }

  @override
  Widget build(BuildContext context) {
    final stats = _statsCache;
    
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        behavior: HitTestBehavior.translucent,
        child: Column(
        children: [
          // Header con búsqueda y botón de reportes
          Container(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            color: Colors.white,
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        focusNode: _searchFocus,
                        onChanged: (value) {
                          _searchTimer?.cancel();
                          _searchTimer = Timer(const Duration(milliseconds: 400), () {
                            if (value != _busqueda) _buscar(value);
                          });
                        },
                        decoration: InputDecoration(
                          hintText: 'Buscar pedido...',
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: _busqueda.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear),
                                  onPressed: () {
                                    _busqueda = '';
                                    _cargarPedidos();
                                  },
                                )
                              : null,
                          filled: true,
                          fillColor: Colors.grey.shade100,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Botón de Reportes
                    Material(
                      color: Colors.indigo.shade600,
                      borderRadius: BorderRadius.circular(12),
                      child: InkWell(
                        onTap: _mostrarReportes,
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          child: const Icon(Icons.bar_chart_rounded, color: Colors.white, size: 24),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // Filtros principales
                Row(
                  children: [
                    Expanded(
                      child: _buildFiltroChip(
                        'PENDIENTES',
                        'Pendientes',
                        Icons.schedule,
                        Colors.orange,
                        _countPendientes,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildFiltroChip(
                        'HISTORIAL',
                        'Historial',
                        Icons.history,
                        Colors.green,
                        _countHistorial,
                      ),
                    ),
                  ],
                ),
                // Subfiltros para Historial
                if (_filtroEstado == 'HISTORIAL') ...[
                  const SizedBox(height: 8),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _buildSubFiltroChip('TODOS', 'Todos', Icons.list, null, _countHistorial),
                        const SizedBox(width: 8),
                        _buildSubFiltroChip(
                          'PAGADOS',
                          'Pagados',
                          Icons.check_circle,
                          Colors.green,
                          _countPagados,
                        ),
                        const SizedBox(width: 8),
                        _buildSubFiltroChip(
                          'PENDIENTE_PAGO',
                          'Por cobrar',
                          Icons.warning_amber_rounded,
                          Colors.red,
                          _countPorCobrar,
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          
          // Mini resumen solo en historial
          if (_filtroEstado == 'HISTORIAL' && !_isLoading && _error == null)
            Container(
              margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.indigo.shade50, Colors.blue.shade50],
                ),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.indigo.shade100),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _buildMiniStat(
                      'Vendido',
                      stats['totalVendido'],
                      Colors.indigo,
                    ),
                  ),
                  Container(
                    width: 1,
                    height: 30,
                    color: Colors.indigo.shade200,
                  ),
                  Expanded(
                    child: _buildMiniStat(
                      'Cobrado',
                      stats['totalCobrado'],
                      Colors.green,
                    ),
                  ),
                  Container(
                    width: 1,
                    height: 30,
                    color: Colors.indigo.shade200,
                  ),
                  Expanded(
                    child: _buildMiniStat(
                      'Por cobrar',
                      stats['totalPendiente'],
                      Colors.red,
                      showAlert: stats['pendientesPago'] > 0,
                    ),
                  ),
                ],
              ),
            ),
          
          Expanded(child: _buildBody()),
        ],
      ),
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Botón Pre-venta
          FloatingActionButton.extended(
            heroTag: 'fab_preventa',
            onPressed: _abrirNuevaPreventa,
            backgroundColor: const Color(0xFFFF6B00),
            icon: const Icon(Icons.local_fire_department, size: 18),
            label: const Text('Pre-venta', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          ),
          const SizedBox(height: 10),
          // Botón Nuevo Pedido
          FloatingActionButton.extended(
            heroTag: 'fab_pedidos',
            onPressed: () async {
              final nuevoPedido = await Navigator.push<Map<String, dynamic>>(
                context,
                MaterialPageRoute(builder: (_) => const CrearPedidoScreen()),
              );
              if (!mounted) return;
              if (nuevoPedido != null) {
                _cargarPedidos();
                _mostrarDetallePedido(nuevoPedido);
              }
            },
            backgroundColor: Colors.blue.shade600,
            icon: const Icon(Icons.add_shopping_cart),
            label: const Text('Nuevo Pedido', style: TextStyle(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Widget _buildMiniStat(
    String label,
    double valor,
    Color color, {
    bool showAlert = false,
  }) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 2),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'S/${valor.toStringAsFixed(0)}',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            if (showAlert) ...[
              const SizedBox(width: 4),
              Icon(
                Icons.warning_amber_rounded,
                size: 14,
                color: Colors.red.shade400,
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _buildFiltroChip(
    String filtro,
    String label,
    IconData icon,
    Color color,
    int count,
  ) {
    final selected = _filtroEstado == filtro;
    
    return GestureDetector(
      onTap: () {
        if (_filtroEstado == filtro) return; // Ya seleccionado
        setState(() {
          _filtroEstado = filtro;
          if (filtro != 'HISTORIAL') _subFiltroHistorial = 'TODOS';
        });
        _cargarPedidos();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? color : Colors.grey.shade200,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 18,
              color: selected ? Colors.white : Colors.grey.shade600,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  color: selected ? Colors.white : Colors.grey.shade700,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (count > 0) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: selected
                      ? Colors.white.withOpacity(0.3)
                      : Colors.grey.shade400,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$count',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSubFiltroChip(
    String filtro,
    String label,
    IconData icon, [
    Color? activeColor,
    int count = 0,
  ]) {
    final selected = _subFiltroHistorial == filtro;
    final color = activeColor ?? Colors.grey.shade600;
    
    return GestureDetector(
      onTap: () {
        if (_subFiltroHistorial == filtro) return;
        setState(() => _subFiltroHistorial = filtro);
        _cargarPedidos(); // Recargar con nuevo filtro server-side
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? color.withOpacity(0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? color : Colors.grey.shade300,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: selected ? color : Colors.grey.shade500,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: selected ? color : Colors.grey.shade600,
                fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
            if (count > 0) ...[
              const SizedBox(width: 4),
              Text(
                '($count)',
                style: TextStyle(
                  fontSize: 11,
                  color: selected ? color : Colors.grey.shade500,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _onRefresh() async {
    await _cargarPedidos();
    _cargarContadores();
  }

  Widget _buildSkeletonCard(double opacity) {
    final c = Colors.grey.withOpacity(opacity);
    final cl = Colors.grey.withOpacity(opacity * 0.6);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 36, height: 36, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(height: 13, width: 150, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(4))),
            const SizedBox(height: 6),
            Container(height: 11, width: 100, decoration: BoxDecoration(color: cl, borderRadius: BorderRadius.circular(4))),
          ])),
          Container(height: 18, width: 64, decoration: BoxDecoration(color: cl, borderRadius: BorderRadius.circular(4))),
        ]),
        const SizedBox(height: 10),
        Container(height: 10, decoration: BoxDecoration(color: cl, borderRadius: BorderRadius.circular(4))),
      ]),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return AnimatedBuilder(
        animation: _shimmerCtrl,
        builder: (_, __) {
          final opacity = 0.25 + _shimmerCtrl.value * 0.25;
          return ListView.builder(
            padding: const EdgeInsets.only(top: 8, bottom: 100),
            itemCount: 8,
            itemBuilder: (_, __) => _buildSkeletonCard(opacity),
          );
        },
      );
    }

    if (_error != null) {
      return RefreshIndicator(
        onRefresh: _onRefresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(height: MediaQuery.of(context).size.height * 0.3),
            Column(
              children: [
                Icon(Icons.error_outline, size: 64, color: Colors.red.shade300),
                const SizedBox(height: 16),
                Text('Error: $_error'),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: _cargarPedidos,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Reintentar'),
                ),
              ],
            ),
          ],
        ),
      );
    }

    if (_pedidos.isEmpty) {
      String mensaje = '';
      String submensaje = '';
      IconData icono = Icons.inbox_outlined;

      if (_filtroEstado == 'PENDIENTES') {
        mensaje = 'No hay pedidos pendientes';
        submensaje = 'Jala hacia abajo para actualizar';
        icono = Icons.inbox_outlined;
      } else if (_subFiltroHistorial == 'PAGADOS') {
        mensaje = 'No hay pedidos pagados';
        submensaje = 'Los pedidos cobrados aparecerán aquí';
        icono = Icons.check_circle_outline;
      } else if (_subFiltroHistorial == 'PENDIENTE_PAGO') {
        mensaje = '¡Excelente! Todo cobrado';
        submensaje = 'No tienes pagos pendientes';
        icono = Icons.celebration;
      } else {
        mensaje = 'No hay historial';
        submensaje = 'Los pedidos completados aparecerán aquí';
        icono = Icons.history;
      }

      return RefreshIndicator(
        onRefresh: _onRefresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(height: MediaQuery.of(context).size.height * 0.25),
            Column(
              children: [
                Icon(icono, size: 80, color: Colors.grey.shade400),
                const SizedBox(height: 16),
                Text(
                  mensaje,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(submensaje, style: TextStyle(color: Colors.grey.shade500)),
              ],
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _onRefresh,
      child: ListView.builder(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(top: 8, bottom: 100),
        itemCount: _pedidos.length + (_hayMas ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == _pedidos.length) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: _isLoadingMore
                    ? const CircularProgressIndicator()
                    : TextButton(
                        onPressed: _cargarMasPedidos,
                        child: Text(
                          'Cargar más (${_pedidos.length} de $_totalPedidos)',
                          style: TextStyle(color: Colors.blue.shade600),
                        ),
                      ),
              ),
            );
          }

          return RepaintBoundary(
            child: PedidoCard(
              pedido: _pedidos[index],
              onTap: () => _mostrarDetallePedido(_pedidos[index]),
              mostrarAlertaPago: _filtroEstado == 'HISTORIAL',
            ),
          );
        },
      ),
    );
  }

  void _abrirNuevaPreventa() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const CrearPreventaScreen()),
    ).then((creado) {
      if (creado == true) {
        _cargarPedidos();
        _cargarContadores();
      }
    });
  }

  void _mostrarDetallePedido(Map<String, dynamic> pedido) {
    _searchFocus.unfocus();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DetallePedidoSheet(
        pedido: pedido,
        onActualizado: () {
          _cargarPedidos();
          _cargarContadores();
        },
        businessName: widget.businessName,
      ),
    ).then((_) => _searchFocus.unfocus());
  }

}
