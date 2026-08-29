import 'package:flutter/material.dart';
import '../../services/api_service.dart';
import '../detalle_cliente_screen.dart';

class ClientesTab extends StatefulWidget {
  const ClientesTab({super.key});

  @override
  State<ClientesTab> createState() => _ClientesTabState();
}

class _ClientesTabState extends State<ClientesTab> with SingleTickerProviderStateMixin {
  late AnimationController _shimmerCtrl;
  List<Map<String, dynamic>> _clientes = [];
  bool _isLoading = true;
  String? _error;
  String _busqueda = '';
  String? _filtroEstado = 'ACTIVO';
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _shimmerCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);
    _cargarClientes();
  }

  @override
  void dispose() {
    _shimmerCtrl.dispose();
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  Future<void> _cargarClientes() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    final result = await ApiService.getClientes(
      buscar: _busqueda.isNotEmpty ? _busqueda : null,
      // ordenar=actividad es default en backend ahora
    );

    setState(() {
      _isLoading = false;
      if (result.isSuccess) {
        var clientes = result.data!;
        if (_filtroEstado != null) {
          clientes = clientes.where((c) => c['estado'] == _filtroEstado).toList();
        }
        _clientes = clientes;
      } else {
        _error = result.error;
      }
    });
  }

  void _buscar(String query) {
    _busqueda = query;
    _cargarClientes();
  }

  void _volverALista() {
    _searchFocus.unfocus();
    if (_busqueda.isNotEmpty) {
      _searchController.clear();
      _busqueda = '';
      _cargarClientes();
    }
  }

  void _irANuevoCliente() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const DetalleClienteScreen()),
    );
    _volverALista();
    if (result == true) _cargarClientes();
  }

  void _irADetalle(Map<String, dynamic> cliente) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => DetalleClienteScreen(cliente: cliente)),
    );
    _volverALista();
    if (result == true) _cargarClientes();
  }

  Color _getEstadoColor(String? estado) {
    switch (estado) {
      case 'ACTIVO': return Colors.green;
      case 'INACTIVO': return Colors.grey;
      case 'INVITADO': return Colors.purple;
      default: return Colors.blue;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        behavior: HitTestBehavior.translucent,
        child: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            color: Colors.white,
            child: Column(
              children: [
                TextField(
                  controller: _searchController,
                  focusNode: _searchFocus,
                  onChanged: (value) {
                    Future.delayed(const Duration(milliseconds: 500), () {
                      if (value != _busqueda) _buscar(value);
                    });
                  },
                  decoration: InputDecoration(
                    hintText: 'Buscar cliente...',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _busqueda.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _searchController.clear();
                              _busqueda = '';
                              _cargarClientes();
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: Colors.grey.shade100,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildFiltroChip('ACTIVO', 'Activos', Icons.check_circle),
                      const SizedBox(width: 8),
                      _buildFiltroChip(null, 'Todos', Icons.people),
                      const SizedBox(width: 8),
                      _buildFiltroChip('INVITADO', 'Invitados', Icons.person_outline),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(child: _buildBody()),
        ],
      ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'fab_clientes',
        onPressed: _irANuevoCliente,
        backgroundColor: Colors.green.shade600,
        icon: const Icon(Icons.person_add),
        label: const Text('Nuevo Cliente', style: TextStyle(fontWeight: FontWeight.w600)),
      ),
    );
  }

  Widget _buildFiltroChip(String? estado, String label, IconData icon) {
    final selected = _filtroEstado == estado;
    final color = estado != null ? _getEstadoColor(estado) : Colors.blue;
    
    return GestureDetector(
      onTap: () {
        setState(() => _filtroEstado = estado);
        _cargarClientes();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? color : Colors.grey.shade200,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: selected ? Colors.white : Colors.grey.shade600),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: selected ? Colors.white : Colors.grey.shade700,
                fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSkeletonCliente(double opacity) {
    final c = Colors.grey.withOpacity(opacity);
    final cl = Colors.grey.withOpacity(opacity * 0.6);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
      child: Row(children: [
        Container(width: 46, height: 46, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(height: 13, width: 130, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(4))),
          const SizedBox(height: 6),
          Container(height: 11, width: 90, decoration: BoxDecoration(color: cl, borderRadius: BorderRadius.circular(4))),
        ])),
        Container(height: 16, width: 50, decoration: BoxDecoration(color: cl, borderRadius: BorderRadius.circular(4))),
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
            itemCount: 10,
            itemBuilder: (_, __) => _buildSkeletonCliente(opacity),
          );
        },
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: Colors.red.shade300),
            const SizedBox(height: 16),
            Text('Error: $_error'),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _cargarClientes,
              icon: const Icon(Icons.refresh),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      );
    }

    if (_clientes.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.people_outline, size: 80, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              _busqueda.isEmpty && _filtroEstado == null ? 'No hay clientes' : 'Sin resultados',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: Colors.grey.shade600),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _cargarClientes,
      child: ListView.builder(
        padding: const EdgeInsets.only(top: 8, bottom: 100),
        itemCount: _clientes.length,
        itemBuilder: (context, index) {
          final cliente = _clientes[index];
          return _ClienteCard(
            cliente: cliente,
            onTap: () => _irADetalle(cliente),
          );
        },
      ),
    );
  }
}

