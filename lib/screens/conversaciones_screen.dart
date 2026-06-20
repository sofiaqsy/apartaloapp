import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/conversation_firestore_service.dart';
import '../services/api_service.dart';

/// Pantalla de lista de conversaciones
class ConversacionesScreen extends StatefulWidget {
  final String businessId;

  const ConversacionesScreen({super.key, required this.businessId});

  @override
  State<ConversacionesScreen> createState() => _ConversacionesScreenState();
}

class _ConversacionesScreenState extends State<ConversacionesScreen> with SingleTickerProviderStateMixin {
  final ConversationFirestoreService _firestoreService = ConversationFirestoreService();
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: const Text('Conversaciones', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.blue.shade600,
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(text: 'Todas'),
            Tab(text: '🆘 Soporte'),
            Tab(text: '💬 No leídas'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildListaConversaciones(_firestoreService.getConversaciones(widget.businessId)),
          _buildListaConversaciones(_firestoreService.getConversacionesSoporte(widget.businessId)),
          _buildListaConversaciones(_firestoreService.getConversacionesNoLeidas(widget.businessId)),
        ],
      ),
    );
  }

  Widget _buildListaConversaciones(Stream<List<Conversacion>> stream) {
    return StreamBuilder<List<Conversacion>>(
      stream: stream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline, size: 48, color: Colors.red.shade300),
                const SizedBox(height: 12),
                Text('Error: ${snapshot.error}', style: TextStyle(color: Colors.grey.shade600)),
              ],
            ),
          );
        }

        final conversaciones = snapshot.data ?? [];

        if (conversaciones.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.chat_bubble_outline, size: 64, color: Colors.grey.shade300),
                const SizedBox(height: 16),
                Text('No hay conversaciones', style: TextStyle(fontSize: 18, color: Colors.grey.shade500)),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(8),
          itemCount: conversaciones.length,
          itemBuilder: (context, index) => _buildConversacionCard(conversaciones[index]),
        );
      },
    );
  }

  Widget _buildConversacionCard(Conversacion conv) {
    final tiempoTexto = conv.ultimoMensaje != null
        ? _formatearTiempo(conv.ultimoMensaje!)
        : '';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        elevation: conv.tieneNoLeidos ? 2 : 1,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _abrirChat(conv),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                // Avatar con indicador de modo
                Stack(
                  children: [
                    CircleAvatar(
                      radius: 26,
                      backgroundColor: conv.requiereAtencion 
                          ? Colors.orange.shade100 
                          : Colors.blue.shade100,
                      child: Text(
                        conv.nombre.isNotEmpty ? conv.nombre[0].toUpperCase() : '?',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: conv.requiereAtencion 
                              ? Colors.orange.shade700 
                              : Colors.blue.shade700,
                        ),
                      ),
                    ),
                    if (conv.requiereAtencion)
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            color: Colors.orange,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                          child: const Icon(Icons.support_agent, size: 12, color: Colors.white),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 14),
                
                // Contenido
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              conv.nombre,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: conv.tieneNoLeidos ? FontWeight.bold : FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            tiempoTexto,
                            style: TextStyle(
                              fontSize: 12,
                              color: conv.tieneNoLeidos ? Colors.blue.shade600 : Colors.grey.shade500,
                              fontWeight: conv.tieneNoLeidos ? FontWeight.w600 : FontWeight.normal,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          if (conv.modo == 'soporte' || conv.modo == 'ayuda')
                            Container(
                              margin: const EdgeInsets.only(right: 6),
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.orange.shade100,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                conv.modo.toUpperCase(),
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.orange.shade700,
                                ),
                              ),
                            ),
                          Expanded(
                            child: Text(
                              conv.ultimoTexto,
                              style: TextStyle(
                                fontSize: 14,
                                color: conv.tieneNoLeidos ? Colors.grey.shade800 : Colors.grey.shade600,
                                fontWeight: conv.tieneNoLeidos ? FontWeight.w500 : FontWeight.normal,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                
                // Badge no leídos
                if (conv.tieneNoLeidos)
                  Container(
                    margin: const EdgeInsets.only(left: 10),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade600,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${conv.noLeidos}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatearTiempo(DateTime fecha) {
    final ahora = DateTime.now();
    final diferencia = ahora.difference(fecha);

    if (diferencia.inMinutes < 1) return 'Ahora';
    if (diferencia.inMinutes < 60) return '${diferencia.inMinutes}m';
    if (diferencia.inHours < 24) return '${diferencia.inHours}h';
    if (diferencia.inDays < 7) return '${diferencia.inDays}d';
    
    return DateFormat('dd/MM').format(fecha);
  }

  void _abrirChat(Conversacion conv) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          businessId: widget.businessId,
          whatsapp: conv.whatsapp,
          nombre: conv.nombre,
        ),
      ),
    );
  }
}

/// Pantalla de chat individual
class ChatScreen extends StatefulWidget {
  final String businessId;
  final String whatsapp;
  final String nombre;

