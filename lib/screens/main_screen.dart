import '../services/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';
import '../services/notification_service.dart';
import '../providers/printer_provider.dart';
import 'login_screen.dart';
import 'tabs/reportes_tab.dart';
import 'tabs/productos_tab.dart';
import 'tabs/clientes_tab.dart';
import 'tabs/pedidos_tab.dart';
import 'settings/settings_screen.dart';
import 'team_screen.dart';
import 'businesses_screen.dart';
import '../services/session_store.dart';
import '../widgets/fincas_widgets.dart';
import '../theme/fincas_tokens.dart';
import 'business_requests_screen.dart';

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
    _loadRole();
    _initializeServices();
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
        return widget.businessName;
      default:
        return widget.businessName;
    }
  }

  @override
  Widget build(BuildContext context) {
    final printerProvider = context.watch<PrinterProvider>();
    
    return Scaffold(
      backgroundColor: FincasColors.background,
      appBar: AppBar(
        title: Text(_getTitle(), style: FincasText.sectionTitle.copyWith(fontSize: 20)),
        centerTitle: false,
        backgroundColor: FincasColors.background,
        foregroundColor: FincasColors.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        actions: [
          // Indicador de impresora (verde cuando está conectada); el texto lo lee VoiceOver
          Semantics(
            button: true,
            label: printerProvider.isConnected ? 'Impresora conectada' : 'Impresora desconectada',
            excludeSemantics: true,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => SettingsScreen(businessName: widget.businessName),
                ),
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: printerProvider.isConnected ? FincasColors.successBg : FincasColors.sand,
                      borderRadius: BorderRadius.circular(FincasRadii.small + 2),
                    ),
                    child: Icon(
                      printerProvider.isConnected ? Icons.print : Icons.print_disabled,
                      size: 20,
                      color: printerProvider.isConnected ? FincasColors.success : FincasColors.textSecondary,
                    ),
                  ),
                ),
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
                case 'team':
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => TeamScreen(businessId: widget.businessId, businessName: widget.businessName),
                    ),
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
                      color: FincasColors.espresso,
                    ),
                    const SizedBox(width: 8),
                    const Text('Configuración'),
                  ],
                ),
              ),
              const PopupMenuItem(value: 'businesses', child: Text('Mis negocios')),
              if (_isOwner)
                const PopupMenuItem(value: 'team', child: Text('Equipo')),
              if (_isPlatformAdmin)
                const PopupMenuItem(value: 'requests', child: Text('Solicitudes de negocios')),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'logout',
                child: Row(
                  children: [
                    Icon(Icons.logout, color: FincasColors.error),
                    SizedBox(width: 8),
                    Text('Cerrar sesión'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: IndexedStack(
        index: _currentIndex,
        children: [
          PedidosTab(businessName: widget.businessName),
          ProductosTab(isActive: _currentIndex == 1),
          const ClientesTab(),
          const ReportesTab(),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: FincasColors.surface,
          border: Border(top: BorderSide(color: FincasColors.divider)),
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
                _buildNavItem(3, Icons.bar_chart_rounded, 'Reportes'),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon, String label) {
    final isSelected = _currentIndex == index;
    final color = isSelected ? FincasColors.ink : FincasColors.textSecondary;

    return Semantics(
      button: true,
      selected: isSelected,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _currentIndex = index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          constraints: const BoxConstraints(minWidth: 64, minHeight: FincasSpacing.minTouch),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: isSelected ? FincasColors.sand : Colors.transparent,
            borderRadius: BorderRadius.circular(FincasRadii.medium),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 24),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(color: color, fontSize: 12, fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
