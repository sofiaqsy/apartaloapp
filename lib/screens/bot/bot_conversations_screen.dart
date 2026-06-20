import 'package:flutter/material.dart';
import 'dart:async';
import '../../services/bot_service.dart';
import '../../models/bot_conversation.dart';
import 'bot_chat_screen.dart';

/// Pantalla de lista de conversaciones del bot WhatsApp
class BotConversationsScreen extends StatefulWidget {
  const BotConversationsScreen({super.key});

  @override
  State<BotConversationsScreen> createState() => _BotConversationsScreenState();
}

class _BotConversationsScreenState extends State<BotConversationsScreen> {
  List<BotConversation> _conversaciones = [];
  int _totalPendientes = 0;
  bool _isLoading = true;
  String? _error;
  Timer? _pollingTimer;
  bool _soloActivas = true;

  @override
  void initState() {
    super.initState();
    _cargarConversaciones();
    _iniciarPolling();
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    super.dispose();
  }

  void _iniciarPolling() {
    _pollingTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      _cargarConversaciones(showLoading: false);
    });
  }

  Future<void> _cargarConversaciones({bool showLoading = true}) async {
    if (showLoading && mounted) {
      setState(() => _isLoading = true);
    }

    final result = await BotService.getConversaciones(soloActivas: _soloActivas);

    if (mounted) {
      setState(() {
        _isLoading = false;
        if (result.success) {
          _conversaciones = result.conversaciones;
          _totalPendientes = result.pendientes;
          _error = null;
        } else {
          _error = result.error;
        }
      });
    }
  }

  Color _getEstadoColor(BotConversation conv) {
    if (conv.pendienteRespuesta) return Colors.red;
    if (conv.estado == 'ACTIVA') return Colors.green;
    if (conv.estado == 'LISTENING') return Colors.grey;
    return Colors.grey.shade400;
  }

  String _getEstadoLabel(BotConversation conv) {
    if (conv.pendienteRespuesta) return 'Pendiente';
    if (conv.estado == 'ACTIVA') return 'Solicita Asesor';
    if (conv.estado == 'LISTENING') return 'Bot Activo';
    return 'Cerrada';
  }

  IconData _getEstadoIcon(BotConversation conv) {
    if (conv.pendienteRespuesta) return Icons.notification_important;
    if (conv.estado == 'ACTIVA') return Icons.support_agent;
    if (conv.estado == 'LISTENING') return Icons.smart_toy;
    return Icons.check_circle_outline;
  }

  String _formatTime(String timestamp) {
    try {
      final date = DateTime.parse(timestamp);
      final now = DateTime.now();
      final diff = now.difference(date);

      if (diff.inMinutes < 60) {
        return '${diff.inMinutes}m';
      } else if (diff.inHours < 24) {
        return '${diff.inHours}h';
      } else if (diff.inDays < 7) {
        return '${diff.inDays}d';
      } else {
        return '${date.day}/${date.month}';
      }
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Conversaciones Bot', style: TextStyle(fontSize: 18)),
            if (_totalPendientes > 0)
              Text(
                '$_totalPendientes pendientes',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.normal),
              ),
          ],
        ),
        backgroundColor: const Color(0xFF7c3aed),
        foregroundColor: Colors.white,
        actions: [
          // Toggle solo activas
          IconButton(
            icon: Icon(_soloActivas ? Icons.filter_alt : Icons.filter_alt_off),
            tooltip: _soloActivas ? 'Mostrando activas' : 'Mostrando todas',
            onPressed: () {
              setState(() => _soloActivas = !_soloActivas);
              _cargarConversaciones();
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _cargarConversaciones(),
          ),
        ],
      ),
      body: Column(
        children: [
          // Stats bar
          Container(
            padding: const EdgeInsets.all(12),
            color: Colors.white,
            child: Row(
              children: [
                _buildStatCard(
                  'Pendientes',
                  _totalPendientes.toString(),
                  Colors.red,
                ),
                const SizedBox(width: 8),
                _buildStatCard(
                  'Activas',
                  _conversaciones.where((c) => c.isActive).length.toString(),
                  Colors.green,
                ),
                const SizedBox(width: 8),
                _buildStatCard(
                  'Hoy',
                  _conversaciones.where((c) {
                    try {
                      final date = DateTime.parse(c.ultimaAct);
                      return date.day == DateTime.now().day;
                    } catch (_) {
                      return false;
                    }
                  }).length.toString(),
                  const Color(0xFF7c3aed),
                ),
              ],
            ),
          ),
          
          // Lista de conversaciones
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.error_outline, size: 64, color: Colors.grey.shade400),
                            const SizedBox(height: 16),
                            Text(_error!, style: TextStyle(color: Colors.grey.shade600)),
                            const SizedBox(height: 16),
                            ElevatedButton(
                              onPressed: _cargarConversaciones,
                              child: const Text('Reintentar'),
                            ),
                          ],
                        ),
                      )
                    : _conversaciones.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.chat_bubble_outline, size: 64, color: Colors.grey.shade400),
                                const SizedBox(height: 16),
                                Text(
                                  'Sin conversaciones',
                                  style: TextStyle(color: Colors.grey.shade600, fontSize: 16),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Las conversaciones del bot aparecerán aquí',
                                  style: TextStyle(color: Colors.grey.shade400, fontSize: 14),
                                ),
                              ],
                            ),
                          )
                        : RefreshIndicator(
                            onRefresh: () => _cargarConversaciones(),
                            child: ListView.builder(
                              padding: const EdgeInsets.all(8),
                              itemCount: _conversaciones.length,
                              itemBuilder: (context, index) {
                                return _buildConversacionCard(_conversaciones[index]);
                              },
                            ),
                          ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey.shade600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConversacionCard(BotConversation conv) {
    final estadoColor = _getEstadoColor(conv);
    
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: conv.pendienteRespuesta
            ? BorderSide(color: Colors.red.shade300, width: 2)
            : BorderSide.none,
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => BotChatScreen(conversacion: conv),
            ),
          );
          _cargarConversaciones(showLoading: false);
        },
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border(
              left: BorderSide(color: estadoColor, width: 4),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                conv.cliente,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: estadoColor.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(_getEstadoIcon(conv), size: 12, color: estadoColor),
                                  const SizedBox(width: 4),
                                  Text(
                                    _getEstadoLabel(conv),
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: estadoColor,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (conv.mensajesSinResponder > 0) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.red,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  conv.mensajesSinResponder.toString(),
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
                        const SizedBox(height: 4),
                        Text(
                          '+${conv.whatsapp}',
                          style: TextStyle(
                            color: Colors.green.shade600,
                            fontSize: 13,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    _formatTime(conv.ultimaAct),
                    style: TextStyle(
                      color: Colors.grey.shade500,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
              if (conv.ultimoMensaje != null && conv.ultimoMensaje!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    if (conv.ultimoTipo == 'BOT')
                      const Icon(Icons.smart_toy, size: 14, color: Colors.green),
                    if (conv.ultimoTipo == 'CLIENTE')
                      const Icon(Icons.person, size: 14, color: Colors.blue),
                    if (conv.ultimoTipo == 'ASESOR')
                      const Icon(Icons.support_agent, size: 14, color: Colors.purple),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        conv.ultimoMensaje!,
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 13,
                        ),
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
      ),
    );
  }
}
