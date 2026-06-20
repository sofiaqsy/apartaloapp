import 'package:flutter_tts/flutter_tts.dart';

/// Servicio para síntesis de voz (Text-to-Speech)
class TTSService {
  final FlutterTts _tts = FlutterTts();
  bool _isInitialized = false;
  bool _isSpeaking = false;

  bool get isSpeaking => _isSpeaking;

  /// Inicializar el servicio TTS
  Future<bool> initialize() async {
    if (_isInitialized) return true;

    try {
      // Configurar idioma español
      await _tts.setLanguage('es-ES');
      
      // Configurar velocidad y tono
      await _tts.setSpeechRate(0.5); // 0.0 - 1.0
      await _tts.setPitch(1.0); // 0.5 - 2.0
      await _tts.setVolume(1.0); // 0.0 - 1.0

      // Callbacks
      _tts.setStartHandler(() {
        _isSpeaking = true;
      });

      _tts.setCompletionHandler(() {
        _isSpeaking = false;
      });

      _tts.setErrorHandler((error) {
        print('❌ TTS Error: $error');
        _isSpeaking = false;
      });

      _isInitialized = true;
      print('✅ TTS service initialized');
      return true;
    } catch (e) {
      print('❌ Error initializing TTS: $e');
      return false;
    }
  }

  /// Hablar texto
  Future<void> speak(String text) async {
    if (!_isInitialized) {
      await initialize();
    }

    if (_isSpeaking) {
      await stop();
    }

    await _tts.speak(text);
  }

  /// Detener la reproducción
  Future<void> stop() async {
    await _tts.stop();
    _isSpeaking = false;
  }

  /// Pausar la reproducción
  Future<void> pause() async {
    await _tts.pause();
  }

  /// Obtener idiomas disponibles
  Future<List<String>> getAvailableLanguages() async {
    final languages = await _tts.getLanguages;
    return languages.cast<String>();
  }

  /// Obtener voces disponibles
  Future<List<Map<String, String>>> getAvailableVoices() async {
    final voices = await _tts.getVoices;
    return voices.cast<Map<String, String>>();
  }

  /// Configurar velocidad (0.0 - 1.0)
  Future<void> setSpeed(double speed) async {
    await _tts.setSpeechRate(speed.clamp(0.0, 1.0));
  }

  /// Configurar tono (0.5 - 2.0)
  Future<void> setPitch(double pitch) async {
    await _tts.setPitch(pitch.clamp(0.5, 2.0));
  }
}
