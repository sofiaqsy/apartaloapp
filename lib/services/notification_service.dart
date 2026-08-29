import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';

/// Servicio para manejar Push Notifications con Firebase
class NotificationService {
  // Singleton
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  String? _fcmToken;

  // Getters
  String? get fcmToken => _fcmToken;

  // Callbacks para manejar notificaciones
  Function(RemoteMessage)? onMessageReceived;
  Function(RemoteMessage)? onMessageOpenedApp;
  VoidCallback? onNuevoPedido;

  /// Inicializar el servicio de notificaciones
  Future<void> initialize() async {
    try {
      debugPrint('🔔 Inicializando NotificationService...');

      // Solicitar permisos
      await _requestPermissions();

      // Obtener token FCM (con retry para iOS)
      await _getTokenWithRetry();

      // Configurar listeners
      _setupListeners();

      debugPrint('✅ NotificationService inicializado correctamente');
    } catch (e) {
      debugPrint('❌ Error inicializando NotificationService: $e');
    }
  }

  /// Solicitar permisos de notificación
  Future<void> _requestPermissions() async {
    debugPrint('📱 Solicitando permisos de notificación...');
    
    final settings = await _messaging.requestPermission(
      alert: true,
      announcement: false,
      badge: true,
      carPlay: false,
      criticalAlert: false,
      provisional: false,
      sound: true,
    );

    debugPrint('🔔 Estado de permisos: ${settings.authorizationStatus}');

    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      debugPrint('✅ ¡Notificaciones AUTORIZADAS!');
    } else if (settings.authorizationStatus == AuthorizationStatus.provisional) {
      debugPrint('⚠️ Notificaciones PROVISIONALES');
    } else if (settings.authorizationStatus == AuthorizationStatus.denied) {
      debugPrint('❌ Notificaciones DENEGADAS');
      debugPrint('💡 El usuario debe ir a Settings → Fincas → Notificaciones');
    } else {
      debugPrint('❓ Estado desconocido: ${settings.authorizationStatus}');
    }
  }

  /// Obtener token con retry (especialmente para iOS)
  Future<String?> _getTokenWithRetry() async {
    // En iOS, primero necesitamos esperar el token APNs
    if (Platform.isIOS) {
      debugPrint('🍎 iOS detectado - Esperando token APNs...');
      
      // Intentar obtener APNs token primero
      String? apnsToken;
      int retries = 0;
      const maxRetries = 10;
      
      while (apnsToken == null && retries < maxRetries) {
        try {
          apnsToken = await _messaging.getAPNSToken();
          if (apnsToken != null) {
            debugPrint('✅ APNs Token obtenido: ${apnsToken.substring(0, 20)}...');
            break;
          }
        } catch (e) {
          debugPrint('⏳ Esperando APNs token... (intento ${retries + 1}/$maxRetries)');
        }
        
        retries++;
        await Future.delayed(const Duration(seconds: 2));
      }
      
      if (apnsToken == null) {
        debugPrint('⚠️ No se pudo obtener APNs token después de $maxRetries intentos');
        debugPrint('💡 Verifica que:');
        debugPrint('   1. Tienes una APNs Key (.p8) configurada en Firebase Console');
        debugPrint('   2. El Bundle ID coincide con Firebase');
        debugPrint('   3. Estás en un dispositivo físico (no simulador)');
        debugPrint('   4. Push Notifications está habilitado en Xcode Capabilities');
        return null;
      }
    }
    
    // Ahora obtener el FCM token
    return await _getToken();
  }

  /// Obtener y guardar token FCM
  Future<String?> _getToken() async {
    try {
      debugPrint('🔑 Obteniendo token FCM...');
      
      _fcmToken = await _messaging.getToken().timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          debugPrint('⏱️ Timeout obteniendo token FCM (15 segundos)');
          return null;
        },
      );
      
      if (_fcmToken != null) {
        debugPrint('✅ FCM Token obtenido:');
        debugPrint('   ${_fcmToken!.substring(0, 50)}...');
        debugPrint('   Longitud: ${_fcmToken!.length} caracteres');

        // Guardar localmente
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('fcm_token', _fcmToken!);
        debugPrint('💾 Token guardado en SharedPreferences');

        // Enviar al backend (si el usuario está logueado)
        await _sendTokenToBackend();
      } else {
        debugPrint('❌ No se pudo obtener token FCM');
        debugPrint('💡 Verifica que:');
        debugPrint('   1. Estás en un dispositivo físico (no simulator)');
        debugPrint('   2. Tienes conexión a internet');
        debugPrint('   3. Los permisos están autorizados');
        debugPrint('   4. GoogleService-Info.plist está en ios/Runner/');
        if (Platform.isIOS) {
          debugPrint('   5. APNs Key está configurada en Firebase Console');
        }
      }

      // Escuchar cambios de token
      _messaging.onTokenRefresh.listen((newToken) {
        debugPrint('🔄 Token FCM actualizado:');
        debugPrint('   ${newToken.substring(0, 50)}...');
        _fcmToken = newToken;
        _sendTokenToBackend();
      });

      return _fcmToken;
    } catch (e, stackTrace) {
      debugPrint('❌ Error obteniendo FCM token: $e');
      debugPrint('Stack trace: $stackTrace');
      return null;
    }
  }

  /// Enviar token FCM al backend
  Future<void> _sendTokenToBackend() async {
    if (_fcmToken == null) {
      debugPrint('⚠️ No hay token FCM para enviar');
      return;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final businessId = prefs.getString('business_id');

      debugPrint('📤 Enviando token al backend...');
      debugPrint('   Business ID: $businessId');
      debugPrint('   Token: ${_fcmToken!.substring(0, 30)}...');

      if (businessId != null && businessId.isNotEmpty) {
        // Asegurar que ApiService tenga el businessId correcto
        ApiService.businessId = businessId;
        
        final result = await ApiService.registrarTokenPush(token: _fcmToken!);
        
        if (result.isSuccess) {
          debugPrint('✅ Token FCM registrado en el backend correctamente');
          debugPrint('   Business: $businessId');
        } else {
          debugPrint('❌ Error registrando token: ${result.error}');
        }
      } else {
        debugPrint('⚠️ No hay businessId, esperando login del usuario');
      }
    } catch (e) {
      debugPrint('❌ Error enviando token al backend: $e');
    }
  }

  /// Re-enviar token (llamar después del login)
  Future<void> resendTokenAfterLogin() async {
    debugPrint('🔄 Re-enviando token después del login...');
    
    // Si no tenemos token, intentar obtenerlo de nuevo
    if (_fcmToken == null) {
      debugPrint('⚠️ No hay token en memoria, intentando obtener de nuevo...');
      
      // Intentar cargar de SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      _fcmToken = prefs.getString('fcm_token');
      
      if (_fcmToken != null) {
        debugPrint('✅ Token recuperado de SharedPreferences');
      } else {
        // Intentar obtener nuevo token
        debugPrint('🔄 Intentando obtener nuevo token FCM...');
        await _getTokenWithRetry();
      }
    }
    
    // Ahora enviar al backend
    await _sendTokenToBackend();
  }

  /// Configurar listeners de notificaciones
  void _setupListeners() {
    debugPrint('👂 Configurando listeners de notificaciones...');

    // Notificación recibida mientras la app está en primer plano
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      debugPrint('');
      debugPrint('📬 ========== NOTIFICACIÓN EN FOREGROUND ==========');
      debugPrint('   Título: ${message.notification?.title}');
      debugPrint('   Cuerpo: ${message.notification?.body}');
      debugPrint('   Data: ${message.data}');
      debugPrint('================================================');
      debugPrint('');
      _handleMessage(message);
      onMessageReceived?.call(message);
    });

    // Usuario tocó la notificación y abrió la app
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      debugPrint('');
      debugPrint('👆 ========== APP ABIERTA DESDE NOTIFICACIÓN ==========');
      debugPrint('   Título: ${message.notification?.title}');
      debugPrint('   Data: ${message.data}');
      debugPrint('====================================================');
      debugPrint('');
      _handleMessageOpenedApp(message);
      onMessageOpenedApp?.call(message);
    });

    // Verificar si la app fue abierta desde una notificación (app cerrada)
    _checkInitialMessage();
  }

  /// Verificar si la app fue abierta desde una notificación
  Future<void> _checkInitialMessage() async {
    final initialMessage = await _messaging.getInitialMessage();

    if (initialMessage != null) {
      debugPrint('');
      debugPrint('🚀 ========== APP INICIADA DESDE NOTIFICACIÓN ==========');
      debugPrint('   Título: ${initialMessage.notification?.title}');
      debugPrint('   Data: ${initialMessage.data}');
      debugPrint('====================================================');
      debugPrint('');
      _handleMessageOpenedApp(initialMessage);
    }
  }

  /// Manejar notificación recibida
  void _handleMessage(RemoteMessage message) {
    final data = message.data;
    if (data['type'] == 'nuevo_pedido') {
      debugPrint('🛒 Nuevo pedido recibido');
      onNuevoPedido?.call();
    } else if (data['type'] == 'mensaje_soporte') {
      debugPrint('💬 Nuevo mensaje de soporte');
    }
  }

  /// Manejar cuando el usuario toca una notificación
  void _handleMessageOpenedApp(RemoteMessage message) {
    final data = message.data;
    if (data['type'] == 'nuevo_pedido') {
      debugPrint('➡️ Navegar a pedidos');
      onNuevoPedido?.call();
    } else if (data['type'] == 'mensaje_soporte') {
      debugPrint('➡️ Navegar a chat de soporte');
    }
  }

  /// Suscribirse a un tema (topic)
  Future<void> subscribeToTopic(String topic) async {
    try {
      await _messaging.subscribeToTopic(topic);
      debugPrint('✅ Suscrito a topic: $topic');
    } catch (e) {
      debugPrint('❌ Error suscribiendo a topic: $e');
    }
  }

  /// Desuscribirse de un tema
  Future<void> unsubscribeFromTopic(String topic) async {
    try {
      await _messaging.unsubscribeFromTopic(topic);
      debugPrint('✅ Desuscrito de topic: $topic');
    } catch (e) {
      debugPrint('❌ Error desuscribiendo de topic: $e');
    }
  }

  /// Obtener token actual (para mostrar en configuración o debug)
  Future<String?> getToken() async {
    if (_fcmToken == null) {
      // Intentar cargar de SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      _fcmToken = prefs.getString('fcm_token');
    }
    return _fcmToken;
  }

  /// Mostrar información de debug
  Future<void> printDebugInfo() async {
    debugPrint('');
    debugPrint('🔍 ========== DEBUG INFO - NOTIFICACIONES ==========');
    
    try {
      final token = await getToken();
      debugPrint('Token FCM: ${token != null ? "${token.substring(0, 50)}..." : "NO DISPONIBLE"}');
      
      final prefs = await SharedPreferences.getInstance();
      final businessId = prefs.getString('business_id');
      debugPrint('Business ID: ${businessId ?? "NO DISPONIBLE"}');
      
      final settings = await _messaging.getNotificationSettings();
      debugPrint('Permisos: ${settings.authorizationStatus}');
      debugPrint('Alert: ${settings.alert}');
      debugPrint('Badge: ${settings.badge}');
      debugPrint('Sound: ${settings.sound}');
      
      if (Platform.isIOS) {
        try {
          final apnsToken = await _messaging.getAPNSToken();
          debugPrint('APNs Token: ${apnsToken != null ? "${apnsToken.substring(0, 20)}..." : "NO DISPONIBLE"}');
        } catch (e) {
          debugPrint('APNs Token: ERROR - $e');
        }
      }
    } catch (e) {
      debugPrint('❌ Error en debug info: $e');
    }
    
    debugPrint('=================================================');
    debugPrint('');
  }
}
