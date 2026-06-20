import 'package:speech_to_text/speech_to_text.dart';
import 'package:speech_to_text/speech_recognition_result.dart';

/// Servicio para reconocimiento de voz
class SpeechService {
  final SpeechToText _speech = SpeechToText();
  bool _isInitialized = false;
  bool _isListening = false;

  bool get isListening => _isListening;
  bool get isInitialized => _isInitialized;

  /// Inicializar el servicio de voz
  Future<bool> initialize() async {
    if (_isInitialized) return true;

    try {
      _isInitialized = await _speech.initialize(
        onStatus: (status) {
          print('🎤 Speech status: $status');
          _isListening = status == 'listening';
        },
        onError: (error) {
          print('❌ Speech error: $error');
          _isListening = false;
        },
      );

      if (_isInitialized) {
        print('✅ Speech service initialized');
        
        // Listar idiomas disponibles
        final locales = await _speech.locales();
        final spanish = locales.where((l) => l.localeId.startsWith('es'));
        print('🌍 Spanish locales: ${spanish.map((l) => l.localeId).join(', ')}');
      }

      return _isInitialized;
    } catch (e) {
      print('❌ Error initializing speech: $e');
      return false;
    }
  }

  /// Comenzar a escuchar
  Future<void> startListening({
    required Function(String) onResult,
    Function(String)? onPartialResult,
    Function()? onDone,
    Duration? listenFor,
    Duration? pauseFor,
  }) async {
    if (!_isInitialized) {
      final initialized = await initialize();
      if (!initialized) {
        throw Exception('No se pudo inicializar el reconocimiento de voz');
      }
    }

    if (_isListening) {
      await stopListening();
    }

    _isListening = true;

    await _speech.listen(
      onResult: (SpeechRecognitionResult result) {
        if (result.finalResult) {
          onResult(result.recognizedWords);
          onDone?.call();
        } else {
          onPartialResult?.call(result.recognizedWords);
        }
      },
      localeId: 'es_PE', // Español de Perú
      listenFor: listenFor ?? const Duration(seconds: 30),
      pauseFor: pauseFor ?? const Duration(seconds: 3),
      partialResults: true,
      cancelOnError: true,
      listenMode: ListenMode.confirmation,
    );
  }

  /// Detener la escucha
  Future<void> stopListening() async {
    if (_isListening) {
      await _speech.stop();
      _isListening = false;
    }
  }

  /// Cancelar la escucha
  Future<void> cancel() async {
    await _speech.cancel();
    _isListening = false;
  }

  /// Verificar si el dispositivo soporta reconocimiento de voz
  Future<bool> hasPermission() async {
    return await _speech.hasPermission;
  }

  /// Obtener idiomas disponibles
  Future<List<String>> getAvailableLocales() async {
    final locales = await _speech.locales();
    return locales.map((l) => l.localeId).toList();
  }
}
