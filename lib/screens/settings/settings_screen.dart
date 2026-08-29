import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/printer_provider.dart';
import 'printer_screen.dart';

class SettingsScreen extends StatelessWidget {
  final String businessName;
  
  const SettingsScreen({
    super.key,
    required this.businessName,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: const Text('⚙️ Configuración'),
        backgroundColor: Colors.blue.shade600,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Impresora
          _buildSettingCard(
            context,
            icon: Icons.print,
            iconColor: Colors.blue,
            title: 'Impresora',
            subtitle: context.watch<PrinterProvider>().isConnected 
                ? 'Conectada: ${context.watch<PrinterProvider>().connectedDeviceName}'
                : 'No conectada',
            trailing: Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: context.watch<PrinterProvider>().isConnected 
                    ? Colors.green 
                    : Colors.grey,
                shape: BoxShape.circle,
              ),
            ),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const PrinterScreen()),
            ),
          ),
          const SizedBox(height: 12),
          
          const SizedBox(height: 0),
          
          // Sonidos
          _buildSettingCard(
            context,
            icon: Icons.volume_up_outlined,
            iconColor: Colors.purple,
            title: 'Sonidos',
            subtitle: 'Configurar sonidos de la app',
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Próximamente')),
              );
            },
          ),
          const SizedBox(height: 12),
          
          // Acerca de
          _buildSettingCard(
            context,
            icon: Icons.info_outline,
            iconColor: Colors.teal,
            title: 'Acerca de',
            subtitle: 'Fincas v1.0.1',
            onTap: () => _showAboutDialog(context),
          ),
          
          const SizedBox(height: 32),
          
          // Logo/Branding
          Center(
            child: Column(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Image.asset(
                    'assets/splash/splash.png',
                    width: 60,
                    height: 60,
                    fit: BoxFit.cover,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  businessName,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingCard(
    BuildContext context, {
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    Widget? trailing,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: iconColor.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: iconColor, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
            trailing ?? Icon(
              Icons.chevron_right,
              color: Colors.grey.shade400,
            ),
          ],
        ),
      ),
    );
  }

  void _showAboutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.asset(
                'assets/splash/splash.png',
                width: 40,
                height: 40,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(width: 12),
            const Text('Fincas'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Versión 1.0.1',
              style: TextStyle(color: Colors.grey.shade600),
            ),
            const SizedBox(height: 16),
            const Text(
              'Sistema de gestión de inventario y pedidos.\n\n'
              '• Gestión de productos\n'
              '• Control de clientes\n'
              '• Registro de pedidos\n'
              '• Impresión de etiquetas\n'
              '• Asistente de voz con IA',
            ),
            const SizedBox(height: 16),
            Text(
              '© 2025 Fincas',
              style: TextStyle(
                color: Colors.grey.shade500,
                fontSize: 12,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }
}
