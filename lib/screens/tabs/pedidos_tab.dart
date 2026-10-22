import 'dart:async';
import 'package:flutter/material.dart';
import '../../services/api_service.dart';
import '../crear_pedido_screen.dart';
import 'pedidos/helpers/estado_pago_helper.dart';
import 'pedidos/widgets/pedido_card.dart';
import 'pedidos/widgets/detalle_pedido/detalle_pedido_sheet.dart';
import 'pedidos/widgets/nuevo_pedido_sheet.dart';
import 'pedidos/widgets/pedidos_filtros.dart';
import '../../theme/fincas_tokens.dart';
import '../../widgets/fincas_widgets.dart';
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

  @override
  Widget build(BuildContext context) {
    final stats = _statsCache;

    return Scaffold(
      backgroundColor: FincasColors.background,
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        behavior: HitTestBehavior.translucent,
        child: Column(
          children: [
            // Búsqueda y filtros: un solo bloque compacto
            Container(
              padding: const EdgeInsets.fromLTRB(FincasSpacing.l, FincasSpacing.s, FincasSpacing.l, FincasSpacing.m),
              decoration: const BoxDecoration(
                color: FincasColors.surface,
                border: Border(bottom: BorderSide(color: FincasColors.divider)),
              ),
              child: Column(
                children: [
                  TextField(
                    focusNode: _searchFocus,
                    textInputAction: TextInputAction.search,
                    onChanged: (value) {
                      _searchTimer?.cancel();
                      _searchTimer = Timer(const Duration(milliseconds: 400), () {
                        if (value != _busqueda) _buscar(value);
                      });
                    },
                    decoration: InputDecoration(
                      hintText: 'Buscar pedido...',
                      prefixIcon: const Icon(Icons.search, color: FincasColors.textSecondary),
                      suffixIcon: _busqueda.isNotEmpty
                          ? IconButton(
                              tooltip: 'Borrar búsqueda',
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _busqueda = '';
                                _cargarPedidos();
                              },
                            )
                          : null,
                      filled: true,
                      fillColor: FincasColors.background,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(FincasRadii.medium), borderSide: BorderSide.none),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(FincasRadii.medium), borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(horizontal: FincasSpacing.l, vertical: FincasSpacing.m),
                    ),
                  ),
                  const SizedBox(height: FincasSpacing.s),
                  Row(
                    children: [
                      Expanded(
                        child: PedidosFiltroChip(
                          label: 'Pendientes',
                          tone: FincasTone.warning,
                          count: _countPendientes,
                          selected: _filtroEstado == 'PENDIENTES',
                          onTap: () => _cambiarFiltro('PENDIENTES'),
                        ),
                      ),
                      const SizedBox(width: FincasSpacing.s),
                      Expanded(
                        child: PedidosFiltroChip(
                          label: 'Historial',
                          tone: FincasTone.success,
                          count: _countHistorial,
                          selected: _filtroEstado == 'HISTORIAL',
                          onTap: () => _cambiarFiltro('HISTORIAL'),
                        ),
                      ),
                    ],
                  ),
                  // Subfiltros del historial
                  if (_filtroEstado == 'HISTORIAL') ...[
                    const SizedBox(height: FincasSpacing.s),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          PedidosSubFiltroChip(
                            label: 'Todos',
                            count: _countHistorial,
                            selected: _subFiltroHistorial == 'TODOS',
                            onTap: () => _cambiarSubFiltro('TODOS'),
                          ),
                          const SizedBox(width: FincasSpacing.s),
                          PedidosSubFiltroChip(
                            label: 'Pagados',
                            count: _countPagados,
                            tone: FincasTone.success,
                            selected: _subFiltroHistorial == 'PAGADOS',
                            onTap: () => _cambiarSubFiltro('PAGADOS'),
                          ),
                          const SizedBox(width: FincasSpacing.s),
                          PedidosSubFiltroChip(
                            label: 'Por cobrar',
                            count: _countPorCobrar,
                            tone: FincasTone.error,
                            selected: _subFiltroHistorial == 'PENDIENTE_PAGO',
                            onTap: () => _cambiarSubFiltro('PENDIENTE_PAGO'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // Resumen solo en historial
            if (_filtroEstado == 'HISTORIAL' && !_isLoading && _error == null)
              PedidosResumen(
                vendido: stats['totalVendido'],
                cobrado: stats['totalCobrado'],
                porCobrar: stats['totalPendiente'],
                hayAlerta: stats['pendientesPago'] > 0,
              ),

            Expanded(child: _buildBody()),
          ],
        ),
      ),
      // Una sola acción principal de creación; el tipo (pedido o pre-venta) se elige al tocarla.
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'fab_pedidos',
        onPressed: _nuevo,
        shape: const StadiumBorder(),
        label: const Text('Nuevo pedido'),
      ),
    );
  }

  Future<void> _nuevo() async {
    final tipo = await showNuevoPedidoSheet(context);
    if (!mounted || tipo == null) return;
    if (tipo == NuevoPedidoTipo.preventa) {
      _abrirNuevaPreventa();
      return;
    }
    final nuevoPedido = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(builder: (_) => const CrearPedidoScreen()),
    );
    if (!mounted) return;
    if (nuevoPedido != null) {
      _cargarPedidos();
      _mostrarDetallePedido(nuevoPedido);
    }
  }

  void _cambiarFiltro(String filtro) {
    if (_filtroEstado == filtro) return;
    setState(() {
      _filtroEstado = filtro;
      if (filtro != 'HISTORIAL') _subFiltroHistorial = 'TODOS';
    });
    _cargarPedidos();
  }

  void _cambiarSubFiltro(String filtro) {
    if (_subFiltroHistorial == filtro) return;
    setState(() => _subFiltroHistorial = filtro);
    _cargarPedidos(); // Recargar con nuevo filtro server-side
  }

  Future<void> _onRefresh() async {
    await _cargarPedidos();
    _cargarContadores();
  }

  Widget _buildSkeletonCard(double opacity) {
    final c = FincasColors.sand.withValues(alpha: 0.5 + opacity);
    final cl = FincasColors.sand.withValues(alpha: 0.3 + opacity);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: FincasSpacing.l, vertical: FincasSpacing.xs + 1),
      padding: const EdgeInsets.all(FincasSpacing.m + 2),
      decoration: BoxDecoration(
        color: FincasColors.surface,
        borderRadius: BorderRadius.circular(FincasRadii.large),
        border: Border.all(color: FincasColors.border),
      ),
      child: Row(children: [
        Container(width: 40, height: 40, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
        const SizedBox(width: FincasSpacing.m),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(height: 14, width: 150, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(4))),
            const SizedBox(height: 8),
            Container(height: 11, width: 110, decoration: BoxDecoration(color: cl, borderRadius: BorderRadius.circular(4))),
          ]),
        ),
        Container(height: 16, width: 64, decoration: BoxDecoration(color: cl, borderRadius: BorderRadius.circular(4))),
      ]),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return AnimatedBuilder(
        animation: _shimmerCtrl,
        builder: (_, __) {
          final opacity = _shimmerCtrl.value * 0.3;
          return ListView.builder(
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.only(top: FincasSpacing.s, bottom: 124),
            itemCount: 8,
            itemBuilder: (_, __) => _buildSkeletonCard(opacity),
          );
        },
      );
    }

    if (_error != null) {
      return RefreshIndicator(
        color: FincasColors.ink,
        onRefresh: _onRefresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: FincasSpacing.xl, vertical: FincasSpacing.xxxl),
          children: [
            const FincasMessageState(
              title: 'No se pudieron cargar los pedidos',
              message: 'Revisa tu conexión e intenta de nuevo.',
              tone: FincasTone.error,
            ),
            const SizedBox(height: FincasSpacing.xl),
            Center(
              child: SizedBox(
                width: 220,
                child: FincasSecondaryButton(label: 'Reintentar', onPressed: _cargarPedidos),
              ),
            ),
          ],
        ),
      );
    }

    if (_pedidos.isEmpty) {
      String mensaje;
      String submensaje;
      if (_busqueda.isNotEmpty) {
        mensaje = 'Sin resultados';
        submensaje = 'No encontramos pedidos para "$_busqueda".';
      } else if (_filtroEstado == 'PENDIENTES') {
        mensaje = 'No hay pedidos pendientes';
        submensaje = 'Jala hacia abajo para actualizar.';
      } else if (_subFiltroHistorial == 'PAGADOS') {
        mensaje = 'No hay pedidos pagados';
        submensaje = 'Los pedidos cobrados aparecerán aquí.';
      } else if (_subFiltroHistorial == 'PENDIENTE_PAGO') {
        mensaje = 'Todo cobrado';
        submensaje = 'No tienes pagos pendientes.';
      } else {
        mensaje = 'No hay historial';
        submensaje = 'Los pedidos completados aparecerán aquí.';
      }

      return RefreshIndicator(
        color: FincasColors.ink,
        onRefresh: _onRefresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: FincasSpacing.xl, vertical: FincasSpacing.xxxl),
          children: [FincasMessageState(title: mensaje, message: submensaje)],
        ),
      );
    }

    return RefreshIndicator(
      color: FincasColors.ink,
      onRefresh: _onRefresh,
      child: ListView.builder(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(top: FincasSpacing.s, bottom: 124), // espacio para los botones flotantes
        itemCount: _pedidos.length + (_hayMas ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == _pedidos.length) {
            return Padding(
              padding: const EdgeInsets.all(FincasSpacing.l),
              child: Center(
                child: _isLoadingMore
                    ? const FincasLoader(message: 'Cargando más...')
                    : FincasTextButton(
                        label: 'Cargar más (${_pedidos.length} de $_totalPedidos)',
                        onPressed: _cargarMasPedidos,
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
