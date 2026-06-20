import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';

/// Estado de conexión con la IA
enum IAStatus {
  checking,
  connected,
  disconnected,
  noApiKey,
  quotaExceeded,
}

/// Resultado del procesamiento de un comando de voz
class ComandoResult {
  final String accion;
  final bool entendido;
  final Map<String, dynamic> datos;
  final String? confirmar;
  final String? mensaje;
  final String origen;

  ComandoResult({
    required this.accion,
    required this.entendido,
    this.datos = const {},
    this.confirmar,
    this.mensaje,
    this.origen = 'groq',
  });

  factory ComandoResult.fromJson(Map<String, dynamic> json) {
    return ComandoResult(
      accion: json['accion'] ?? 'error',
      entendido: json['entendido'] ?? false,
      datos: Map<String, dynamic>.from(json['datos'] ?? {}),
      confirmar: json['confirmar'],
      mensaje: json['mensaje'],
      origen: json['origen'] ?? 'groq',
    );
  }

  factory ComandoResult.error(String mensaje) {
    return ComandoResult(
      accion: 'error',
      entendido: false,
      mensaje: mensaje,
    );
  }
}

/// Servicio de IA para procesar comandos de voz - Usando GROQ
class AIAssistantService {
  // Singleton
  static final AIAssistantService _instance = AIAssistantService._internal();
  factory AIAssistantService() => _instance;
  AIAssistantService._internal();

  // Estado
  IAStatus _status = IAStatus.checking;
  String _statusMessage = 'Verificando conexión...';
  String _proveedorActual = 'groq';
  int _successfulCalls = 0;
  int _failedCalls = 0;

  // Getters
  IAStatus get status => _status;
  String get statusMessage => _statusMessage;
  String get proveedorActual => _proveedorActual;
  bool get isConnected => _status == IAStatus.connected;
  int get successfulCalls => _successfulCalls;
  int get failedCalls => _failedCalls;

  // Callback para notificar cambios
  Function(IAStatus, String)? onStatusChange;

  // URLs de las APIs
  static const String _groqUrl = 'https://api.groq.com/openai/v1/chat/completions';
  static const String _geminiUrl = 'https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent';

  // Prompt optimizado para entender español peruano
  static const String _systemPrompt = '''
Eres un asistente de inventario para tiendas pequeñas en Perú. 
Debes entender español coloquial peruano: "ponle", "dame", "quiero", "pe", "lucas"=soles.

ACCIONES DISPONIBLES (responde SOLO en JSON válido):

PRODUCTOS:
- registrar_producto: crear producto {nombre, precio, stock?}
- actualizar_stock: modificar cantidad {producto, cantidad, operacion:"agregar"|"restar"}
- consultar_stock: ver cantidad {producto}
- consultar_precio: ver precio {producto}
- listar_productos: mostrar todos {}
- buscar_producto: buscar uno {buscar}

CLIENTES:
- registrar_cliente: crear cliente {nombre, whatsapp}
- listar_clientes: mostrar todos {}
- buscar_cliente: buscar uno {buscar}

PEDIDOS:
- crear_pedido: nuevo pedido {cliente}
- listar_pedidos: ver pedidos {}

OTROS:
- estadisticas_productos: contar productos {}
- estadisticas_clientes: contar clientes {}
- resumen_negocio: resumen general {}
- saludo: cuando saludan {}
- despedida: cuando se despiden {}
- ayuda: cuando piden ayuda {}

FORMATO DE RESPUESTA (SIEMPRE JSON, nada más):
{"accion":"nombre","entendido":true,"datos":{...},"confirmar":"pregunta?","mensaje":"texto"}

EJEMPLOS:
"ponle café a 50 soles" → {"accion":"registrar_producto","entendido":true,"datos":{"nombre":"Café","precio":50},"confirmar":"¿Registro Café a S/50?"}
"agrega 20 al café" → {"accion":"actualizar_stock","entendido":true,"datos":{"producto":"café","cantidad":20,"operacion":"agregar"},"confirmar":"¿Agrego 20 al café?"}
"cuánto hay de arroz" → {"accion":"consultar_stock","entendido":true,"datos":{"producto":"arroz"}}
"mis productos" → {"accion":"listar_productos","entendido":true,"datos":{}}
"cliente Juan 999888777" → {"accion":"registrar_cliente","entendido":true,"datos":{"nombre":"Juan","whatsapp":"51999888777"},"confirmar":"¿Registro a Juan?"}
"hola" → {"accion":"saludo","entendido":true,"datos":{},"mensaje":"¡Hola! ¿En qué te ayudo?"}

REGLAS:
- Teléfonos de 9 dígitos: agrega 51 al inicio
- Capitaliza nombres propios
- "soles", "sol", "s/", "lucas" = moneda peruana
- Si no entiendes: {"accion":"no_entendido","entendido":false,"mensaje":"No entendí. ¿Puedes repetir?"}
''';

