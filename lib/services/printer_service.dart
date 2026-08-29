import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../screens/tabs/pedidos/helpers/producto_parser.dart';

/// Modelo de pedido simplificado para impresión
class PedidoPrint {
  final String id;
  final String fecha;
  final String hora;
  final String cliente;
  final String telefono;
  final String direccion;
  final String productos;
  final double total;
  final String? departamento;
  final String? ciudad;
  final String? businessWhatsapp; // Número de WhatsApp del negocio
  final String? businessId;       // ID del negocio (para URL de tracking)

  PedidoPrint({
    required this.id,
    required this.fecha,
    required this.hora,
    required this.cliente,
    required this.telefono,
    required this.direccion,
    required this.productos,
    required this.total,
    this.departamento,
    this.ciudad,
    this.businessWhatsapp,
    this.businessId,
  });
}

class PrinterService {
  BluetoothDevice? _connectedDevice;
  BluetoothCharacteristic? _writeCharacteristic;
  bool _isConnected = false;
  String? _savedDeviceId;

  // Logo Fincas en formato hex (60x60 pixels - 8 bytes width x 60 height)
  // Puedes personalizar este logo
  static const String _logoHex = '000000000000000000000000000000000000000000000000000000000000000000000000000000000000001FC00000000000007FF0000000000001FFFC00000000000FFFFF80000000001FFFFFC0000000007FFFFFF0000000006FF8FFB000000000DFCD9FD800000001DF8F8FDC00000001BF9FCFEC00000001BF1FC7EC000000003F3FE7E0000000003F3FE7E0000000003F3FE7E0000000003F1FC7E0000000003F9FCFE0000000001F870FC0000000001FC01FC0000000000FF07F80000000000FFFFF800000000007FFFF000000000003FFFE000000000001FFFC0000000001FFFFFFFC00000001FFFFFFFC00000001FFFFFFFC00000001FFFFFFFC00000001E000003C60000001E000003C78000001E000003C7C000001E000003C1E000001E000003C0E000001E000003C0F000001E000003C07000001E000003C07000001E000003C07000001E000003C07000001E000003C07000001E000003C0F000001E000003C0E000001E000003C1E000001E000003C7C000001E000003C78000001E000003C60000001FFFFFFFC00000001FFFFFFFC00000001FFFFFFFC0000000FFFFFFFFF8000000FFFFFFFFF8000000FFFFFFFFF8000000FFFFFFFFF8000000FFFFFFFFF8000000FFFFFFFFF8000000FFFFFFFFF80000000000000000000';

  bool get isConnected => _isConnected;
  String get connectedDeviceName => _connectedDevice?.platformName ?? '';

