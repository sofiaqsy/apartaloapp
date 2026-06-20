import 'package:flutter/material.dart';
import '../services/ai_assistant_service.dart';

/// Widget que muestra el estado de conexión con la IA
class IAStatusIndicator extends StatefulWidget {
  final bool showDetails;
  final VoidCallback? onTap;

  const IAStatusIndicator({
    super.key,
    this.showDetails = false,
    this.onTap,
  });

  @override
  State<IAStatusIndicator> createState() => _IAStatusIndicatorState();
}

class _IAStatusIndicatorState extends State<IAStatusIndicator> {
  final AIAssistantService _aiService = AIAssistantService();

  @override
  void initState() {
    super.initState();
    _aiService.onStatusChange = (status, message) {
      if (mounted) setState(() {});
    };
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap ?? () => _showStatusDialog(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: _getBackgroundColor(),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _getBorderColor(), width: 1.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildStatusIcon(),
            const SizedBox(width: 5),
            Text(
              _getStatusText(),
              style: TextStyle(
                color: _getTextColor(),
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusIcon() {
    switch (_aiService.status) {
      case IAStatus.checking:
        return SizedBox(
          width: 12,
          height: 12,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation(_getTextColor()),
          ),
        );
      case IAStatus.connected:
        return Icon(Icons.check_circle, size: 14, color: _getTextColor());
      case IAStatus.disconnected:
      case IAStatus.quotaExceeded:
        return Icon(Icons.error, size: 14, color: _getTextColor());
      case IAStatus.noApiKey:
        return Icon(Icons.warning, size: 14, color: _getTextColor());
    }
  }

  Color _getBackgroundColor() {
    switch (_aiService.status) {
      case IAStatus.checking:
        return Colors.blue.shade50;
      case IAStatus.connected:
        return Colors.green.shade50;
      case IAStatus.disconnected:
      case IAStatus.quotaExceeded:
        return Colors.red.shade50;
      case IAStatus.noApiKey:
        return Colors.orange.shade50;
    }
  }

  Color _getBorderColor() {
    switch (_aiService.status) {
      case IAStatus.checking:
        return Colors.blue.shade200;
      case IAStatus.connected:
        return Colors.green.shade300;
      case IAStatus.disconnected:
      case IAStatus.quotaExceeded:
        return Colors.red.shade300;
      case IAStatus.noApiKey:
        return Colors.orange.shade300;
    }
  }

  Color _getTextColor() {
    switch (_aiService.status) {
      case IAStatus.checking:
        return Colors.blue.shade700;
      case IAStatus.connected:
        return Colors.green.shade700;
      case IAStatus.disconnected:
      case IAStatus.quotaExceeded:
        return Colors.red.shade700;
      case IAStatus.noApiKey:
        return Colors.orange.shade700;
    }
  }

  String _getStatusText() {
    switch (_aiService.status) {
      case IAStatus.checking:
        return 'Conectando...';
      case IAStatus.connected:
        return 'IA OK';
      case IAStatus.disconnected:
        return 'Sin IA';
      case IAStatus.quotaExceeded:
        return 'Cuota agotada';
      case IAStatus.noApiKey:
        return 'Sin API Key';
    }
  }

  void _showStatusDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            _buildStatusIcon(),
            const SizedBox(width: 8),
            const Text('Estado de la IA', style: TextStyle(fontSize: 18)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildInfoRow('Estado:', _getFullStatusText()),
            const SizedBox(height: 8),
            _buildInfoRow('Proveedor:', _aiService.proveedorActual.toUpperCase()),
            const SizedBox(height: 8),
            _buildInfoRow('Mensaje:', _aiService.statusMessage),
            const SizedBox(height: 12),
            const Divider(),
            const SizedBox(height: 8),
            _buildInfoRow('✓ Exitosas:', '${_aiService.successfulCalls}'),
            _buildInfoRow('✗ Fallidas:', '${_aiService.failedCalls}'),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _aiService.status == IAStatus.connected
                    ? Colors.green.shade50
                    : Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    _aiService.status == IAStatus.connected
                        ? Icons.check_circle
                        : Icons.info,
                    color: _aiService.status == IAStatus.connected
                        ? Colors.green.shade700
                        : Colors.orange.shade700,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _aiService.status == IAStatus.connected
                          ? 'Todo funcionando correctamente'
                          : 'Funcionando en modo local',
                      style: TextStyle(
                        color: _aiService.status == IAStatus.connected
                            ? Colors.green.shade700
                            : Colors.orange.shade700,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cerrar'),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Reconectar'),
            onPressed: () async {
              Navigator.pop(context);
              await _aiService.checkConnection();
              if (mounted) setState(() {});
            },
          ),
        ],
      ),
    );
  }

  String _getFullStatusText() {
    switch (_aiService.status) {
      case IAStatus.checking:
        return 'Verificando...';
      case IAStatus.connected:
        return 'Conectado ✓';
      case IAStatus.disconnected:
        return 'Desconectado';
      case IAStatus.quotaExceeded:
        return 'Cuota excedida';
      case IAStatus.noApiKey:
        return 'Sin configurar';
    }
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

/// Banner de alerta cuando hay problemas
class IAStatusBanner extends StatefulWidget {
  const IAStatusBanner({super.key});

  @override
  State<IAStatusBanner> createState() => _IAStatusBannerState();
}

class _IAStatusBannerState extends State<IAStatusBanner> {
  final AIAssistantService _aiService = AIAssistantService();

  @override
  void initState() {
    super.initState();
    _aiService.onStatusChange = (status, message) {
      if (mounted) setState(() {});
    };
  }

  @override
  Widget build(BuildContext context) {
    // Solo mostrar si hay problema
    if (_aiService.status == IAStatus.connected || 
        _aiService.status == IAStatus.checking) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.offline_bolt, color: Colors.orange.shade700, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Modo local activado',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.orange.shade800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'La app funciona, pero con menos inteligencia',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.orange.shade700,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () async {
              await _aiService.checkConnection();
              if (mounted) setState(() {});
            },
            child: const Text('Reintentar'),
          ),
        ],
      ),
    );
  }
}
