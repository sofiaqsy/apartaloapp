import 'package:flutter/material.dart';
import 'dart:async';
import '../../services/bot_service.dart';
import '../../models/bot_conversation.dart';

/// Pantalla de chat con un cliente del bot
class BotChatScreen extends StatefulWidget {
  final BotConversation conversacion;

  const BotChatScreen({super.key, required this.conversacion});

  @override
  State<BotChatScreen> createState() => _BotChatScreenState();
}

class _BotChatScreenState extends State<BotChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  
  List<BotMessage> _mensajes = [];
  final Set<String> _messageIds = {};
  bool _isLoading = true;
  bool _isSending = false;
  Timer? _pollingTimer;
  late BotConversation _conversacion;

  @override
  void initState() {
    super.initState();
    _conversacion = widget.conversacion;
    _cargarMensajes();
    _iniciarPolling();
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _iniciarPolling() {
    _pollingTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _cargarMensajes(showLoading: false);
    });
  }

  Future<void> _cargarMensajes({bool showLoading = true}) async {
    if (showLoading && mounted) {
      setState(() => _isLoading = true);
    }

    final result = await BotService.getMensajes(_conversacion.id);

    if (mounted) {
      setState(() {
        _isLoading = false;
        if (result.success) {
          // 🔥 Filtrar duplicados usando Set de IDs únicos
          final mensajesSinDuplicados = <BotMessage>[];
          _messageIds.clear();
          
          for (final msg in result.mensajes) {
            // Crear ID único: timestamp + mensaje + tipo
            final uniqueId = '${msg.timestamp}_${msg.mensaje}_${msg.remitente}';
            
            if (!_messageIds.contains(uniqueId)) {
              _messageIds.add(uniqueId);
              mensajesSinDuplicados.add(msg);
            } else {
              debugPrint('⚠️ Duplicado filtrado: ${msg.mensaje.substring(0, 20)}...');
            }
          }
          
          _mensajes = mensajesSinDuplicados;
          _mensajes.sort((a, b) => b.timestamp.compareTo(a.timestamp));
          
          debugPrint('📨 Total: ${result.mensajes.length}, Sin duplicados: ${_mensajes.length}');
        }
      });
    }
  }

  Future<void> _enviarMensaje() async {
    final mensaje = _messageController.text.trim();
    if (mensaje.isEmpty) return;

    setState(() => _isSending = true);
    _messageController.clear();

    final result = await BotService.enviarMensaje(
      conversacionId: _conversacion.id,
      mensaje: mensaje,
    );

    if (mounted) {
      setState(() => _isSending = false);

      if (result.success) {
        _cargarMensajes(showLoading: false);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.error ?? 'Error enviando mensaje'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _activarConversacion() async {
    final result = await BotService.actualizarEstado(
      conversacionId: _conversacion.id,
      estado: 'ACTIVA',
    );

    if (result.success && mounted) {
      setState(() {
        _conversacion = BotConversation(
          id: _conversacion.id,
          fechaInicio: _conversacion.fechaInicio,
          cliente: _conversacion.cliente,
          whatsapp: _conversacion.whatsapp,
          estado: 'ACTIVA',
          ultimaAct: _conversacion.ultimaAct,
          solicitaAsesor: true,
        );
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Conversación activada'), backgroundColor: Colors.green),
      );
    }
  }

  Future<void> _cerrarConversacion() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cerrar conversación'),
        content: const Text('¿Deseas cerrar esta conversación? El bot volverá a estar activo para este cliente.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final result = await BotService.actualizarEstado(
        conversacionId: _conversacion.id,
        estado: 'CERRADA',
      );

      if (result.success && mounted) {
        Navigator.pop(context);
      }
    }
  }

  String _formatTime(String timestamp) {
    try {
      final date = DateTime.parse(timestamp);
      return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return '';
    }
  }

  String _formatDate(String timestamp) {
    try {
      final date = DateTime.parse(timestamp);
      final now = DateTime.now();
      final yesterday = now.subtract(const Duration(days: 1));
      
      if (date.year == now.year && date.month == now.month && date.day == now.day) {
        return 'Hoy';
      } else if (date.year == yesterday.year && date.month == yesterday.month && date.day == yesterday.day) {
        return 'Ayer';
      }
      return '${date.day}/${date.month}/${date.year}';
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final isListening = _conversacion.estado == 'LISTENING';
    final isActive = _conversacion.estado == 'ACTIVA';
    final isClosed = _conversacion.estado == 'CERRADA';

    return Scaffold(
      backgroundColor: const Color(0xFF0f0f1a),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1a1a2e),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _conversacion.cliente,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            Text(
              '+${_conversacion.whatsapp}',
              style: TextStyle(fontSize: 12, color: Colors.green.shade400),
            ),
          ],
        ),
        actions: [
          if (isListening)
            TextButton(
              onPressed: _activarConversacion,
              child: const Text('Iniciar', style: TextStyle(color: Colors.green)),
            ),
          if (isActive)
            TextButton(
              onPressed: _cerrarConversacion,
              child: const Text('Cerrar', style: TextStyle(color: Colors.red)),
            ),
        ],
      ),
      body: Column(
        children: [
          // Mensajes
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _mensajes.isEmpty
                    ? const Center(
                        child: Text(
                          'Sin mensajes',
                          style: TextStyle(color: Colors.grey),
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(16),
                        reverse: true,
                        itemCount: _mensajes.length,
                        itemBuilder: (context, index) {
                          // Con reverse + orden desc: index 0 = más reciente (abajo)
                          final msg = _mensajes[index];
                          
                          // Mostrar fecha después del mensaje si el siguiente es de otro día
                          // (en visual: la fecha aparece arriba del grupo de mensajes de ese día)
                          final nextIndex = index + 1;
                          final showDate = nextIndex >= _mensajes.length ||
                              _formatDate(msg.timestamp) != _formatDate(_mensajes[nextIndex].timestamp);

                          return Column(
                            children: [
                              _buildMessageBubble(msg),
                              if (showDate)
                                Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 16),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF1a1a2e),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      _formatDate(msg.timestamp),
                                      style: TextStyle(
                                        color: Colors.grey.shade500,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          );
                        },
                      ),
          ),

          // Input area o notice
          if (isListening)
            Container(
              padding: const EdgeInsets.all(16),
              color: const Color(0xFF1a1a2e),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.smart_toy, color: Colors.grey),
                  SizedBox(width: 8),
                  Text(
                    'Bot activo. Presiona "Iniciar" para responder.',
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            )
          else if (isClosed)
            Container(
              padding: const EdgeInsets.all(16),
              color: const Color(0xFF1a1a2e),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.lock, color: Colors.grey),
                  SizedBox(width: 8),
                  Text(
                    'Conversación cerrada',
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            )
          else
            Container(
              padding: const EdgeInsets.all(12),
              color: const Color(0xFF1a1a2e),
              child: SafeArea(
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _messageController,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          hintText: 'Escribe un mensaje...',
                          hintStyle: TextStyle(color: Colors.grey.shade600),
                          filled: true,
                          fillColor: const Color(0xFF0d0d15),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                        ),
                        maxLines: 3,
                        minLines: 1,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _enviarMensaje(),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF7c3aed),
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: IconButton(
                        icon: _isSending
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.send, color: Colors.white),
                        onPressed: _isSending ? null : _enviarMensaje,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(BotMessage msg) {
    final isClient = msg.isFromClient;
    final isBot = msg.isFromBot;
    final isAdvisor = msg.isFromAdvisor;
    final isSystem = msg.isSystem;

    if (isSystem) {
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF1a1a2e),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey.shade800),
        ),
        child: Text(
          msg.mensaje,
          style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
          textAlign: TextAlign.center,
        ),
      );
    }

    return Align(
      alignment: isClient ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.8,
        ),
        child: Column(
          crossAxisAlignment: isClient ? CrossAxisAlignment.start : CrossAxisAlignment.end,
          children: [
            if (isBot)
              Padding(
                padding: const EdgeInsets.only(bottom: 4, right: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.smart_toy, size: 12, color: Colors.green.shade400),
                    const SizedBox(width: 4),
                    Text(
                      'Bot • AUTO',
                      style: TextStyle(fontSize: 10, color: Colors.green.shade400),
                    ),
                  ],
                ),
              ),
            if (isBot)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 3,
                    height: 40,
                    decoration: BoxDecoration(
                      color: const Color(0xFF10b981),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1a1a2e),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade800),
                      ),
                      child: Text(
                        msg.mensaje,
                        style: const TextStyle(color: Colors.white, fontSize: 14),
                      ),
                    ),
                  ),
                ],
              )
            else
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  gradient: isClient
                      ? const LinearGradient(
                          colors: [Color(0xFF7c3aed), Color(0xFF5b21b6)],
                        )
                      : null,
                  color: isAdvisor ? const Color(0xFF10b981) : const Color(0xFF1a1a2e),
                  borderRadius: BorderRadius.circular(16).copyWith(
                    bottomLeft: isClient ? const Radius.circular(4) : null,
                    bottomRight: !isClient ? const Radius.circular(4) : null,
                  ),
                ),
                child: Text(
                  msg.mensaje,
                  style: TextStyle(
                    color: isAdvisor ? Colors.black : Colors.white,
                    fontSize: 14,
                  ),
                ),
              ),
            const SizedBox(height: 4),
            Text(
              _formatTime(msg.timestamp),
              style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }
}