  /// Verificar conexión con la IA
  Future<bool> checkConnection() async {
    _updateStatus(IAStatus.checking, 'Verificando conexión...');

    // Primero intentar con Groq
    if (await _testGroq()) {
      _proveedorActual = 'groq';
      _updateStatus(IAStatus.connected, 'Conectado a Groq ✓');
      return true;
    }

    // Si Groq falla, intentar Gemini
    if (await _testGemini()) {
      _proveedorActual = 'gemini';
      _updateStatus(IAStatus.connected, 'Conectado a Gemini ✓');
      return true;
    }

    _updateStatus(IAStatus.disconnected, 'Sin conexión a IA. Usando modo local.');
    return false;
  }

  Future<bool> _testGroq() async {
    final apiKey = AppConfig.groqApiKey;
    if (apiKey.isEmpty) return false;

    try {
      final response = await http.post(
        Uri.parse(_groqUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $apiKey',
        },
        body: jsonEncode({
          'model': 'llama-3.3-70b-versatile',
          'messages': [
            {'role': 'user', 'content': 'Di solo OK'}
          ],
          'max_tokens': 5,
          'temperature': 0,
        }),
      ).timeout(const Duration(seconds: 10));

      debugPrint('🔍 Groq test: ${response.statusCode}');
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('❌ Groq test error: $e');
      return false;
    }
  }