  const ChatScreen({
    super.key,
    required this.businessId,
    required this.whatsapp,
    required this.nombre,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final ConversationFirestoreService _firestoreService = ConversationFirestoreService();
  final TextEditingController _mensajeController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _enviando = false;
  String _modoActual = 'bot'; // bot, soporte, ayuda

  @override
  void initState() {
    super.initState();
    // Marcar como leída al abrir
    _firestoreService.marcarMensajesLeidos(widget.businessId, widget.whatsapp);
  }

  @override
  void dispose() {
    _mensajeController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFECE5DD), // Color estilo WhatsApp
      appBar: AppBar(
        backgroundColor: Colors.blue.shade600,
        foregroundColor: Colors.white,
        titleSpacing: 0,
        title: StreamBuilder<Conversacion?>(
          stream: _firestoreService.getConversacion(widget.businessId, widget.whatsapp),
          builder: (context, snapshot) {
            final conv = snapshot.data;
            if (conv != null) {
              // Actualizar modo actual
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (_modoActual != conv.modo) {
                  setState(() => _modoActual = conv.modo);
                }
              });
            }
            
            return Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: Colors.white24,
                  child: Text(
                    widget.nombre.isNotEmpty ? widget.nombre[0].toUpperCase() : '?',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.nombre,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Row(
                        children: [
                          Text(
                            widget.whatsapp,
                            style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.7)),
                          ),
                          const SizedBox(width: 8),
                          // Indicador de modo
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: _getModoColor(_modoActual).withOpacity(0.3),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(_getModoIcon(_modoActual), size: 10, color: Colors.white),
                                const SizedBox(width: 3),
                                Text(
                                  _getModoLabel(_modoActual),
                                  style: const TextStyle(fontSize: 9, color: Colors.white, fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
        actions: [
          // Menú de opciones
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (value) => _manejarAccion(value),
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'bot',
                child: Row(
                  children: [
                    Icon(Icons.smart_toy, color: _modoActual == 'bot' ? Colors.green : Colors.grey),
                    const SizedBox(width: 8),
                    const Text('🤖 Modo Bot'),
                    if (_modoActual == 'bot') ...[
                      const Spacer(),
                      const Icon(Icons.check, color: Colors.green, size: 18),
                    ],
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'soporte',
                child: Row(
                  children: [
                    Icon(Icons.support_agent, color: _modoActual == 'soporte' ? Colors.orange : Colors.grey),
                    const SizedBox(width: 8),
                    const Text('🆘 Modo Soporte'),
                    if (_modoActual == 'soporte') ...[
                      const Spacer(),
                      const Icon(Icons.check, color: Colors.orange, size: 18),
                    ],
                  ],
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'whatsapp',
                child: Row(
                  children: [
                    Icon(Icons.open_in_new, color: Colors.green),
                    SizedBox(width: 8),
                    Text('💬 Abrir WhatsApp'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // Banner de modo soporte activo
          if (_modoActual == 'soporte')
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              color: Colors.orange.shade100,
              child: Row(
                children: [
                  Icon(Icons.support_agent, color: Colors.orange.shade700, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Modo Soporte activo - Bot bloqueado',
                      style: TextStyle(color: Colors.orange.shade800, fontWeight: FontWeight.w500, fontSize: 13),
                    ),
                  ),
                  TextButton(
                    onPressed: () => _cambiarModo('bot'),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      backgroundColor: Colors.orange.shade700,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Activar Bot', style: TextStyle(fontSize: 12)),
                  ),
                ],
              ),
            ),
          
          // Lista de mensajes
          Expanded(
            child: StreamBuilder<List<Mensaje>>(
              stream: _firestoreService.getMensajes(widget.businessId, widget.whatsapp),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final mensajes = snapshot.data ?? [];

                if (mensajes.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.chat_bubble_outline, size: 48, color: Colors.grey.shade400),
                        const SizedBox(height: 12),
                        Text('No hay mensajes', style: TextStyle(color: Colors.grey.shade600)),
                      ],
                    ),
                  );
                }

                // Scroll al final cuando lleguen mensajes nuevos
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (_scrollController.hasClients) {
                    _scrollController.animateTo(
                      _scrollController.position.maxScrollExtent,
                      duration: const Duration(milliseconds: 100),
                      curve: Curves.easeOut,
                    );
                  }
                });

                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(12),
                  itemCount: mensajes.length,
                  itemBuilder: (context, index) => _buildMensaje(mensajes[index]),
                );
              },
            ),
          ),
          
          // Input de mensaje
          _buildInputMensaje(),
        ],
      ),
    );
  }

  /// Construir burbuja de mensaje con diseño específico por tipo
  Widget _buildMensaje(Mensaje mensaje) {
    final esDelCliente = mensaje.esDelCliente;
    final esDelBot = mensaje.esDelBot;
    final esDelNegocio = mensaje.esDelNegocio;
    final hora = mensaje.timestamp != null 
        ? DateFormat('HH:mm').format(mensaje.timestamp!) 
        : '';

    // CLIENTE: Izquierda con globo gris
    if (esDelCliente) {
      return Align(
        alignment: Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.75,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(16),
              topRight: Radius.circular(16),
              bottomLeft: Radius.circular(4),
              bottomRight: Radius.circular(16),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 2,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                mensaje.texto,
                style: TextStyle(fontSize: 15, color: Colors.grey.shade800),
              ),
              const SizedBox(height: 4),
              Text(
                hora,
                style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
              ),
            ],
          ),
        ),
      );
    }

    // BOT: Derecha SIN globo, texto plano con icono
    if (esDelBot) {
      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.75,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Flexible(
                    child: Text(
                      mensaje.texto,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey.shade600,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(Icons.smart_toy, size: 14, color: Colors.green.shade400),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                hora,
                style: TextStyle(fontSize: 10, color: Colors.grey.shade400),
              ),
            ],
          ),
        ),
      );
    }

    // NEGOCIO/ASESOR: Derecha CON globo verde
    if (esDelNegocio) {
      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.75,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.green.shade100,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(16),
              topRight: Radius.circular(16),
              bottomLeft: Radius.circular(16),
              bottomRight: Radius.circular(4),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 2,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // Indicador de asesor
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.support_agent, size: 12, color: Colors.green.shade700),
                    const SizedBox(width: 4),
                    Text(
                      'Tú',
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.green.shade700,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                mensaje.texto,
                style: TextStyle(fontSize: 15, color: Colors.grey.shade800),
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    hora,
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    mensaje.leido ? Icons.done_all : Icons.done,
                    size: 14,
                    color: mensaje.leido ? Colors.blue : Colors.grey.shade400,
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    // Fallback para otros tipos
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(
          mensaje.texto,
          style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  Widget _buildInputMensaje() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          children: [
            // Campo de texto
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: TextField(
                  controller: _mensajeController,
                  maxLines: 4,
                  minLines: 1,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    hintText: 'Escribe un mensaje...',
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  ),
                  onSubmitted: (_) => _enviarMensaje(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            
            // Botón enviar
            Material(
              color: Colors.blue.shade600,
              borderRadius: BorderRadius.circular(24),
              child: InkWell(
                borderRadius: BorderRadius.circular(24),
                onTap: _enviando ? null : _enviarMensaje,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  child: _enviando
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Icon(Icons.send, color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _enviarMensaje() async {
    final texto = _mensajeController.text.trim();
    if (texto.isEmpty) return;

    setState(() => _enviando = true);
    _mensajeController.clear();

    try {
      // Guardar en Firestore
      await _firestoreService.enviarMensaje(
        businessId: widget.businessId,
        whatsapp: widget.whatsapp,
        texto: texto,
        origen: 'negocio',
      );

      // Enviar por WhatsApp API
      await ApiService.enviarMensaje(
        whatsapp: widget.whatsapp,
        mensaje: texto,
      );

    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      setState(() => _enviando = false);
    }
  }

  void _manejarAccion(String accion) async {
    switch (accion) {
      case 'bot':
      case 'soporte':
        await _cambiarModo(accion);
        break;
      case 'whatsapp':
        _abrirWhatsApp();
        break;
    }
  }

  Future<void> _cambiarModo(String nuevoModo) async {
    try {
      // Actualizar en Firestore
      await _firestoreService.cambiarModo(widget.businessId, widget.whatsapp, nuevoModo);
      
      // También actualizar en el backend (para sincronizar con Sheets)
      // Esto lo manejará el backend automáticamente cuando detecte el cambio
      
      setState(() => _modoActual = nuevoModo);
      
      if (mounted) {
        final mensaje = nuevoModo == 'bot' 
            ? '🤖 Bot activado - El cliente será atendido automáticamente'
            : '🆘 Modo soporte - Bot bloqueado, responde tú';
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(mensaje),
            backgroundColor: nuevoModo == 'bot' ? Colors.green : Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _abrirWhatsApp() async {
    final url = Uri.parse('https://wa.me/${widget.whatsapp}');
    // Usar url_launcher si está disponible
    debugPrint('Abrir WhatsApp: $url');
  }

  Color _getModoColor(String modo) {
    switch (modo) {
      case 'soporte':
      case 'ayuda':
        return Colors.orange;
      case 'bot':
      default:
        return Colors.green;
    }
  }

  IconData _getModoIcon(String modo) {
    switch (modo) {
      case 'soporte':
      case 'ayuda':
        return Icons.support_agent;
      case 'bot':
      default:
        return Icons.smart_toy;
    }
  }

  String _getModoLabel(String modo) {
    switch (modo) {
      case 'soporte':
        return 'SOPORTE';
      case 'ayuda':
        return 'AYUDA';
      case 'bot':
      default:
        return 'BOT';
    }
  }
}
