import 'dart:typed_data';
import 'dart:ui' as ui;

/// La constancia de un retiro en efectivo (General Manager, 18 nov 2026: "I hate when I don't have evidence, I don't
/// remember what happened there ... upload an automatic image when the match is executed when is retiro or cash
/// payment"). Una imagen PNG con los datos del banco y lo que se pagó con ese efectivo, que se guarda como evidencia
/// al conciliar. Dice que la hizo la app: no reemplaza el voucher ni el recibo firmado.
class ConstanciaRetiro {
  /// Una línea del banco en efectivo: un retiro (BCP: "RETIRO AG …", "RETIRO ATM …") o un pago en efectivo.
  static bool esRetiro(String? descripcionBanco) => RegExp(r'RETIRO|EFECTIVO', caseSensitive: false).hasMatch(descripcionBanco ?? '');

  /// [filas]: (nombre, valor) en orden. [hecha]: cuándo se hizo la constancia.
  static Future<Uint8List> png({required String negocio, required List<(String, String)> filas, required DateTime hecha}) async {
    const ancho = 1080.0, margen = 72.0;
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);

    ui.Paragraph texto(String t, double tam, {ui.Color color = const ui.Color(0xFF1F2328), bool negrita = false, double? w}) {
      final b = ui.ParagraphBuilder(ui.ParagraphStyle(fontSize: tam, height: 1.3))
        ..pushStyle(ui.TextStyle(color: color, fontSize: tam, fontWeight: negrita ? ui.FontWeight.w700 : ui.FontWeight.w400))
        ..addText(t);
      return b.build()..layout(ui.ParagraphConstraints(width: w ?? ancho - 2 * margen));
    }

    final piezas = <(ui.Paragraph, double)>[]; // párrafo y espacio antes
    piezas.add((texto(negocio, 34, color: const ui.Color(0xFF57606A)), 0));
    piezas.add((texto('Constancia de retiro en efectivo', 52, negrita: true), 8));
    for (final f in filas) {
      piezas.add((texto(f.$1, 30, color: const ui.Color(0xFF57606A)), 36));
      piezas.add((texto(f.$2, 40, negrita: true), 4));
    }
    final dd = hecha.day.toString().padLeft(2, '0'), mm = hecha.month.toString().padLeft(2, '0');
    final hh = hecha.hour.toString().padLeft(2, '0'), mi = hecha.minute.toString().padLeft(2, '0');
    piezas.add((
      texto('Hecha por la app Fincas al conciliar, el $dd/$mm/${hecha.year} a las $hh:$mi. '
          'No reemplaza el voucher del banco ni el recibo firmado.', 28, color: const ui.Color(0xFF57606A)),
      56
    ));

    var alto = margen * 2;
    for (final p in piezas) {
      alto += p.$2 + p.$1.height;
    }
    canvas.drawRect(ui.Rect.fromLTWH(0, 0, ancho, alto), ui.Paint()..color = const ui.Color(0xFFFFFFFF));
    canvas.drawRect(ui.Rect.fromLTWH(0, 0, ancho, 16), ui.Paint()..color = const ui.Color(0xFF2E7D32));
    var y = margen;
    for (final p in piezas) {
      y += p.$2;
      canvas.drawParagraph(p.$1, ui.Offset(margen, y));
      y += p.$1.height;
    }
    final imagen = await recorder.endRecording().toImage(ancho.toInt(), alto.ceil());
    final datos = await imagen.toByteData(format: ui.ImageByteFormat.png);
    return datos!.buffer.asUint8List();
  }
}