  /// Inicializa el servicio y carga dispositivo guardado
  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    _savedDeviceId = prefs.getString('printer_device_id');
  }

  /// Escanea dispositivos Bluetooth
  Stream<List<ScanResult>> scanDevices() {
    FlutterBluePlus.startScan(timeout: const Duration(seconds: 10));
    return FlutterBluePlus.scanResults;
  }

  /// Detiene el escaneo
  Future<void> stopScan() async => await FlutterBluePlus.stopScan();

  /// Conecta a un dispositivo Bluetooth
  Future<bool> connect(BluetoothDevice device) async {
    try {
      await device.connect(timeout: const Duration(seconds: 10));
      _connectedDevice = device;
      List<BluetoothService> services = await device.discoverServices();

      // Buscar característica de escritura específica para impresoras térmicas
      for (var service in services) {
        for (var char in service.characteristics) {
          String charUuid = char.uuid.toString().toLowerCase();
          // UUIDs comunes de impresoras térmicas
          if (charUuid.contains("8841") || charUuid.contains("fff2") || charUuid.contains("aca3")) {
            if (char.properties.write || char.properties.writeWithoutResponse) {
              _writeCharacteristic = char;
              _isConnected = true;
              
              // Guardar dispositivo para reconexión automática
              final prefs = await SharedPreferences.getInstance();
              await prefs.setString('printer_device_id', device.remoteId.toString());
              await prefs.setString('printer_device_name', device.platformName);
              _savedDeviceId = device.remoteId.toString();
              
              debugPrint('[PRINTER] ✅ Conectado: $charUuid');
              return true;
            }
          }
        }
      }

      // Fallback: buscar cualquier característica de escritura
      for (var service in services) {
        for (var char in service.characteristics) {
          if (char.properties.write || char.properties.writeWithoutResponse) {
            _writeCharacteristic = char;
            _isConnected = true;
            
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString('printer_device_id', device.remoteId.toString());
            await prefs.setString('printer_device_name', device.platformName);
            _savedDeviceId = device.remoteId.toString();
            
            debugPrint('[PRINTER] ✅ Conectado (fallback): ${char.uuid}');
            return true;
          }
        }
      }

      return false;
    } catch (e) {
      debugPrint('[PRINTER] ❌ Error conexión: $e');
      return false;
    }
  }

  /// Intenta reconectar al último dispositivo guardado
  Future<bool> tryAutoReconnect() async {
    if (_savedDeviceId == null) return false;
    
    try {
      // Buscar dispositivos conectados al sistema
      final connectedDevices = FlutterBluePlus.connectedDevices;
      for (var device in connectedDevices) {
        if (device.remoteId.toString() == _savedDeviceId) {
          return await connect(device);
        }
      }
      return false;
    } catch (e) {
      debugPrint('[PRINTER] Error reconexión: $e');
      return false;
    }
  }

  /// Desconecta el dispositivo
  Future<void> disconnect() async {
    try {
      await _connectedDevice?.disconnect();
      _connectedDevice = null;
      _writeCharacteristic = null;
      _isConnected = false;
    } catch (e) {
      debugPrint('[PRINTER] Error desconectando: $e');
    }
  }

  /// Envía datos a la impresora
  Future<bool> _sendData(Uint8List data) async {
    if (_writeCharacteristic == null) return false;

    try {
      const chunkSize = 100;
      for (var i = 0; i < data.length; i += chunkSize) {
        final end = (i + chunkSize < data.length) ? i + chunkSize : data.length;
        final chunk = data.sublist(i, end);

        if (_writeCharacteristic!.properties.writeWithoutResponse) {
          await _writeCharacteristic!.write(chunk, withoutResponse: true);
        } else {
          await _writeCharacteristic!.write(chunk, withoutResponse: false);
        }
        await Future.delayed(const Duration(milliseconds: 50));
      }
      return true;
    } catch (e) {
      debugPrint('[PRINTER] ❌ Error enviando: $e');
      return false;
    }
  }

  /// Imprime etiqueta/ticket de pedido
  Future<bool> printPedido(PedidoPrint pedido, String businessName) async {
    if (!_isConnected || _writeCharacteristic == null) return false;

    try {
      final tsplCommands = _buildPedidoLabel(pedido, businessName);
      debugPrint('[PRINTER] 📄 Enviando etiqueta: ${tsplCommands.length} bytes');
      return await _sendData(Uint8List.fromList(tsplCommands.codeUnits));
    } catch (e) {
      debugPrint('[PRINTER] ❌ Error: $e');
      return false;
    }
  }

  /// Construye comandos TSPL para etiqueta de pedido
  String _buildPedidoLabel(PedidoPrint pedido, String businessName) {
    final StringBuffer cmd = StringBuffer();
    final biz = _sanitize(businessName);

    // 100mm = 800 dots wide; 150mm = 1200 dots tall
    cmd.writeln('SIZE 100 mm, 150 mm');
    cmd.writeln('GAP 2 mm, 0 mm');
    cmd.writeln('DIRECTION 1');
    cmd.writeln('CLS');

    int y = 5;
    const int lx = 70;                  // sangría izquierda para todo el texto

    // ── TOP BAR ──────────────────────────────────────────
    cmd.writeln('BAR 15,$y,770,14');
    y += 30;

    // ── BUSINESS NAME (font 5, x_mult=1 y_mult=2 → más alto) ──
    cmd.writeln('TEXT $lx,$y,"5",0,1,2,"$biz"');
    y += 114;                           // font5 48px × 2 = 96px + gap 18px

    // ── SUBTITLE "Pedido de [negocio]" (font 3) ──────────
    cmd.writeln('TEXT $lx,$y,"3",0,1,1,"Pedido de $biz"');
    y += 34;

    // ── THIN SEPARATOR ───────────────────────────────────
    cmd.writeln('BAR 15,$y,770,3');
    y += 15;

    // ── DATE + ORDER ID ──────────────────────────────────
    cmd.writeln('TEXT $lx,$y,"4",0,1,1,"${pedido.fecha}  ${pedido.hora}"');
    y += 44;
    cmd.writeln('TEXT $lx,$y,"4",0,1,1,"#${_sanitize(pedido.id)}"');
    y += 44;

    // ── THIN SEPARATOR → starts DESTINO section ──────────
    cmd.writeln('BAR 15,$y,770,3');
    y += 15;

    // ── DESTINO DE ENTREGA (font 4, normal) ──────────────
    cmd.writeln('TEXT $lx,$y,"4",0,1,1,"DESTINO DE ENTREGA"');
    y += 50;

    // Client name (font 4)
    cmd.writeln('TEXT $lx,$y,"4",0,1,1,"${_sanitize(pedido.cliente)}"');
    y += 50;

    // Delivery address — word-boundary wrap at 44 chars (no mid-word cuts)
    final dir = _sanitize(pedido.direccion);
    if (dir.isNotEmpty) {
      if (dir.length > 44) {
        final int p = dir.lastIndexOf(' ', 44);
        final int cut = p > 0 ? p : 44;
        cmd.writeln('TEXT $lx,$y,"4",0,1,1,"${dir.substring(0, cut)}"');
        y += 44;
        final String rest = dir.substring(cut).trim();
        if (rest.isNotEmpty) {
          cmd.writeln('TEXT $lx,$y,"4",0,1,1,"$rest"');
          y += 44;
        }
      } else {
        cmd.writeln('TEXT $lx,$y,"4",0,1,1,"$dir"');
        y += 44;
      }
    }

    // City, Department (font 4)
    final ubicParts = [pedido.ciudad, pedido.departamento]
        .where((e) => e != null && e!.isNotEmpty).toList();
    if (ubicParts.isNotEmpty) {
      cmd.writeln('TEXT $lx,$y,"4",0,1,1,"${_sanitize(ubicParts.join(', '))}"');
      y += 44;
    }


    // ── THIN SEPARATOR → starts PRODUCTOS section ────────
    y += 6;
    cmd.writeln('BAR 15,$y,770,3');
    y += 15;

    // ── PRODUCTOS (font 4, normal) ────────────────────────
    cmd.writeln('TEXT $lx,$y,"4",0,1,1,"PRODUCTOS"');
    y += 50;

    // Parse products — word-boundary wrap at 44 chars, no truncation

    final List<({String text, String roastedAt})> lineas = [];
    if (pedido.productos.trim().startsWith('[')) {
      try {
        final List<dynamic> raw = jsonDecode(pedido.productos);
        final items = agruparProductos(
          raw.whereType<Map>().map((p) => Map<String, dynamic>.from(p)).toList(),
        );
        for (final p in items) {
          final nombre    = _sanitize((p['nombre'] ?? p['name'] ?? '').toString());
          final cantidad  = p['cantidad'] ?? p['qty'] ?? 1;
          final unit      = p['unit']?.toString() ?? '';
          final roastedAt = p['roastedAt']?.toString() ?? '';
          if (nombre.isNotEmpty) {
            final qty = unit.isNotEmpty ? '$cantidad $unit' : '${cantidad}x';
            lineas.add((text: '$qty $nombre', roastedAt: roastedAt));
          }
        }
      } catch (_) {
        for (final raw in pedido.productos.split('\n')) {
          final clean = _sanitize(raw.trim());
          if (clean.isNotEmpty) lineas.add((text: clean, roastedAt: ''));
        }
      }
    } else {
      for (final raw in pedido.productos.split('\n')) {
        final clean = _sanitize(
            raw.replaceAll(RegExp(r'\s*[-–]\s*S/[\d.,]+'), '').trim());
        if (clean.isNotEmpty) lineas.add((text: clean, roastedAt: ''));
      }
    }

    for (final linea in lineas.take(6)) {
      if (linea.text.length > 44) {
        final int p = linea.text.lastIndexOf(' ', 44);
        final int cut = p > 0 ? p : 44;
        cmd.writeln('TEXT $lx,$y,"4",0,1,1,"${linea.text.substring(0, cut)}"');
        y += 46;
        final String rest = linea.text.substring(cut).trim();
        if (rest.isNotEmpty) {
          cmd.writeln('TEXT $lx,$y,"4",0,1,1,"$rest"');
          y += 46;
        }
      } else {
        cmd.writeln('TEXT $lx,$y,"4",0,1,1,"${linea.text}"');
        y += 46;
      }
      if (linea.roastedAt.isNotEmpty) {
        cmd.writeln('TEXT $lx,$y,"3",0,1,1,"Tueste: ${linea.roastedAt}"');
        y += 38;
      }
    }

    // ── THIN SEPARATOR → starts SEGUIMIENTO section ──────
    cmd.writeln('BAR 15,$y,770,3');
    y += 15;

    // ── SEGUIMIENTO DEL PEDIDO (font 4, normal) ──────────
    cmd.writeln('TEXT $lx,$y,"4",0,1,1,"SEGUIMIENTO DEL PEDIDO"');
    y += 50;

    // ── QR (cell=7=231px) + TEXT alongside (font 3, after QR+margin) ──
    final businessId = pedido.businessId ?? 'BIZ';
    final trackUrl = 'https://apartalo-core-9d633cdb9e1a.herokuapp.com/track/$businessId/${pedido.id}';
    cmd.writeln('QRCODE $lx,$y,M,7,A,0,"$trackUrl"');
    final int qrTextX = lx + 231 + 16;  // after QR (231px) + margin
    cmd.writeln('TEXT $qrTextX,$y,"3",0,1,1,"Ver estado en tiempo real"');
    cmd.writeln('TEXT $qrTextX,${y + 34},"3",0,1,1,"Confirmar entrega / recepcion"');
    y += 250;

    // ── FOOTER ───────────────────────────────────────────
    cmd.writeln('BAR 15,$y,770,14');
    y += 34;
    cmd.writeln('TEXT 257,$y,"4",0,1,1,"Gracias por tu compra!"');  // right-aligned: 785-(22chars×24px)

    cmd.writeln('PRINT 1,1');
    return cmd.toString();
  }

  /// Imprime página de prueba
  Future<bool> printTest(String businessName) async {
    if (!_isConnected || _writeCharacteristic == null) {
      debugPrint('[PRINTER] ❌ No conectado');
      return false;
    }

    try {
      final tsplTest = '''
SIZE 100 mm, 150 mm
GAP 2 mm, 0 mm
DIRECTION 1
CLS
BAR 20,20,760,10
BITMAP 320,60,8,60,0,$_logoHex
TEXT 400,180,"5",0,1,1,"${_sanitize(businessName)}"
TEXT 400,270,"3",0,1,1,"Sistema de Gestion"
BAR 20,340,760,6
TEXT 400,420,"4",0,1,1,"PRUEBA DE IMPRESION"
TEXT 400,500,"4",0,1,1,"Impresora conectada!"
TEXT 400,570,"3",0,1,1,"Bluetooth OK"
BAR 20,640,760,3
BOX 100,680,700,840,4
TEXT 400,720,"3",0,1,1,"Si puedes ver este ticket"
TEXT 400,780,"3",0,1,1,"todo funciona correctamente"
BAR 20,900,760,8
TEXT 400,950,"2",0,1,1,"${_sanitize(businessName)}"
TEXT 400,1000,"2",0,1,1,"Gracias por tu compra!"
PRINT 1,1
''';

      debugPrint('[PRINTER] 🧪 Enviando prueba...');
      return await _sendData(Uint8List.fromList(tsplTest.codeUnits));
    } catch (e) {
      debugPrint('[PRINTER] ❌ Error: $e');
      return false;
    }
  }

  /// Sanitiza texto para impresora (quita acentos y caracteres especiales)
  String _sanitize(String text) {
    return text
        .replaceAll('"', "'")
        .replaceAll('\n', ' ')
        .replaceAll('\r', ' ')
        .replaceAll('á', 'a')
        .replaceAll('é', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('ú', 'u')
        .replaceAll('ñ', 'n')
        .replaceAll('Á', 'A')
        .replaceAll('É', 'E')
        .replaceAll('Í', 'I')
        .replaceAll('Ó', 'O')
        .replaceAll('Ú', 'U')
        .replaceAll('Ñ', 'N')
        .replaceAll('¿', '')
        .replaceAll('¡', '');
  }

  /// Divide texto de productos en líneas
  List<String> _splitProductos(String text, int maxLen) {
    List<String> result = [];
    String remaining = text;
    
    while (remaining.isNotEmpty) {
      if (remaining.length <= maxLen) {
        result.add(remaining);
        break;
      }
      
      int splitIndex = remaining.lastIndexOf(' ', maxLen);
      if (splitIndex == -1) splitIndex = maxLen;
      
      result.add(remaining.substring(0, splitIndex));
      remaining = remaining.substring(splitIndex).trim();
    }
    
    return result;
  }
}
