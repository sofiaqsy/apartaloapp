import 'package:flutter_dotenv/flutter_dotenv.dart';

class AppConfig {
  // APIs de IA
  static String get groqApiKey => dotenv.env['GROQ_API_KEY'] ?? '';
  static String get geminiApiKey => dotenv.env['GEMINI_API_KEY'] ?? '';
  
  // Backend
  static String get apiBaseUrl => dotenv.env['API_BASE_URL'] ?? 'http://localhost:3000';
  static String get businessId => dotenv.env['BUSINESS_ID'] ?? 'demo';

  // App info
  static const String appName = 'Fincas';
  static const String appVersion = '1.0.1';

  // Colores
  static const int primaryColor = 0xFF2563EB;
  static const int successColor = 0xFF10B981;
  static const int warningColor = 0xFFF59E0B;
  static const int dangerColor = 0xFFEF4444;
}
