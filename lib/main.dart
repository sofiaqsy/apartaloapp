import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:http/http.dart' as http;
import 'config/app_config.dart';
import 'theme/fincas_theme.dart';
import 'services/auth_client.dart';
import 'services/auth_service.dart';
import 'firebase_options.dart';
import 'providers/printer_provider.dart';
import 'services/notification_service.dart';
import 'screens/login_screen.dart';

/// Handler para notificaciones en background
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  debugPrint('🔔 Notificación en background: ${message.messageId}');
}

Future<void> main() async {
  // Every http call made through the top-level helpers goes through AuthClient, which
  // adds the Firebase token only for our backend host.
  await http.runWithClient(
    _appMain,
    () => AuthClient(
      http.Client(),
      backendHost: () => Uri.tryParse(AppConfig.apiBaseUrl)?.host,
      getToken: AuthService.idToken,
    ),
  );
}

Future<void> _appMain() async {
  // Envolver todo en un try-catch para evitar crashes
  try {
    WidgetsFlutterBinding.ensureInitialized();

    // Inicializar Firebase
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      debugPrint('✅ Firebase inicializado');
      
      // Configurar handler de notificaciones en background
      FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
      
      // Inicializar servicio de notificaciones
      await AuthService.clearStaleSessionOnFreshInstall();
      await NotificationService().initialize();
    } catch (e) {
      debugPrint('⚠️ Error inicializando Firebase: $e');
    }

    // Cargar variables de entorno con manejo seguro
    try {
      await dotenv.load(fileName: '.env');
      debugPrint('✅ .env cargado correctamente');
    } catch (e) {
      debugPrint('⚠️ No se pudo cargar .env: $e');
      // Continuar sin el .env - los valores por defecto en AppConfig se usarán
    }

    // Configurar orientación con manejo de errores
    try {
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]);
    } catch (e) {
      debugPrint('⚠️ Error configurando orientación: $e');
    }

    // Configurar estilo de la barra de estado
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
      ),
    );

    runApp(const FincaRosalApp());
  } catch (e, stackTrace) {
    debugPrint('❌ Error fatal en main: $e');
    debugPrint('Stack trace: $stackTrace');
    // Ejecutar app de emergencia
    runApp(const EmergencyApp());
  }
}

/// App de emergencia si falla la inicialización
class EmergencyApp extends StatelessWidget {
  const EmergencyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, size: 64, color: Colors.red),
                const SizedBox(height: 16),
                const Text(
                  'Error de inicialización',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Hubo un problema al iniciar la app. Por favor, ciérrala y vuelve a abrirla.',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class FincaRosalApp extends StatelessWidget {
  const FincaRosalApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => PrinterProvider()..initialize()),
      ],
      child: MaterialApp(
        title: 'Fincas',
        debugShowCheckedModeBanner: false,
        theme: FincasTheme.light(),
        home: const LoginScreen(), // Inicia con Login
      ),
    );
  }
}
