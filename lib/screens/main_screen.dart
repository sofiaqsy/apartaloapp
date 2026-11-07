import '../services/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import '../services/administracion_service.dart';
import '../services/api_service.dart';
import '../services/notification_service.dart';
import '../providers/printer_provider.dart';
import 'login_screen.dart';
import 'tabs/administracion_tab.dart' show AdministracionTab, pagarConComprobante, claveAreasElegidas;
import 'tabs/productos_tab.dart';
import 'tabs/clientes_tab.dart';
import 'tabs/pedidos_tab.dart';
import 'settings/settings_screen.dart';
import 'perfil_screen.dart';
import 'businesses_screen.dart';
import '../services/session_store.dart';
import '../widgets/fincas_widgets.dart';
import 'business_requests_screen.dart';
import 'team_screen.dart';
import '../theme/legacy_theme.dart';
import '../services/comprobante_service.dart';
import 'elegir_pedido_comprobante_screen.dart';
import 'package:flutter/cupertino.dart' show CupertinoPageRoute;

class MainScreen extends StatefulWidget {
  final String businessId;
  final String businessName;

  const MainScreen({
    super.key,
    required this.businessId,
    required this.businessName,
  });

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    ApiService.businessId = widget.businessId;
    AdministracionService.olvidarMemoria(); // otra cuenta u otro negocio: nada de lo visto antes
    _loadRole();
    _initializeServices();
    // Un comprobante compartido desde WhatsApp abre Pedidos y "¿De qué pedido es?" (6 nov 2026).
    ComprobanteService.compartido.addListener(_comprobanteCompartido);
    WidgetsBinding.instance.addPostFrameCallback((_) => _comprobanteCompartido());
  }

  @override
  void dispose() {
    ComprobanteService.compartido.removeListener(_comprobanteCompartido);
    super.dispose();
  }

  /// Un comprobante compartido se abre según las áreas de la persona (General Manager, 7 nov 2026): con
  /// Comercialización, los pedidos por cobrar; con Finanzas (dueños), lo que está por pagar; con las dos, se pregunta.
  Future<void> _comprobanteCompartido() async {
    final ruta = ComprobanteService.compartido.value;
    if (ruta == null || !mounted) return;
    ComprobanteService.compartido.value = null;
    final destino = await _destinoComprobante();
    if (!mounted) return;
    if (destino == null) {
      ComprobanteService.borrarTemporal(ruta);
      return;
    }
    setState(() => _currentIndex = destino == 'finanzas' ? 3 : 0);
    if (destino == 'finanzas') {
      await pagarConComprobante(context, ruta);
    } else {
      await Navigator.of(context).push(CupertinoPageRoute(builder: (_) => ElegirPedidoComprobanteScreen(imagen: ruta)));
    }
  }

  /// 'pedidos', 'finanzas', o null si la persona cerró la pregunta.
  Future<String?> _destinoComprobante() async {
    final prefs = await SharedPreferences.getInstance();
    final dueno = prefs.getString('business_role') == 'owner';
    var areas = (prefs.getStringList(claveAreasElegidas) ?? const <String>[]).toSet();
    if (areas.isEmpty) {
      // Sin "Mis áreas" elegidas en Perfil: las áreas de la persona, como las muestra Perfil.
      final r = await AdministracionService.miArea();
      final todas = r.isSuccess ? ((r.data!['areas'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList() : <Map<String, dynamic>>[];
      final mias = todas.where((a) => a['role'] == 'lead' || a['role'] == 'member').toList();
      areas = (mias.isNotEmpty ? mias : todas).map((a) => '${a['area']}').toSet();
    }
    final finanzas = dueno && areas.contains('finance');
    final comercial = areas.contains('commercial');
    if (!finanzas) return 'pedidos';
    if (!comercial) return 'finanzas';
    if (!mounted) return null;
    return showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const ListTile(title: Text('¿Qué comprobante es?', style: TextStyle(fontWeight: FontWeight.w600))),
          ListTile(
            leading: const Icon(Icons.shopping_bag_outlined),
            title: const Text('Un cobro de un pedido'),
            subtitle: const Text('Comercialización · pedidos por cobrar'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.pop(ctx, 'pedidos'),
          ),
          ListTile(
            leading: const Icon(Icons.payments_outlined),
            title: const Text('Un pago que hicimos'),
            subtitle: const Text('Finanzas · lo que está por pagar'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.pop(ctx, 'finanzas'),
          ),
        ]),
      ),
    );
  }

  Future<void> _initializeServices() async {
    // Re-enviar token FCM después del login
    try {
      debugPrint('🔄 Re-enviando token FCM después del login...');
      final notifService = NotificationService();
      await notifService.resendTokenAfterLogin();
      // Navigate to Pedidos tab when a new order notification is tapped or received
      notifService.onNuevoPedido = () {
        if (mounted) setState(() => _currentIndex = 0);
      };
    } catch (e) {
      debugPrint('⚠️ Error re-enviando token: $e');
    }
  }

  bool _isOwner = false;
  bool _isPlatformAdmin = false;

  Future<void> _loadRole() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _isOwner = prefs.getString('business_role') == 'owner';
        _isPlatformAdmin = prefs.getBool('is_platform_admin') ?? false;
      });
    }
  }

  /// "Mis negocios": switch business or ask to join / register another one.
  Future<void> _openBusinesses() async {
    try {
      final session = await runWithFincasLoader(context, 'Cargando tus negocios...', AuthService.fetchSession);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => BusinessesScreen(
            session: session,
            currentBusinessId: widget.businessId,
            onSelect: (screenContext, business, s) async {
              if (business['businessId'] == widget.businessId) {
                Navigator.of(screenContext).pop();
                return;
              }
              await SessionStore.activateBusiness(business, isPlatformAdmin: s.isAdmin);
              if (!screenContext.mounted) return;
              Navigator.of(screenContext).pushAndRemoveUntil(
                MaterialPageRoute(
                  builder: (_) => MainScreen(businessId: business['businessId'], businessName: business['name']),
                ),
                (route) => false,
              );
            },
          ),
        ),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No se pudo cargar tus negocios. Revisa tu internet.')));
      }
    }
  }

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Cerrar sesión'),
        content: const Text('¿Deseas salir de tu cuenta?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Salir'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await AuthService.signOut();
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
      // clear() también borra la marca de instalación; se vuelve a poner para no repetir el cierre.
      await prefs.setBool('install_marker_v1', true);

      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
        );
      }
    }
  }

  String _getTitle() {
    switch (_currentIndex) {
      case 0:
        return 'Pedidos';
      case 1:
        return 'Productos';
      case 2:
        return 'Clientes';
      case 3:
        return 'Administración'; // antes el nombre del negocio (General Manager, 5 nov 2026)
      default:
        return widget.businessName;
    }
  }

  @override
  Widget build(BuildContext context) {
    final printerProvider = context.watch<PrinterProvider>();
    
    return Theme(
      data: legacyTabsTheme(),
      child: Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: Text(
          _getTitle(),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: false,
        backgroundColor: Colors.blue.shade600,
        foregroundColor: Colors.white,
        systemOverlayStyle: SystemUiOverlayStyle.light,
        elevation: 0,
        actions: [
          // Indicador de impresora
          GestureDetector(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => SettingsScreen(businessName: widget.businessName),
              ),
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              margin: const EdgeInsets.only(right: 4),
              decoration: BoxDecoration(
                color: printerProvider.isConnected 
                    ? Colors.green.withOpacity(0.2) 
                    : Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    printerProvider.isConnected ? Icons.print : Icons.print_disabled,
                    size: 18,
                    color: printerProvider.isConnected ? Colors.green.shade100 : Colors.white70,
                  ),
                  if (printerProvider.isConnected) ...[
                    const SizedBox(width: 4),
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: Colors.green,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (value) {
              switch (value) {
                case 'settings':
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => SettingsScreen(businessName: widget.businessName),
                    ),
                  );
                  break;
                case 'businesses':
                  _openBusinesses();
                  break;
                case 'perfil':
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => PerfilScreen(businessId: widget.businessId, businessName: widget.businessName, esDueno: _isOwner),
                    ),
                  );
                  break;
                case 'invitar':
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => TeamScreen(businessId: widget.businessId, businessName: widget.businessName)),
                  );
                  break;
                case 'requests':
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const BusinessRequestsScreen()));
                  break;
                case 'logout':
                  _logout();
                  break;
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'settings',
                child: Row(
                  children: [
                    Icon(
                      Icons.settings,
                      color: Colors.blue.shade600,
                    ),
                    const SizedBox(width: 8),
                    const Text('Configuración'),
                  ],
                ),
              ),
              const PopupMenuItem(value: 'businesses', child: Text('Mis negocios')),
              // Perfil: mis áreas, Mi área y, para los dueños, Equipo.
              const PopupMenuItem(value: 'perfil', child: Text('Perfil')),
              // Atajo a Perfil → Equipo → Invitar y solicitudes (era difícil de encontrar).
              if (_isOwner) const PopupMenuItem(value: 'invitar', child: Text('Invitar persona')),
              if (_isPlatformAdmin)
                const PopupMenuItem(value: 'requests', child: Text('Solicitudes de negocios')),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'logout',
                child: Row(
                  children: [
                    Icon(Icons.logout, color: Colors.red),
                    SizedBox(width: 8),
                    Text('Cerrar sesión'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      // Las pestañas ocultas siguen vivas (no pierden lo cargado) pero sus animaciones se pausan: una animación
      // oculta haría que el teléfono redibuje la pantalla sin parar y gaste batería.
      body: IndexedStack(
        index: _currentIndex,
        children: [
          TickerMode(enabled: _currentIndex == 0, child: PedidosTab(businessName: widget.businessName)),
          TickerMode(enabled: _currentIndex == 1, child: ProductosTab(isActive: _currentIndex == 1)),
          TickerMode(enabled: _currentIndex == 2, child: const ClientesTab()),
          TickerMode(enabled: _currentIndex == 3, child: const AdministracionTab()),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 10,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildNavItem(0, Icons.shopping_cart_rounded, 'Pedidos'),
                _buildNavItem(1, Icons.inventory_2_rounded, 'Productos'),
                _buildNavItem(2, Icons.people_rounded, 'Clientes'),
                _buildNavItem(3, Icons.admin_panel_settings_rounded, 'Admin'),
              ],
            ),
          ),
        ),
      ),
    ),
    );
  }

  Widget _buildNavItem(int index, IconData icon, String label) {
    final isSelected = _currentIndex == index;
    
    return GestureDetector(
      onTap: () => setState(() => _currentIndex = index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? Colors.blue.shade50 : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: isSelected ? Colors.blue.shade600 : Colors.grey.shade500,
              size: 26,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.blue.shade600 : Colors.grey.shade500,
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
