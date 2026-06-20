import 'package:flutter/material.dart';
import '../../services/bot_service.dart';
import '../../models/bot_conversation.dart';
import '../bot/bot_chat_screen.dart';

/// Widget para mostrar el historial de conversación del bot de un cliente
/// Se puede usar dentro de una pantalla de detalle de cliente
class ClienteBotHistoryWidget extends StatefulWidget {
  final String whatsapp;
  final String? nombreCliente;
  final bool expandido;

  const ClienteBotHistoryWidget({
    super.key,
    required this.whatsapp,
    this.nombreCliente,
    this.expandido = false,
  });

  @override
  State<ClienteBotHistoryWidget> createState() => _ClienteBotHistoryWidgetState();
}

class _ClienteBotHistoryWidgetState extends State<ClienteBotHistoryWidget> {
  BotConversation? _conversacion;
  List<BotMessage> _mensajes = [];
  bool _isLoading = true;
  bool _existe = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargarDatos();
  }

  Future<void> _cargarDatos() async {
    setState(() => _isLoading = true);

    final result = await BotService.getConversacionCliente(widget.whatsapp);

    if (mounted) {
      setState(() {
        _isLoading = false;
        _existe = result.existe;
        _conversacion = result.conversacion;
        _mensajes = result.mensajes;
        _error = result.error;
      });
    }
  }

  String _formatTime(String timestamp) {
    try {
      final date = DateTime.parse(timestamp);
      return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')} - ${date.day}/${date.month}';
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, color: Colors.grey.shade400, size: 48),
            const SizedBox(height: 16),
            Text(_error!, style: TextStyle(color: Colors.grey.shade600)),
            TextButton(
              onPressed: _cargarDatos,
              child: const Text('Reintentar'),
            ),
          ],
        ),
      );
    }

    if (!_existe || _conversacion == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.smart_toy_outlined, color: Colors.grey.shade400, size: 48),
            const SizedBox(height: 16),
            Text(
              'Sin interacciones con el bot',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(
              'El cliente no ha interactuado con el bot de WhatsApp',
              style: TextStyle(color: Colors.grey.shade400, fontSize: 14),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        // Header con estado
        _buildHeader(),
        
        // Lista de mensajes
        Expanded(
          child: _mensajes.isEmpty
              ? const Center(child: Text('Sin mensajes', style: TextStyle(color: Colors.grey)))
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _mensajes.length,
                  itemBuilder: (context, index) => _buildMessageItem(_mensajes[index]),
                ),
        ),
      ],
    );
  }

  Widget _buildHeader() {
    final conv = _conversacion!;
    final color = conv.estado == 'ACTIVA'
        ? Colors.green
        : conv.estado == 'LISTENING'
            ? Colors.blue
            : Colors.grey;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        border: Border(bottom: BorderSide(color: color.withOpacity(0.3))),
      ),
      child: Row(
        children: [
          Icon(
            conv.estado == 'ACTIVA'
                ? Icons.support_agent
                : conv.estado == 'LISTENING'
                    ? Icons.smart_toy
                    : Icons.check_circle_outline,
            color: color,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  conv.estado == 'ACTIVA'
                      ? 'Solicita Asesor'
                      : conv.estado == 'LISTENING'
                          ? 'Bot Activo'
                          : 'Conversación Cerrada',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
                Text(
                  '${_mensajes.length} mensajes • Última act: ${_formatTime(conv.ultimaAct)}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => BotChatScreen(conversacion: conv),
                ),
              ).then((_) => _cargarDatos());
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: color,
              foregroundColor: Colors.white,
            ),
            child: const Text('Ver Chat'),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageItem(BotMessage msg) {
    final isClient = msg.isFromClient;
    final isBot = msg.isFromBot;
    final isSystem = msg.isSystem;

    if (isSystem) {
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.grey.shade200,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          msg.mensaje,
          style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
          textAlign: TextAlign.center,
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: isClient ? MainAxisAlignment.start : MainAxisAlignment.end,
        children: [
          if (isClient) ...[
            CircleAvatar(
              radius: 14,
              backgroundColor: Colors.blue.shade100,
              child: Icon(Icons.person, size: 16, color: Colors.blue.shade700),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isClient
                    ? Colors.blue.shade50
                    : isBot
                        ? Colors.green.shade50
                        : Colors.purple.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isClient
                      ? Colors.blue.shade200
                      : isBot
                          ? Colors.green.shade200
                          : Colors.purple.shade200,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (isBot)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.smart_toy, size: 12, color: Colors.green.shade700),
                        const SizedBox(width: 4),
                        Text(
                          'Bot',
                          style: TextStyle(fontSize: 10, color: Colors.green.shade700, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  Text(
                    msg.mensaje,
                    style: const TextStyle(fontSize: 14),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _formatTime(msg.timestamp),
                    style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
                  ),
                ],
              ),
            ),
          ),
          if (!isClient) ...[
            const SizedBox(width: 8),
            CircleAvatar(
              radius: 14,
              backgroundColor: isBot ? Colors.green.shade100 : Colors.purple.shade100,
              child: Icon(
                isBot ? Icons.smart_toy : Icons.support_agent,
                size: 16,
                color: isBot ? Colors.green.shade700 : Colors.purple.shade700,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Badge indicador de que el cliente solicita asesor
/// Se puede usar en listas de clientes
class ClienteSolicitaAsesorBadge extends StatefulWidget {
  final String whatsapp;
  final Widget? child;

  const ClienteSolicitaAsesorBadge({
    super.key,
    required this.whatsapp,
    this.child,
  });

  @override
  State<ClienteSolicitaAsesorBadge> createState() => _ClienteSolicitaAsesorBadgeState();
}

class _ClienteSolicitaAsesorBadgeState extends State<ClienteSolicitaAsesorBadge> {
  bool _solicitaAsesor = false;

  @override
  void initState() {
    super.initState();
    _verificar();
  }

  Future<void> _verificar() async {
    final resultado = await BotService.clienteSolicitaAsesor(widget.whatsapp);
    if (mounted) {
      setState(() => _solicitaAsesor = resultado);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_solicitaAsesor) {
      return widget.child ?? const SizedBox.shrink();
    }

    return Stack(
      children: [
        if (widget.child != null) widget.child!,
        Positioned(
          right: 0,
          top: 0,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.red,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.support_agent, size: 10, color: Colors.white),
                SizedBox(width: 2),
                Text(
                  'Asesor',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Indicador simple de punto rojo para cliente que solicita asesor
class ClientePendienteDot extends StatefulWidget {
  final String whatsapp;
  final double size;

  const ClientePendienteDot({
    super.key,
    required this.whatsapp,
    this.size = 10,
  });

  @override
  State<ClientePendienteDot> createState() => _ClientePendienteDotState();
}

class _ClientePendienteDotState extends State<ClientePendienteDot> {
  bool _solicitaAsesor = false;

  @override
  void initState() {
    super.initState();
    _verificar();
  }

  Future<void> _verificar() async {
    final resultado = await BotService.clienteSolicitaAsesor(widget.whatsapp);
    if (mounted) {
      setState(() => _solicitaAsesor = resultado);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_solicitaAsesor) return const SizedBox.shrink();

    return Container(
      width: widget.size,
      height: widget.size,
      decoration: const BoxDecoration(
        color: Colors.red,
        shape: BoxShape.circle,
      ),
    );
  }
}
