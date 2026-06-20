import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/speech_service.dart';
import '../services/tts_service.dart';
import '../services/ai_assistant_service.dart';
import '../services/api_service.dart';
import '../widgets/voice_widgets.dart';
import '../widgets/ia_status_widget.dart';
import 'login_screen.dart';

class HomeScreen extends StatefulWidget {
  final String businessId;
  final String businessName;

  const HomeScreen({
    super.key,
    required this.businessId,
    required this.businessName,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final SpeechService _speechService = SpeechService();
  final TTSService _ttsService = TTSService();
  final AIAssistantService _aiService = AIAssistantService();

  bool _isListening = false;
  bool _isProcessing = false;
  String _partialText = '';
  final List<ChatMessage> _messages = [];
  ComandoResult? _pendingCommand;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    ApiService.businessId = widget.businessId;
    _initialize();
  }

  Future<void> _initialize() async {
    // Solicitar permisos
    await Permission.microphone.request();

    // Inicializar servicios en paralelo
    await Future.wait([
      _speechService.initialize(),
      _ttsService.initialize(),
      _aiService.checkConnection(), // Verificar conexión con IA
    ]);

    // Escuchar cambios de estado de la IA
    _aiService.onStatusChange = (status, message) {
      if (mounted) setState(() {});
    };

    // Mensaje de bienvenida
    _addMessage(
      '¡Hola! Bienvenido a ${widget.businessName} 👋\n\n'
      'Soy tu asistente. Puedes decirme:\n'
      '• "Mostrar productos"\n'
      '• "Registrar cliente Juan 999888777"\n'
      '• "Agregar 10 al café"\n\n'
      'Toca el micrófono para comenzar.',
      isUser: false,
    );
  }

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
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
      await prefs.remove('business_id');
      await prefs.remove('business_name');
      await prefs.remove('user_phone');

      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
        );
      }
    }
  }

  void _addMessage(String text, {required bool isUser}) {
    setState(() {
      _messages.add(ChatMessage(text: text, isUser: isUser));
    });
    // Scroll al final
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _startListening() async {
    await _ttsService.stop();

    setState(() {
      _isListening = true;
      _partialText = '';
    });

    try {
      await _speechService.startListening(
        onResult: (text) {
          final trimmedText = text.trim();
          if (trimmedText.length > 2) {
            _processVoiceCommand(trimmedText);
          } else {
            debugPrint('⚠️ Texto muy corto: "$text"');
            setState(() => _isListening = false);
          }
        },
        onPartialResult: (text) {
          setState(() => _partialText = text);
        },
        onDone: () {
          setState(() => _isListening = false);
        },
      );
    } catch (e) {
      setState(() => _isListening = false);
      _showError('Error al escuchar: $e');
    }
  }

  Future<void> _stopListening() async {
    await _speechService.stopListening();
    setState(() {
      _isListening = false;
      _partialText = '';
    });
  }

  Future<void> _processVoiceCommand(String text) async {
    if (text.isEmpty) return;

    setState(() {
      _isListening = false;
      _isProcessing = true;
      _partialText = '';
    });

    _addMessage(text, isUser: true);

    try {
      final result = await AIAssistantService.procesarComando(text);

      // Actualizar UI con el estado de la IA
      if (mounted) setState(() {});

      if (result.entendido) {
        if (result.confirmar != null) {
          _pendingCommand = result;
          _addMessage(result.confirmar!, isUser: false);
          await _ttsService.speak(result.confirmar!);
        } else {
          await _executeCommand(result);
        }
      } else {
        final mensaje = result.mensaje ?? 'No entendí. ¿Puedes repetir?';
        _addMessage(mensaje, isUser: false);
        await _ttsService.speak(_extractForSpeech(mensaje));
      }
    } catch (e) {
      _showError('Error procesando: $e');
    }

    setState(() => _isProcessing = false);
  }

  Future<void> _confirmCommand() async {
    if (_pendingCommand == null) return;

    setState(() => _isProcessing = true);
    await _executeCommand(_pendingCommand!);
    _pendingCommand = null;
    setState(() => _isProcessing = false);
  }

  void _cancelCommand() {
    _pendingCommand = null;
    _addMessage('Cancelado.', isUser: false);
    _ttsService.speak('Cancelado');
  }

  Future<void> _executeCommand(ComandoResult command) async {
    String respuesta = '';

    switch (command.accion) {
      case 'registrar_producto':
        respuesta = await _registrarProducto(command.datos);
        break;

      case 'actualizar_stock':
        respuesta = await _actualizarStock(command.datos);
        break;

      case 'registrar_cliente':
        respuesta = await _registrarCliente(command.datos);
        break;

      case 'consultar_stock':
        respuesta = await _consultarStock(command.datos);
        break;

      case 'consultar_precio':
        respuesta = await _consultarPrecio(command.datos);
        break;

      case 'listar_productos':
        respuesta = await _listarProductos();
        break;

      case 'listar_clientes':
        respuesta = await _listarClientes();
        break;

      case 'listar_pedidos':
        respuesta = await _listarPedidos();
        break;

      case 'buscar_producto':
        respuesta = await _buscarProducto(command.datos);
        break;

      case 'buscar_cliente':
        respuesta = await _buscarCliente(command.datos);
        break;

      case 'crear_pedido':
        respuesta = await _crearPedido(command.datos);
        break;

      case 'estadisticas_productos':
        respuesta = await _estadisticasProductos();
        break;

      case 'estadisticas_clientes':
        respuesta = await _estadisticasClientes();
        break;

      case 'resumen_negocio':
        respuesta = await _resumenNegocio();
        break;

      case 'saludo':
        respuesta = command.mensaje ?? '¡Hola! ¿En qué puedo ayudarte?';
        break;

      case 'despedida':
        respuesta = command.mensaje ?? '¡Hasta luego! 👋';
        break;

      case 'ayuda':
        respuesta = AIAssistantService.getMensajeAyuda();
        break;

      case 'no_entendido':
      case 'error':
        respuesta = command.mensaje ?? 'No entendí. Di "ayuda" para ver opciones.';
        break;

      default:
        respuesta = command.mensaje ?? 'Esa función aún no está lista.';
    }

    _addMessage(respuesta, isUser: false);
    await _ttsService.speak(_extractForSpeech(respuesta));
  }

  // ==================== ACCIONES ====================

  Future<String> _registrarProducto(Map<String, dynamic> datos) async {
    final nombre = datos['nombre'] as String? ?? 'Producto';
    final precio = (datos['precio'] as num?)?.toDouble() ?? 0;
    final stock = datos['stock'] as int? ?? 0;

    final codigo = 'PROD-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}';

    final result = await ApiService.crearProducto(nombre: nombre);

    if (result.isSuccess) {
      return '✅ ¡Listo! Registré:\n\n'
          '📦 $nombre\n'
          '💰 S/ ${precio.toStringAsFixed(2)}\n'
          '${stock > 0 ? '📊 Stock: $stock unidades' : ''}';
    } else {
      return '❌ No pude registrar: ${result.error}';
    }
  }

  Future<String> _actualizarStock(Map<String, dynamic> datos) async {
    final nombreProducto = datos['producto'] as String? ?? '';
    final cantidad = datos['cantidad'] as int? ?? 0;
    final operacion = datos['operacion'] as String? ?? 'agregar';

    if (nombreProducto.isEmpty) {
      return '❓ ¿De qué producto quieres actualizar el stock?';
    }

    final producto = await ApiService.buscarProducto(nombreProducto);

    if (producto == null) {
      return '❌ No encontré "$nombreProducto".\n\nDi "Mostrar productos" para ver la lista.';
    }

    final result = await ApiService.actualizarStock(
      codigo: producto['codigo'],
      cantidad: cantidad,
      operacion: operacion,
    );

    if (result.isSuccess) {
      final stockAnterior = result.data!['stockAnterior'];
      final stockNuevo = result.data!['stockNuevo'];
      final accion = operacion == 'agregar' ? 'Agregué' : 'Quité';

      return '✅ ¡Listo!\n\n'
          '📦 ${producto['nombre']}\n'
          '$accion $cantidad unidades\n'
          '📊 Stock: $stockAnterior → $stockNuevo';
    } else {
      return '❌ Error: ${result.error}';
    }
  }

  Future<String> _registrarCliente(Map<String, dynamic> datos) async {
    final nombre = datos['nombre'] as String? ?? 'Cliente';
    final whatsapp = datos['whatsapp'] as String? ?? '';
    final empresa = datos['empresa'] as String?;

    if (whatsapp.isEmpty) {
      return '❓ ¿Cuál es el número de WhatsApp de $nombre?';
    }

    final result = await ApiService.crearCliente(
      nombre: nombre,
      whatsapp: whatsapp,
      empresa: empresa,
    );

    if (result.isSuccess) {
      return '✅ ¡Listo! Registré:\n\n'
          '👤 $nombre\n'
          '📱 $whatsapp'
          '${empresa != null ? '\n🏢 $empresa' : ''}';
    } else {
      return '❌ No pude registrar: ${result.error}';
    }
  }

  Future<String> _consultarStock(Map<String, dynamic> datos) async {
    final nombreProducto = datos['producto'] as String? ?? '';

    if (nombreProducto.isEmpty) {
      return '❓ ¿De qué producto quieres saber el stock?';
    }

    final producto = await ApiService.buscarProducto(nombreProducto);

    if (producto == null) {
      return '❌ No encontré "$nombreProducto"';
    }

    final stock = producto['stock'] ?? 0;
    return '📦 ${producto['nombre']}\n\n'
        '📊 Hay $stock unidades\n'
        '💰 Precio: S/ ${producto['precio']}';
  }

  Future<String> _consultarPrecio(Map<String, dynamic> datos) async {
    final nombreProducto = datos['producto'] as String? ?? '';

    if (nombreProducto.isEmpty) {
      return '❓ ¿De qué producto quieres saber el precio?';
    }

    final producto = await ApiService.buscarProducto(nombreProducto);

    if (producto == null) {
      return '❌ No encontré "$nombreProducto"';
    }

    return '📦 ${producto['nombre']}\n💰 Precio: S/ ${producto['precio']}';
  }

  Future<String> _listarProductos() async {
    final result = await ApiService.getProductos(estado: 'ACTIVO');

    if (!result.isSuccess || result.data!.isEmpty) {
      return '📦 No hay productos registrados.\n\n'
          '💡 Di "Registrar café a 50 soles" para agregar uno.';
    }

    final productos = result.data!.take(6).toList();
    final buffer = StringBuffer('📦 Tus productos:\n\n');

    for (final p in productos) {
      final nombre = p['nombre'] ?? 'Sin nombre';
      final precio = p['precio'] ?? 0;
      final stock = p['disponible'] ?? p['stock'] ?? 0;
      buffer.writeln('• $nombre - S/$precio ($stock disp.)');
    }

    if (result.data!.length > 6) {
      buffer.writeln('\n... y ${result.data!.length - 6} más');
    }

    return buffer.toString();
  }

  Future<String> _listarClientes() async {
    final result = await ApiService.getClientes();

    if (!result.isSuccess || result.data!.isEmpty) {
      return '👥 No hay clientes registrados.\n\n'
          '💡 Di "Registrar cliente Juan 999888777"';
    }

    final clientes = result.data!.take(6).toList();
    final buffer = StringBuffer('👥 Tus clientes:\n\n');

    for (final c in clientes) {
      buffer.writeln('• ${c['nombre']} - ${c['whatsapp']}');
    }

    if (result.data!.length > 6) {
      buffer.writeln('\n... y ${result.data!.length - 6} más');
    }

    return buffer.toString();
  }

  Future<String> _listarPedidos() async {
    final result = await ApiService.getPedidos(vista: 'PENDIENTES', limite: 10);

    if (!result.isSuccess || result.data!.pedidos.isEmpty) {
      return '🛒 No hay pedidos.\n\n'
          '💡 Di "Crear pedido para Juan"';
    }

    final pedidos = result.data!.pedidos.take(5).toList();
    final buffer = StringBuffer('🛒 Pedidos (${result.data!.total} total):\n\n');

    for (final p in pedidos) {
      final cliente = p['cliente'] ?? 'Cliente';
      final estado = p['estado'] ?? '';
      final total = p['total'] ?? 0;
      buffer.writeln('• $cliente - S/$total ($estado)');
    }

    return buffer.toString();
  }

  Future<String> _buscarProducto(Map<String, dynamic> datos) async {
    final buscar = datos['buscar'] as String? ?? datos['producto'] as String? ?? '';

    if (buscar.isEmpty) {
      return '❓ ¿Qué producto buscas?';
    }

    final producto = await ApiService.buscarProducto(buscar);

    if (producto == null) {
      return '❌ No encontré "$buscar"';
    }

    return '📦 ${producto['nombre']}\n\n'
        '💰 Precio: S/ ${producto['precio']}\n'
        '📊 Stock: ${producto['stock'] ?? 0}\n'
        '🏷️ Código: ${producto['codigo']}';
  }

  Future<String> _buscarCliente(Map<String, dynamic> datos) async {
    final buscar = datos['buscar'] as String? ?? datos['nombre'] as String? ?? '';

    if (buscar.isEmpty) {
      return '❓ ¿Qué cliente buscas?';
    }

    final result = await ApiService.getClientes(buscar: buscar);

    if (!result.isSuccess || result.data!.isEmpty) {
      return '❌ No encontré "$buscar"';
    }

    final cliente = result.data!.first;
    return '👤 ${cliente['nombre']}\n\n'
        '📱 ${cliente['whatsapp']}'
        '${cliente['empresa'] != null ? '\n🏢 ${cliente['empresa']}' : ''}';
  }

  Future<String> _crearPedido(Map<String, dynamic> datos) async {
    final cliente = datos['cliente'] as String?;

    if (cliente == null || cliente.isEmpty) {
      return '❓ ¿Para qué cliente es el pedido?\n\nDi: "Crear pedido para Juan"';
    }

    return '🛒 Pedido para $cliente\n\n'
        '⏳ En desarrollo...\n\n'
        '💡 Por ahora puedes ver los pedidos existentes diciendo "Mostrar pedidos"';
  }

  Future<String> _estadisticasProductos() async {
    final result = await ApiService.getProductos();

    if (!result.isSuccess) {
      return '❌ Error al obtener datos';
    }

    final productos = result.data!;
    final total = productos.length;

    if (total == 0) {
      return '📦 No tienes productos.\n\n'
          '💡 Di "Registrar café a 50 soles"';
    }

    int stockTotal = 0;
    int sinStock = 0;

    for (final p in productos) {
      final stock = (p['stock'] ?? 0) as int;
      stockTotal += stock;
      if (stock == 0) sinStock++;
    }

    return '📦 Tienes $total productos\n\n'
        '📊 Stock total: $stockTotal unidades\n'
        '${sinStock > 0 ? '⚠️ Sin stock: $sinStock productos' : '✅ Todos tienen stock'}';
  }

  Future<String> _estadisticasClientes() async {
    final result = await ApiService.getClientes();

    if (!result.isSuccess) {
      return '❌ Error al obtener datos';
    }

    final total = result.data!.length;

    if (total == 0) {
      return '👥 No tienes clientes.\n\n'
          '💡 Di "Registrar cliente Juan 999888777"';
    }

    return '👥 Tienes $total clientes registrados';
  }

  Future<String> _resumenNegocio() async {
    final productosResult = await ApiService.getProductos();
    final clientesResult = await ApiService.getClientes();
    final pedidosResult = await ApiService.getPedidos();

    final buffer = StringBuffer('📊 Resumen del negocio:\n\n');

    if (productosResult.isSuccess) {
      final productos = productosResult.data!;
      int stockTotal = 0;
      for (final p in productos) {
        stockTotal += (p['stock'] ?? 0) as int;
      }
      buffer.writeln('📦 Productos: ${productos.length}');
      buffer.writeln('   Stock total: $stockTotal');
    }

    if (clientesResult.isSuccess) {
      buffer.writeln('👥 Clientes: ${clientesResult.data!.length}');
    }

    if (pedidosResult.isSuccess) {
      final data = pedidosResult.data!;
      buffer.writeln('🛒 Pedidos: ${data.total}');
      final pendientes = data.pedidos.where((p) => p['estado'] == 'PENDIENTE').length;
      if (pendientes > 0) {
        buffer.writeln('   ⏳ Pendientes: $pendientes');
      }
    }

    return buffer.toString();
  }

  String _extractForSpeech(String text) {
    return text
        .replaceAll(RegExp(r'[📦💰📊📈👤📱🏢📍✅❌🏷️👥🛒⚠️⏳💡•\n]+'), ' ')
        .replaceAll(RegExp(r'\*\*.*?\*\*'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.businessName,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const Text(
              'Asistente de voz',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.normal),
            ),
          ],
        ),
        backgroundColor: Colors.blue.shade600,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          // ========== INDICADOR DE IA ==========
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Center(child: IAStatusIndicator()),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (value) {
              if (value == 'logout') _logout();
              if (value == 'reconectar') _aiService.checkConnection();
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'reconectar',
                child: Row(
                  children: [
                    Icon(Icons.refresh, color: Colors.blue.shade600),
                    const SizedBox(width: 8),
                    const Text('Reconectar IA'),
                  ],
                ),
              ),
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
      body: Column(
        children: [
          // Banner de estado si hay problema
          const IAStatusBanner(),

          // Lista de mensajes
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(vertical: 16),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final message = _messages[index];
                final isLastAssistant = !message.isUser &&
                    index == _messages.length - 1 &&
                    _pendingCommand != null;

                return AssistantBubble(
                  message: message.text,
                  isUser: message.isUser,
                  onConfirm: isLastAssistant ? _confirmCommand : null,
                  onCancel: isLastAssistant ? _cancelCommand : null,
                );
              },
            ),
          ),

          // Indicador de escucha
          ListeningIndicator(
            isListening: _isListening,
            partialText: _partialText,
          ),

          // Área del botón de voz
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: Column(
              children: [
                VoiceButton(
                  isListening: _isListening,
                  isProcessing: _isProcessing,
                  onPressed: _isListening ? _stopListening : _startListening,
                ),
                const SizedBox(height: 12),
                Text(
                  _isListening
                      ? 'Te escucho...'
                      : _isProcessing
                          ? 'Pensando...'
                          : 'Toca para hablar',
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                // Tip sutil
                if (!_isListening && !_isProcessing)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      '💡 Di "ayuda" si no sabes qué decir',
                      style: TextStyle(
                        color: Colors.grey.shade400,
                        fontSize: 12,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }
}

/// Modelo de mensaje
class ChatMessage {
  final String text;
  final bool isUser;
  final DateTime timestamp;

  ChatMessage({
    required this.text,
    required this.isUser,
  }) : timestamp = DateTime.now();
}
