import 'package:flutter/services.dart';
import 'dart:async';

/// Servicio para manejar el escáner de hardware Sunmi
/// Los escáneres Sunmi envían códigos de barras como entrada de teclado
class SunmiScannerService {
  static final SunmiScannerService _instance = SunmiScannerService._internal();
  factory SunmiScannerService() => _instance;
  SunmiScannerService._internal();

  final _scanController = StreamController<String>.broadcast();
  Stream<String> get onScan => _scanController.stream;

  String _buffer = '';
  DateTime _lastKeyTime = DateTime.now();
  
  // Tiempo máximo entre teclas para considerar que es del escáner (ms)
  // Los escáneres envían caracteres muy rápido (<50ms entre cada uno)
  static const int _scannerTimeout = 100;
  
  // Tiempo para considerar que terminó el escaneo
  static const int _scanCompleteTimeout = 150;
  
  Timer? _completeTimer;
  bool _isInitialized = false;

  /// Inicializar el servicio de escáner
  void initialize() {
    if (_isInitialized) return;
    _isInitialized = true;
    
    // Escuchar eventos de teclado de hardware
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
  }

  /// Manejar eventos de teclado
  bool _handleKeyEvent(KeyEvent event) {
    // Solo procesar KeyDown
    if (event is! KeyDownEvent) return false;
    
    final now = DateTime.now();
    final timeDiff = now.difference(_lastKeyTime).inMilliseconds;
    
    // Si pasó mucho tiempo, es entrada manual del usuario, no del escáner
    if (timeDiff > _scannerTimeout && _buffer.isNotEmpty) {
      _buffer = '';
    }
    
    _lastKeyTime = now;
    
    // Obtener el carácter
    final char = event.character;
    
    // Enter indica fin del escaneo
    if (event.logicalKey == LogicalKeyboardKey.enter) {
      if (_buffer.length >= 4) { // Mínimo 4 caracteres para un código válido
        _emitScan(_buffer);
      }
      _buffer = '';
      _completeTimer?.cancel();
      return true; // Consumir el evento
    }
    
    // Agregar carácter al buffer
    if (char != null && char.isNotEmpty) {
      _buffer += char;
      
      // Reiniciar timer de completado
      _completeTimer?.cancel();
      _completeTimer = Timer(
        const Duration(milliseconds: _scanCompleteTimeout),
        () {
          if (_buffer.length >= 4) {
            _emitScan(_buffer);
          }
          _buffer = '';
        },
      );
      
      return true; // Consumir el evento si parece ser del escáner
    }
    
    return false;
  }

  void _emitScan(String code) {
    final cleanCode = code.trim();
    if (cleanCode.isNotEmpty) {
      _scanController.add(cleanCode);
    }
  }

  /// Limpiar buffer manualmente
  void clearBuffer() {
    _buffer = '';
    _completeTimer?.cancel();
  }

  /// Liberar recursos
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    _completeTimer?.cancel();
    _scanController.close();
    _isInitialized = false;
  }

  /// Verificar si el dispositivo es Sunmi
  static Future<bool> isSunmiDevice() async {
    try {
      const channel = MethodChannel('com.apartalo/device_info');
      final String? manufacturer = await channel.invokeMethod('getManufacturer');
      return manufacturer?.toLowerCase().contains('sunmi') ?? false;
    } catch (e) {
      // Si falla, intentar detectar por modelo
      return false;
    }
  }
}
