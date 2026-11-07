import 'package:apartalo_app/services/comprobante_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('reading a comprobante', () {
    test('Yape: the amount under ¡Yapeaste! and the operation number', () {
      const texto = '¡Yapeaste!\nS/ 150\nJuan Pérez\n06 nov. 2026 - 10:32 am\nNro. de operación\n12345678';
      final c = ComprobanteLeido.deTexto(texto);
      expect(c.monto, 150);
      expect(c.operacion, '12345678');
    });

    test('BCP transfer: Monto transferido wins over the commission and the ITF', () {
      const texto = 'Operación exitosa\nComisión S/ 0.50\nMonto transferido S/ 1,250.50\nITF S/ 0.05\n'
          'Número de operación: 00789123';
      final c = ComprobanteLeido.deTexto(texto);
      expect(c.monto, 1250.5);
      expect(c.operacion, '00789123');
    });

    test('without a key word, the largest amount (never the commission)', () {
      final c = ComprobanteLeido.deTexto('Constancia\nS/ 80.00\nComisión S/ 2.00');
      expect(c.monto, 80);
      expect(c.operacion, isNull);
    });

    test('"Código de operación" and "Operación: 123" are read too', () {
      expect(ComprobanteLeido.deTexto('Código de operación 4455 66').operacion, '445566');
      expect(ComprobanteLeido.deTexto('Operación: 998877').operacion, '998877');
    });

    test('a photo with no text proposes nothing', () {
      final c = ComprobanteLeido.deTexto('');
      expect(c.monto, isNull);
      expect(c.operacion, isNull);
    });

    test('numbers in Peruvian and European formats', () {
      expect(ComprobanteLeido.numero('1,250.50'), 1250.5);
      expect(ComprobanteLeido.numero('1.250,50'), 1250.5);
      expect(ComprobanteLeido.numero('25,50'), 25.5);
      expect(ComprobanteLeido.numero('1,250'), 1250);
      expect(ComprobanteLeido.numero('150'), 150);
      expect(ComprobanteLeido.numero('150.'), 150);
    });
  });
}
