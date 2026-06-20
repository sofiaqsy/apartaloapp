import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';
import '../models/bot_conversation.dart';
import 'api_service.dart';

/// Servicio para gestión de conversaciones del bot WhatsApp
class BotService {
  static String get baseUrl => AppConfig.apiBaseUrl;
  static String get businessId => ApiService.businessId;

  static Map<String, String> get headers => {
    'Content-Type': 'application/json',
  };

  // ==================== CONVERSACIONES ====================

  /// Obtener todas las conversaciones del bot
  static Future<BotConversationsResponse> getConversaciones({
    String? estado,
    bool soloActivas = false,
  }) async {
    try {
      var url = '$baseUrl/api/bot/conversaciones/$businessId';
      final params = <String>[];
      if (estado != null) params.add('estado=$estado');
      if (soloActivas) params.add('soloActivas=true');
      if (params.isNotEmpty) url += '?${params.join('&')}';

      final response = await http.get(
        Uri.parse(url),
        headers: headers,
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final conversaciones = (data['conversaciones'] as List?)
            ?.map((c) => BotConversation.fromJson(c))
            .toList() ?? [];
        
        return BotConversationsResponse(
          success: true,
          total: data['total'] ?? 0,
          pendientes: data['pendientes'] ?? 0,
          conversaciones: conversaciones,
        );
      } else {
        return BotConversationsResponse(
          success: false,
          error: 'Error obteniendo conversaciones',
        );
      }
    } catch (e) {
      return BotConversationsResponse(
        success: false,
        error: 'Error de conexión: $e',
      );
    }
  }

  /// Obtener mensajes de una conversación
  static Future<BotMessagesResponse> getMensajes(String conversacionId) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/bot/conversaciones/$businessId/$conversacionId/mensajes'),
        headers: headers,
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final mensajes = (data['mensajes'] as List?)
            ?.map((m) => BotMessage.fromJson(m))
            .toList() ?? [];
        
