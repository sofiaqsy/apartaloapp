import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../services/printer_service.dart';

class PrinterProvider extends ChangeNotifier {
  final PrinterService _printerService = PrinterService();
  List<ScanResult> _devices = [];
  bool _isScanning = false;
  bool _isConnecting = false;
  bool _isPrinting = false;
  String? _error;
  
  // Getters
  List<ScanResult> get devices => _devices;
  bool get isScanning => _isScanning;
  bool get isConnecting => _isConnecting;
  bool get isPrinting => _isPrinting;
  bool get isConnected => _printerService.isConnected;
  String get connectedDeviceName => _printerService.connectedDeviceName;
  String? get error => _error;

  /// Inicializa el provider
  Future<void> initialize() async {
    await _printerService.initialize();
    // Intentar reconectar automáticamente
    await tryAutoReconnect();
  }

  /// Intenta reconectar al último dispositivo
  Future<bool> tryAutoReconnect() async {
    try {
      final success = await _printerService.tryAutoReconnect();
      notifyListeners();
      return success;
    } catch (e) {
      return false;
    }
  }
  
  /// Inicia escaneo de dispositivos Bluetooth
  Future<void> startScan() async {
    _isScanning = true;
    _error = null;
    _devices = [];
    notifyListeners();
    
    try {
      // Verificar estado del Bluetooth
      final state = await FlutterBluePlus.adapterState.first;
      if (state != BluetoothAdapterState.on) {
        _error = 'Por favor enciende el Bluetooth';
        _isScanning = false;
        notifyListeners();
        return;
      }
      
      // Escuchar resultados del escaneo
      _printerService.scanDevices().listen((results) {
        _devices = results
            .where((r) => r.device.platformName.isNotEmpty)
            .toList();
        notifyListeners();
      });
      
      // Esperar a que termine el escaneo
      await Future.delayed(const Duration(seconds: 10));
      await _printerService.stopScan();
      
    } catch (e) {
      _error = e.toString();
    }
    
    _isScanning = false;
    notifyListeners();
  }
  
  /// Detiene el escaneo
  Future<void> stopScan() async {
    await _printerService.stopScan();
    _isScanning = false;
    notifyListeners();
  }
  
  /// Conecta a un dispositivo
  Future<bool> connectToDevice(BluetoothDevice device) async {
    _isConnecting = true;
    _error = null;
    notifyListeners();
    
    try {
      final success = await _printerService.connect(device);
      if (!success) {
        _error = 'No se pudo conectar a la impresora';
      }
      _isConnecting = false;
      notifyListeners();
      return success;
    } catch (e) {
      _error = e.toString();
      _isConnecting = false;
      notifyListeners();
      return false;
    }
  }
  
  /// Desconecta la impresora
  Future<void> disconnect() async {
    await _printerService.disconnect();
    notifyListeners();
  }
  
  /// Imprime un pedido
  Future<bool> printPedido(PedidoPrint pedido, String businessName) async {
    if (!isConnected) {
      _error = 'Impresora no conectada';
      notifyListeners();
      return false;
    }
    
    _isPrinting = true;
    _error = null;
    notifyListeners();
    
    try {
      final success = await _printerService.printPedido(pedido, businessName);
      if (!success) {
        _error = 'Error al imprimir';
      }
      _isPrinting = false;
      notifyListeners();
      return success;
    } catch (e) {
      _error = e.toString();
      _isPrinting = false;
      notifyListeners();
      return false;
    }
  }
  
  /// Imprime página de prueba
  Future<bool> printTest(String businessName) async {
    if (!isConnected) {
      _error = 'Impresora no conectada';
      notifyListeners();
      return false;
    }
    
    _isPrinting = true;
    _error = null;
    notifyListeners();
    
    try {
      final success = await _printerService.printTest(businessName);
      if (!success) {
        _error = 'Error al imprimir';
      }
      _isPrinting = false;
      notifyListeners();
      return success;
    } catch (e) {
      _error = e.toString();
      _isPrinting = false;
      notifyListeners();
      return false;
    }
  }

  /// Limpia el error
  void clearError() {
    _error = null;
    notifyListeners();
  }
}