class _ClienteCard extends StatelessWidget {
  final Map<String, dynamic> cliente;
  final VoidCallback onTap;

  const _ClienteCard({required this.cliente, required this.onTap});

  Color _getEstadoColor(String? estado) {
    switch (estado) {
      case 'ACTIVO': return Colors.green;
      case 'INACTIVO': return Colors.grey;
      case 'INVITADO': return Colors.purple;
      default: return Colors.blue;
    }
  }

  @override
  Widget build(BuildContext context) {
    final nombreNegocio = cliente['nombreNegocio'] ?? cliente['nombre'] ?? '';
    final nombreResponsable = cliente['nombreResponsable'] ?? '';
    final whatsapp = cliente['whatsapp'] ?? '';
    final totalComprado = (cliente['totalComprado'] ?? 0).toDouble();
    final totalPedidos = (cliente['totalPedidos'] ?? 0);
    final pedidosActivos = (cliente['pedidosActivos'] ?? 0);
    final tipoEnvio = cliente['tipoEnvio'] ?? '';
    final empresaEnvio = cliente['empresaEnvio'] ?? '';
    final estado = cliente['estado'] ?? 'ACTIVO';

    String displayName = nombreNegocio.isNotEmpty ? nombreNegocio : nombreResponsable;
    if (displayName.isEmpty) displayName = 'Sin nombre';

    final tienePedidos = totalPedidos > 0;
    final tieneActivos = pedidosActivos > 0;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        elevation: 1,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // Avatar
                Stack(
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: _getEstadoColor(estado).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(28),
                      ),
                      child: Center(
                        child: Text(
                          displayName.isNotEmpty ? displayName[0].toUpperCase() : '?',
                          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: _getEstadoColor(estado)),
                        ),
                      ),
                    ),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        width: 16,
                        height: 16,
                        decoration: BoxDecoration(
                          color: _getEstadoColor(estado),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 16),
                
                // Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              displayName,
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      if (nombreResponsable.isNotEmpty && nombreNegocio.isNotEmpty)
                        Text(
                          nombreResponsable,
                          style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                        ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(Icons.phone, size: 14, color: Colors.grey.shade500),
                          const SizedBox(width: 4),
                          Text(whatsapp, style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
                        ],
                      ),
                      // Badges de actividad
                      if (tieneActivos) ...[
                        const SizedBox(height: 6),
                        _buildBadge('$pedidosActivos pendiente${pedidosActivos > 1 ? 's' : ''}', Colors.orange),
                      ],
                      if (!tienePedidos && (tipoEnvio.isNotEmpty || empresaEnvio.isNotEmpty)) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(Icons.local_shipping, size: 14, color: Colors.blue.shade400),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                '${tipoEnvio.isNotEmpty ? tipoEnvio : ''} ${empresaEnvio.isNotEmpty ? '- $empresaEnvio' : ''}'.trim(),
                                style: TextStyle(fontSize: 12, color: Colors.blue.shade600),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                
                // Stats columna derecha
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (totalComprado > 0)
                      Text(
                        'S/ ${totalComprado.toStringAsFixed(0)}',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.green.shade600,
                        ),
                      ),
                    if (tienePedidos)
                      Text(
                        '$totalPedidos pedido${totalPedidos > 1 ? 's' : ''}',
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                      ),
                    if (!tienePedidos)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'Sin pedidos',
                          style: TextStyle(fontSize: 10, color: Colors.grey.shade400),
                        ),
                      ),
                    const SizedBox(height: 4),
                    Icon(Icons.chevron_right, color: Colors.grey.shade400),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: color),
      ),
    );
  }
}