        return BotMessagesResponse(
          success: true,
          conversacionId: conversacionId,
          total: data['total'] ?? 0,
          mensajes: mensajes,
        );
      } else {
        return BotMessagesResponse(
          success: false,
          error: 'Error obteniendo mensajes',
        );
      }
    } catch (e) {
      return BotMessagesResponse(
        success: false,
        error: 'Error de conexión: $e',
      );
    }
  }

  /// Enviar mensaje como asesor
  static Future<ApiResult> enviarMensaje({
    required String conversacionId,
    required String mensaje,
    String? asesor,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/bot/conversaciones/$businessId/$conversacionId/enviar'),
        headers: headers,
        body: jsonEncode({
          'mensaje': mensaje,
          if (asesor != null) 'asesor': asesor,
        }),
      ).timeout(const Duration(seconds: 30));

      final data = jsonDecode(response.body);

      if (response.statusCode == 200 && data['success'] == true) {
        return ApiResult(success: true, data: data);
      } else {
        return ApiResult(success: false, error: data['error'] ?? 'Error enviando mensaje');
      }
    } catch (e) {
      return ApiResult(success: false, error: 'Error de conexión: $e');
    }
  }

  /// Actualizar estado de conversación
  static Future<ApiResult> actualizarEstado({
    required String conversacionId,
    required String estado,
  }) async {
    try {
      final response = await http.put(
        Uri.parse('$baseUrl/api/bot/conversaciones/$businessId/$conversacionId/estado'),
        headers: headers,
        body: jsonEncode({'estado': estado}),
      ).timeout(const Duration(seconds: 30));

      final data = jsonDecode(response.body);

      if (response.statusCode == 200 && data['success'] == true) {
        return ApiResult(success: true, data: data);
      } else {
        return ApiResult(success: false, error: data['error'] ?? 'Error actualizando estado');
      }
    } catch (e) {
      return ApiResult(success: false, error: 'Error de conexión: $e');
    }
  }

  // ==================== CLIENTES PENDIENTES ====================

  /// Obtener clientes que solicitan asesor
  static Future<ClientesPendientesResponse> getClientesPendientes() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/bot/clientes/$businessId/pendientes'),
        headers: headers,
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final pendientes = (data['pendientes'] as List?)
            ?.map((p) => ClientePendiente.fromJson(p))
            .toList() ?? [];
        
        return ClientesPendientesResponse(
          success: true,
          total: data['total'] ?? 0,
          pendientes: pendientes,
        );
      } else {
        return ClientesPendientesResponse(
          success: false,
          error: 'Error obteniendo clientes pendientes',
        );
      }
    } catch (e) {
      return ClientesPendientesResponse(
        success: false,
        error: 'Error de conexión: $e',
      );
    }
  }

  /// Verificar si un número de WhatsApp tiene conversación activa solicitando asesor
  static Future<bool> clienteSolicitaAsesor(String whatsapp) async {
    try {
      final result = await getClientesPendientes();
      if (!result.success) return false;
      
      final waLimpio = whatsapp.replaceAll(RegExp(r'[^0-9]'), '');
      return result.pendientes.any((p) => 
        p.whatsapp.replaceAll(RegExp(r'[^0-9]'), '') == waLimpio
      );
    } catch (_) {
      return false;
    }
  }

  // ==================== CONVERSACIÓN POR CLIENTE ====================

  /// Obtener conversación de un cliente por WhatsApp
  static Future<ClienteConversacionResponse> getConversacionCliente(String whatsapp) async {
    try {
      final waLimpio = whatsapp.replaceAll(RegExp(r'[^0-9]'), '');
      
      final response = await http.get(
        Uri.parse('$baseUrl/api/bot/cliente/$businessId/$waLimpio/conversacion'),
        headers: headers,
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        BotConversation? conversacion;
        if (data['existe'] == true && data['conversacion'] != null) {
          conversacion = BotConversation.fromJson(data['conversacion']);
        }
        
        final mensajes = (data['mensajes'] as List?)
            ?.map((m) => BotMessage.fromJson(m))
            .toList() ?? [];
        
        return ClienteConversacionResponse(
          success: true,
          existe: data['existe'] ?? false,
          conversacion: conversacion,
          mensajes: mensajes,
        );
      } else {
        return ClienteConversacionResponse(
          success: false,
          error: 'Error obteniendo conversación',
        );
      }
    } catch (e) {
      return ClienteConversacionResponse(
        success: false,
        error: 'Error de conexión: $e',
      );
    }
  }

  /// Iniciar conversación con cliente
  static Future<ApiResult> iniciarConversacion({
    required String whatsapp,
    String? cliente,
    String? mensaje,
  }) async {
    try {
      final waLimpio = whatsapp.replaceAll(RegExp(r'[^0-9]'), '');
      
      final response = await http.post(
        Uri.parse('$baseUrl/api/bot/cliente/$businessId/$waLimpio/iniciar'),
        headers: headers,
        body: jsonEncode({
          if (cliente != null) 'cliente': cliente,
          if (mensaje != null) 'mensaje': mensaje,
        }),
      ).timeout(const Duration(seconds: 30));

      final data = jsonDecode(response.body);

      if (response.statusCode == 200 && data['success'] == true) {
        return ApiResult(success: true, data: data);
      } else {
        return ApiResult(success: false, error: data['error'] ?? 'Error iniciando conversación');
      }
    } catch (e) {
      return ApiResult(success: false, error: 'Error de conexión: $e');
    }
  }
}

// ==================== RESPONSE CLASSES ====================

class BotConversationsResponse {
  final bool success;
  final int total;
  final int pendientes;
  final List<BotConversation> conversaciones;
  final String? error;

  BotConversationsResponse({
    required this.success,
    this.total = 0,
    this.pendientes = 0,
    this.conversaciones = const [],
    this.error,
  });
}

class BotMessagesResponse {
  final bool success;
  final String? conversacionId;
  final int total;
  final List<BotMessage> mensajes;
  final String? error;

  BotMessagesResponse({
    required this.success,
    this.conversacionId,
    this.total = 0,
    this.mensajes = const [],
    this.error,
  });
}

class ClientesPendientesResponse {
  final bool success;
  final int total;
  final List<ClientePendiente> pendientes;
  final String? error;

  ClientesPendientesResponse({
    required this.success,
    this.total = 0,
    this.pendientes = const [],
    this.error,
  });
}

class ClienteConversacionResponse {
  final bool success;
  final bool existe;
  final BotConversation? conversacion;
  final List<BotMessage> mensajes;
  final String? error;

  ClienteConversacionResponse({
    required this.success,
    this.existe = false,
    this.conversacion,
    this.mensajes = const [],
    this.error,
  });
}

class ApiResult {
  final bool success;
  final Map<String, dynamic>? data;
  final String? error;

  ApiResult({required this.success, this.data, this.error});
}