  Future<bool> _testGemini() async {
    final apiKey = AppConfig.geminiApiKey;
    if (apiKey.isEmpty) return false;

    try {
      final response = await http.post(
        Uri.parse('$_geminiUrl?key=$apiKey'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'contents': [{'parts': [{'text': 'Di OK'}]}],
          'generationConfig': {'maxOutputTokens': 5},
        }),
      ).timeout(const Duration(seconds: 10));

      debugPrint('🔍 Gemini test: ${response.statusCode}');
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('❌ Gemini test error: $e');
      return false;
    }
  }

  void _updateStatus(IAStatus newStatus, String message) {
    _status = newStatus;
    _statusMessage = message;
    onStatusChange?.call(newStatus, message);
    debugPrint('🤖 IA: $newStatus - $message');
  }

  /// Procesar comando de voz
  static Future<ComandoResult> procesarComando(String comando) async {
    final instance = AIAssistantService();
    return instance._procesarComandoInterno(comando);
  }

  Future<ComandoResult> _procesarComandoInterno(String comando) async {
    if (comando.trim().isEmpty) {
      return ComandoResult.error('No escuché ningún comando');
    }

    debugPrint('🎤 Procesando: "$comando"');

    // 1. Intentar procesamiento local primero (instantáneo)
    final resultadoLocal = _procesarLocal(comando);
    if (resultadoLocal != null) {
      debugPrint('✅ Local: ${resultadoLocal.accion}');
      _successfulCalls++;
      return resultadoLocal;
    }

    // 2. Si hay conexión, usar IA
    if (_status == IAStatus.connected) {
      final resultado = _proveedorActual == 'groq'
          ? await _procesarConGroq(comando)
          : await _procesarConGemini(comando);
      
      if (resultado.entendido || resultado.accion != 'error') {
        return resultado;
      }
    }

    // 3. Fallback: procesamiento extendido local
    return _procesarExtendido(comando);
  }

  /// Procesamiento local para comandos comunes (INSTANTÁNEO)
  ComandoResult? _procesarLocal(String comando) {
    final cmd = comando.toLowerCase().trim();

    // === SALUDOS ===
    if (RegExp(r'^(hola|buenos días|buenas tardes|buenas noches|hey|qué tal|alo|aló|hi|buenas)').hasMatch(cmd)) {
      return ComandoResult(
        accion: 'saludo',
        entendido: true,
        mensaje: '¡Hola! ¿En qué te ayudo?\n\n'
            '• "Mostrar productos"\n'
            '• "Registrar cliente Juan 999888777"\n'
            '• "Agregar 10 al café"',
        origen: 'local',
      );
    }

    // === DESPEDIDAS ===
    if (RegExp(r'^(chau|adiós|adios|hasta luego|bye|nos vemos)').hasMatch(cmd) || 
        cmd.startsWith('gracias')) {
      return ComandoResult(
        accion: 'despedida',
        entendido: true,
        mensaje: '¡Hasta luego! Que te vaya bien 👋',
        origen: 'local',
      );
    }

    // === AYUDA ===
    if (_matchAny(cmd, ['ayuda', 'help', 'qué puedo', 'que puedo', 'cómo funciona', 'como funciona', 'no sé', 'no se', 'qué hago', 'que hago'])) {
      return ComandoResult(accion: 'ayuda', entendido: true, origen: 'local');
    }

    // === LISTAR PRODUCTOS ===
    if (_matchAny(cmd, ['productos', 'inventario', 'mis productos', 'ver productos', 'mostrar productos', 'dame productos', 'listar productos', 'qué tengo', 'que tengo', 'qué hay', 'que hay'])) {
      return ComandoResult(accion: 'listar_productos', entendido: true, datos: {}, origen: 'local');
    }

    // === LISTAR CLIENTES ===
    if (_matchAny(cmd, ['clientes', 'mis clientes', 'ver clientes', 'mostrar clientes', 'dame clientes', 'listar clientes'])) {
      return ComandoResult(accion: 'listar_clientes', entendido: true, datos: {}, origen: 'local');
    }

    // === LISTAR PEDIDOS ===
    if (_matchAny(cmd, ['pedidos', 'mis pedidos', 'ver pedidos', 'mostrar pedidos'])) {
      return ComandoResult(accion: 'listar_pedidos', entendido: true, datos: {}, origen: 'local');
    }

    // === ESTADÍSTICAS ===
    if (cmd.contains('cuántos productos') || cmd.contains('cuantos productos') || cmd.contains('total productos')) {
      return ComandoResult(accion: 'estadisticas_productos', entendido: true, datos: {}, origen: 'local');
    }
    if (cmd.contains('cuántos clientes') || cmd.contains('cuantos clientes') || cmd.contains('total clientes')) {
      return ComandoResult(accion: 'estadisticas_clientes', entendido: true, datos: {}, origen: 'local');
    }

    // === RESUMEN ===
    if (_matchAny(cmd, ['resumen', 'cómo va', 'como va', 'estado', 'cómo está el negocio', 'como esta el negocio'])) {
      return ComandoResult(accion: 'resumen_negocio', entendido: true, datos: {}, origen: 'local');
    }

    return null;
  }

  bool _matchAny(String text, List<String> keywords) {
    for (final kw in keywords) {
      if (text.contains(kw)) return true;
    }
    return false;
  }

  /// Procesar con GROQ (Llama 3.3)
  Future<ComandoResult> _procesarConGroq(String comando) async {
    final apiKey = AppConfig.groqApiKey;
    if (apiKey.isEmpty) return _procesarExtendido(comando);

    try {
      final startTime = DateTime.now();

      final response = await http.post(
        Uri.parse(_groqUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $apiKey',
        },
        body: jsonEncode({
          'model': 'llama-3.3-70b-versatile',
          'messages': [
            {'role': 'system', 'content': _systemPrompt},
            {'role': 'user', 'content': comando},
          ],
          'max_tokens': 200,
          'temperature': 0.1,
        }),
      ).timeout(const Duration(seconds: 15));

      final elapsed = DateTime.now().difference(startTime).inMilliseconds;
      debugPrint('📡 Groq: ${response.statusCode} (${elapsed}ms)');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final text = data['choices']?[0]?['message']?['content'] ?? '';
        debugPrint('📝 Respuesta: $text');

        final jsonString = _extractJson(text);
        if (jsonString != null) {
          try {
            final resultado = jsonDecode(jsonString) as Map<String, dynamic>;
            resultado['origen'] = 'groq';
            _successfulCalls++;
            _updateStatus(IAStatus.connected, 'Groq ✓ (${elapsed}ms)');
            return ComandoResult.fromJson(resultado);
          } catch (e) {
            debugPrint('❌ Error parsing JSON: $e');
          }
        }
      } else {
        debugPrint('❌ Groq error: ${response.body}');
      }
    } catch (e) {
      debugPrint('❌ Groq exception: $e');
    }

    _failedCalls++;
    return _procesarExtendido(comando);
  }

  /// Procesar con Gemini (backup)
  Future<ComandoResult> _procesarConGemini(String comando) async {
    final apiKey = AppConfig.geminiApiKey;
    if (apiKey.isEmpty) return _procesarExtendido(comando);

    try {
      final response = await http.post(
        Uri.parse('$_geminiUrl?key=$apiKey'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'contents': [
            {'parts': [{'text': '$_systemPrompt\n\nCOMANDO: "$comando"\nJSON:'}]}
          ],
          'generationConfig': {
            'temperature': 0.1,
            'maxOutputTokens': 200,
          },
        }),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final text = data['candidates']?[0]?['content']?['parts']?[0]?['text'] ?? '';

        final jsonString = _extractJson(text);
        if (jsonString != null) {
          final resultado = jsonDecode(jsonString) as Map<String, dynamic>;
          resultado['origen'] = 'gemini';
          _successfulCalls++;
          return ComandoResult.fromJson(resultado);
        }
      }
    } catch (e) {
      debugPrint('❌ Gemini error: $e');
    }

    _failedCalls++;
    return _procesarExtendido(comando);
  }

  /// Extraer JSON de una respuesta
  String? _extractJson(String text) {
    // Limpiar markdown
    var clean = text.replaceAll(RegExp(r'```json\s*'), '').replaceAll(RegExp(r'```\s*'), '');
    
    // Buscar JSON
    final match = RegExp(r'\{[\s\S]*\}').firstMatch(clean);
    return match?.group(0);
  }

  /// Procesamiento extendido local (cuando IA no está disponible)
  ComandoResult _procesarExtendido(String comando) {
    final cmd = comando.toLowerCase().trim();

    // === REGISTRAR PRODUCTO ===
    // "registrar café a 50" / "ponle arroz a 8 soles" / "producto leche 12"
    final regProducto = RegExp(
      r'(registrar|registra|ponle|agregar|agrega|nuevo|nueva|añadir|añade|producto)\s*'
      r'(producto\s+)?'
      r'([a-záéíóúñ\s]+?)\s+'
      r'(a\s+)?'
      r'(\d+\.?\d*)\s*'
      r'(soles?|sol|lucas)?',
      caseSensitive: false,
    );
    var match = regProducto.firstMatch(cmd);
    if (match != null) {
      final nombre = _capitalizar(match.group(3)?.trim() ?? 'Producto');
      final precio = double.tryParse(match.group(5) ?? '0') ?? 0;
      if (precio > 0) {
        return ComandoResult(
          accion: 'registrar_producto',
          entendido: true,
          datos: {'nombre': nombre, 'precio': precio},
          confirmar: '¿Registro $nombre a S/$precio?',
          origen: 'extendido',
        );
      }
    }

    // === ACTUALIZAR STOCK ===
    // "agrega 20 al café" / "ponle 10 más al arroz" / "quita 5 del azúcar"
    final regStock = RegExp(
      r'(agrega|agregar|ponle|añade|añadir|suma|sumar|quita|quitar|resta|restar)\s+'
      r'(\d+)\s+'
      r'(unidades?\s+)?'
      r'(al?|del?|de|más al?|más del?)\s+'
      r'([a-záéíóúñ\s]+)',
      caseSensitive: false,
    );
    match = regStock.firstMatch(cmd);
    if (match != null) {
      final accion = match.group(1)!.toLowerCase();
      final operacion = (accion.contains('quita') || accion.contains('resta')) ? 'restar' : 'agregar';
      final cantidad = int.tryParse(match.group(2) ?? '0') ?? 0;
      final producto = match.group(5)?.trim() ?? '';
      if (cantidad > 0 && producto.isNotEmpty) {
        return ComandoResult(
          accion: 'actualizar_stock',
          entendido: true,
          datos: {'producto': producto, 'cantidad': cantidad, 'operacion': operacion},
          confirmar: operacion == 'agregar' 
              ? '¿Agrego $cantidad al $producto?' 
              : '¿Quito $cantidad del $producto?',
          origen: 'extendido',
        );
      }
    }

    // === CONSULTAR STOCK ===
    // "cuánto hay de café" / "hay arroz?" / "cuánto café tengo"
    final regStock2 = RegExp(
      r'(cuánto|cuanto|hay|stock|cantidad)\s+(hay\s+)?(de\s+)?([a-záéíóúñ\s]+?)(\?|$)',
      caseSensitive: false,
    );
    match = regStock2.firstMatch(cmd);
    if (match != null && !cmd.contains('producto') && !cmd.contains('cliente')) {
      final producto = match.group(4)?.trim().replaceAll('?', '') ?? '';
      if (producto.isNotEmpty && producto.length > 2) {
        return ComandoResult(
          accion: 'consultar_stock',
          entendido: true,
          datos: {'producto': producto},
          origen: 'extendido',
        );
      }
    }

    // === CONSULTAR PRECIO ===
    // "cuánto cuesta el café" / "precio del arroz"
    final regPrecio = RegExp(
      r'(cuánto|cuanto)\s+(cuesta|está|esta|vale)\s+(el\s+)?([a-záéíóúñ\s]+)',
      caseSensitive: false,
    );
    match = regPrecio.firstMatch(cmd);
    if (match != null) {
      final producto = match.group(4)?.trim().replaceAll('?', '') ?? '';
      return ComandoResult(
        accion: 'consultar_precio',
        entendido: true,
        datos: {'producto': producto},
        origen: 'extendido',
      );
    }

    // "precio del café"
    if (cmd.contains('precio')) {
      final regPrecio2 = RegExp(r'precio\s+(del?|de)\s+([a-záéíóúñ\s]+)', caseSensitive: false);
      match = regPrecio2.firstMatch(cmd);
      if (match != null) {
        return ComandoResult(
          accion: 'consultar_precio',
          entendido: true,
          datos: {'producto': match.group(2)?.trim() ?? ''},
          origen: 'extendido',
        );
      }
    }

    // === REGISTRAR CLIENTE ===
    // "cliente Juan 999888777" / "registrar cliente María 987654321"
    final regCliente = RegExp(
      r'(registrar|registra|cliente|nuevo cliente|anota|anotar)\s+'
      r'(cliente\s+)?'
      r'([a-záéíóúñA-ZÁÉÍÓÚÑ\s]+?)\s+'
      r'(\d{9})',
      caseSensitive: false,
    );
    match = regCliente.firstMatch(cmd);
    if (match != null) {
      final nombre = _capitalizar(match.group(3)?.trim() ?? 'Cliente');
      final telefono = match.group(4) ?? '';
      return ComandoResult(
        accion: 'registrar_cliente',
        entendido: true,
        datos: {'nombre': nombre, 'whatsapp': '51$telefono'},
        confirmar: '¿Registro a $nombre con número $telefono?',
        origen: 'extendido',
      );
    }

    // === CREAR PEDIDO ===
    // "pedido para Juan" / "hacer pedido de María"
    final regPedido = RegExp(
      r'(pedido|orden)\s+(para|de)\s+([a-záéíóúñA-ZÁÉÍÓÚÑ\s]+)',
      caseSensitive: false,
    );
    match = regPedido.firstMatch(cmd);
    if (match != null) {
      final cliente = _capitalizar(match.group(3)?.trim() ?? '');
      return ComandoResult(
        accion: 'crear_pedido',
        entendido: true,
        datos: {'cliente': cliente},
        confirmar: '¿Creo pedido para $cliente?',
        origen: 'extendido',
      );
    }

    // === BUSCAR ===
    if (cmd.contains('busca') || cmd.contains('encuentra')) {
      final texto = cmd
          .replaceAll(RegExp(r'(busca|buscar|encuentra|encontrar)\s*(a|al|el|la)?'), '')
          .trim();
      if (texto.isNotEmpty) {
        return ComandoResult(
          accion: 'buscar_producto',
          entendido: true,
          datos: {'buscar': texto},
          origen: 'extendido',
        );
      }
    }

    // === NO ENTENDIDO ===
    return _fallbackResponse(comando);
  }

  String _capitalizar(String texto) {
    if (texto.isEmpty) return texto;
    return texto.split(' ').map((word) {
      if (word.isEmpty) return word;
      return word[0].toUpperCase() + word.substring(1).toLowerCase();
    }).join(' ');
  }

  ComandoResult _fallbackResponse(String comando) {
    final cmd = comando.toLowerCase();

    if (cmd.contains('producto') || cmd.contains('registr') || cmd.contains('agreg') || cmd.contains('pon')) {
      return ComandoResult(
        accion: 'no_entendido',
        entendido: false,
        mensaje: '🤔 ¿Quieres algo con productos?\n\n'
            'Intenta:\n'
            '• "Registrar café a 50 soles"\n'
            '• "Agregar 20 al café"\n'
            '• "Mostrar productos"',
        origen: 'fallback',
      );
    }

    if (cmd.contains('cliente')) {
      return ComandoResult(
        accion: 'no_entendido',
        entendido: false,
        mensaje: '🤔 ¿Quieres algo con clientes?\n\n'
            'Intenta:\n'
            '• "Cliente Juan 999888777"\n'
            '• "Mostrar clientes"',
        origen: 'fallback',
      );
    }

    if (cmd.contains('cuánto') || cmd.contains('cuanto') || cmd.contains('precio')) {
      return ComandoResult(
        accion: 'no_entendido',
        entendido: false,
        mensaje: '🤔 ¿Precio o cantidad?\n\n'
            'Intenta:\n'
            '• "¿Cuánto cuesta el café?"\n'
            '• "¿Cuánto hay de arroz?"',
        origen: 'fallback',
      );
    }

    return ComandoResult(
      accion: 'no_entendido',
      entendido: false,
      mensaje: '🤔 No entendí "$comando"\n\n'
          '¿Qué necesitas?\n'
          '• "Productos" - ver lista\n'
          '• "Clientes" - ver lista\n'
          '• "Ayuda" - más opciones',
      origen: 'fallback',
    );
  }

  /// Mensaje de ayuda
  static String getMensajeAyuda() {
    return '''
¡Hola! Soy tu asistente. 🎤

📦 **PRODUCTOS:**
• "Registrar café a 50 soles"
• "Agregar 20 al café"
• "¿Cuánto hay de arroz?"
• "¿Cuánto cuesta el café?"
• "Mostrar productos"

👥 **CLIENTES:**
• "Cliente Juan 999888777"
• "Mostrar clientes"

🛒 **PEDIDOS:**
• "Pedido para Juan"
• "Mostrar pedidos"

📊 **RESUMEN:**
• "¿Cómo va el negocio?"
• "¿Cuántos productos tengo?"

💡 ¡Habla naturalmente, te entiendo!''';
  }
}
