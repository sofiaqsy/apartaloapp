import 'dart:async';
import 'dart:io';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Lo que se lee de un comprobante (Yape, Plin, BCP): el monto y el número de operación. Puede faltar cualquiera.
class ComprobanteLeido {
  const ComprobanteLeido({this.monto, this.operacion});
  final double? monto;
  final String? operacion;

  static const vacio = ComprobanteLeido();

  /// Lee el texto que el teléfono sacó de la imagen. Sólo propone: la persona confirma o cambia el monto.
  factory ComprobanteLeido.deTexto(String texto) => ComprobanteLeido(monto: _monto(texto), operacion: _operacion(texto));

  // Las líneas con estas palabras dicen el monto pagado; comisión e ITF nunca.
  static final _clave = RegExp(r'monto|importe|total|yapeaste|plineaste|pagaste|enviaste|transferi|te yape|recibiste', caseSensitive: false);
  static final _noEs = RegExp(r'comisi[oó]n|itf|saldo|disponible', caseSensitive: false);
  static final _soles = RegExp(r'S\s*/\s*\.?\s*([0-9][0-9.,]*)', caseSensitive: false);

  static double? _monto(String texto) {
    final lineas = texto.split(RegExp(r'[\r\n]+'));
    double? conClave;
    double? mayor;
    for (var i = 0; i < lineas.length; i++) {
      final linea = lineas[i];
      if (_noEs.hasMatch(linea)) continue;
      for (final m in _soles.allMatches(linea)) {
        final v = numero(m.group(1)!);
        if (v == null || v <= 0) continue;
        // La palabra puede estar en la misma línea o en la de arriba ("Monto" y abajo "S/ 150.00").
        if (conClave == null && (_clave.hasMatch(linea) || (i > 0 && _clave.hasMatch(lineas[i - 1])))) conClave = v;
        if (mayor == null || v > mayor) mayor = v;
      }
    }
    return conClave ?? mayor;
  }

  static final _op = RegExp(
      r'(?:n[º°o]\.?|nro\.?|n[uú]mero|c[oó]digo|cod\.?)\s*(?:de\s+)?operaci[oó]n\s*:?\s*([0-9][0-9 ]{3,24})|operaci[oó]n\s*(?:n[º°o]\.?|nro\.?)?\s*:\s*([0-9][0-9 ]{3,24})',
      caseSensitive: false);

  static String? _operacion(String texto) {
    final m = _op.firstMatch(texto);
    if (m == null) return null;
    final n = (m.group(1) ?? m.group(2) ?? '').replaceAll(' ', '');
    return n.length >= 4 ? n : null;
  }

  /// "1,250.50", "1.250,50", "150", "150,5" → número. Con los dos signos, el último separa los decimales;
  /// con uno solo, es decimal si lo siguen 1 o 2 cifras ("25,50"), si no es de miles ("1,250").
  static double? numero(String s) {
    var t = s.trim().replaceAll(RegExp(r'[.,]+$'), '');
    if (t.isEmpty) return null;
    final punto = t.lastIndexOf('.');
    final coma = t.lastIndexOf(',');
    if (punto >= 0 && coma >= 0) {
      final dec = punto > coma ? '.' : ',';
      final mil = dec == '.' ? ',' : '.';
      t = t.replaceAll(mil, '').replaceAll(dec, '.');
    } else if (punto >= 0 || coma >= 0) {
      final signo = punto >= 0 ? '.' : ',';
      final partes = t.split(signo);
      final ultimo = partes.last;
      t = partes.length == 2 && ultimo.length <= 2 ? '${partes.first}.$ultimo' : partes.join();
    }
    return double.tryParse(t);
  }
}

/// Comprobantes: leer la imagen en el teléfono (sin internet) y recibir las que se comparten desde WhatsApp.
/// Las imágenes compartidas llegan a la caché de la app, nunca a la galería; se borran al guardar o al cerrar.
class ComprobanteService {
  static const _canal = MethodChannel('com.apartalo/comprobante');

  /// Para las pruebas: reemplaza la lectura del teléfono.
  @visibleForTesting
  static Future<String> Function(String ruta)? leerTextoParaPruebas;

  /// El texto de la imagen, leído en el teléfono (iPhone: Vision; Android: ML Kit). Vacío si no se pudo leer.
  static Future<String> leerTexto(String ruta) async {
    try {
      final prueba = leerTextoParaPruebas;
      if (prueba != null) return await prueba(ruta);
      return await _canal.invokeMethod<String>('leerTexto', {'ruta': ruta}).timeout(const Duration(seconds: 20)) ?? '';
    } catch (e) {
      debugPrint('Comprobante no leído: $e');
      return '';
    }
  }

  static Future<ComprobanteLeido> leer(String ruta) async {
    final texto = await leerTexto(ruta);
    return texto.trim().isEmpty ? ComprobanteLeido.vacio : ComprobanteLeido.deTexto(texto);
  }

  /// Una imagen compartida a la app que espera a que la persona elija su pedido.
  static final ValueNotifier<String?> compartido = ValueNotifier(null);

  static bool _escuchando = false;

  /// Android avisa por el canal; el iPhone abre fincas://comprobante y la imagen se toma del grupo de la app.
  static Future<void> escuchar() async {
    if (_escuchando) return;
    _escuchando = true;
    _canal.setMethodCallHandler((call) async {
      if (call.method == 'compartido' && call.arguments is String) compartido.value = call.arguments as String;
    });
    await _traerPendiente();
    try {
      final links = AppLinks();
      links.uriLinkStream.listen((uri) {
        if (esEnlaceComprobante(uri)) _traerPendiente();
      }, onError: (_) {});
    } catch (e) {
      debugPrint('Enlace de comprobante no leído: $e');
    }
  }

  static bool esEnlaceComprobante(Uri? uri) => uri != null && uri.scheme == 'fincas' && uri.host == 'comprobante';

  static Future<void> _traerPendiente() async {
    try {
      final ruta = await _canal.invokeMethod<String>('pendiente');
      if (ruta != null && ruta.isNotEmpty) compartido.value = ruta;
    } catch (e) {
      debugPrint('Sin comprobante compartido: $e');
    }
  }

  /// Borra la copia temporal (al guardar o al cerrar sin guardar). Sólo dentro de la caché de la app.
  static void borrarTemporal(String? ruta) {
    if (ruta == null) return;
    try {
      final f = File(ruta);
      if (f.existsSync()) f.deleteSync();
    } catch (_) {}
  }
}
