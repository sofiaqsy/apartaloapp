import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';
import '../services/ai_assistant_service.dart';
import '../services/conversation_firestore_service.dart';
import '../services/notification_service.dart';
import '../providers/printer_provider.dart';
import '../widgets/ia_status_widget.dart';
import 'login_screen.dart';
import 'tabs/reportes_tab.dart';
import 'tabs/productos_tab.dart';
import 'tabs/clientes_tab.dart';
import 'tabs/pedidos_tab.dart';
import 'conversaciones_screen.dart';
import 'settings/settings_screen.dart';

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
  final AIAssistantService _aiService = AIAssistantService();
  final ConversationFirestoreService _conversationService = ConversationFirestoreService();
  
  // Contador de mensajes no leídos
  int _mensajesNoLeidos = 0;

  @override
  void initState() {
    super.initState();
    ApiService.businessId = widget.businessId;
    _initializeServices();
  }

  Future<void> _initializeServices() async {
    // Inicializar IA
    _initializeAI();
    
    // Cargar contador de mensajes
    _cargarContadorMensajes();
    
    // Re-enviar token FCM después del login
    try {
      debugPrint('🔄 Re-enviando token FCM después del login...');
      await NotificationService().resendTokenAfterLogin();
    } catch (e) {
      debugPrint('⚠️ Error re-enviando token: $e');
    }
  }

  Future<void> _initializeAI() async {
    await _aiService.checkConnection();
    _aiService.onStatusChange = (status, message) {
      if (mounted) setState(() {});
    };
  }

  Future<void> _cargarContadorMensajes() async {
    try {
      final count = await _conversationService.contarMensajesNoLeidos(widget.businessId);
      if (mounted) {
        setState(() => _mensajesNoLeidos = count);
      }
    } catch (e) {
      debugPrint('Error cargando contador: $e');
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
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();

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
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: Text(
          _getTitle(),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: false,
        backgroundColor: Colors.blue.shade600,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          // Botón de conversaciones con badge
          Stack(
            children: [
              IconButton(
                icon: const Icon(Icons.chat_bubble_outline),
                onPressed: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ConversacionesScreen(businessId: widget.businessId),
                    ),
                  );
                  // Recargar contador al volver
                  _cargarContadorMensajes();
                },
              ),
              if (_mensajesNoLeidos > 0)
                Positioned(
                  right: 6,
                  top: 6,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                    constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                    child: Text(
                      _mensajesNoLeidos > 99 ? '99+' : '$_mensajesNoLeidos',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
            ],
          ),
          
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
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Center(child: IAStatusIndicator()),
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
                case 'reconectar':
                  _aiService.checkConnection();
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
              const PopupMenuItem(
                value: 'reconectar',
                child: Row(
                  children: [
                    Icon(Icons.refresh, color: Colors.blue),
                    SizedBox(width: 8),
                    Text('Reconectar IA'),
                  ],
                ),
              ),
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
