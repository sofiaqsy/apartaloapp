import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:apartalo_app/screens/tabs/pedidos/helpers/estado_pago_helper.dart';

void main() {
  group('EstadoPagoHelper.determinarEstadoPago', () {
    test('returns explicit estadoPago when present', () {
      final pedido = {'estadoPago': 'PAGADO', 'total': 100.0, 'montoPagado': 0.0};
      expect(EstadoPagoHelper.determinarEstadoPago(pedido), 'PAGADO');
    });

    test('ignores empty estadoPago string and infers from amounts', () {
      final pedido = {'estadoPago': '', 'total': 100.0, 'montoPagado': 100.0};
      expect(EstadoPagoHelper.determinarEstadoPago(pedido), EstadoPagoHelper.PAGADO);
    });

    test('returns PAGADO when montoPagado >= total', () {
      final pedido = {'total': 50.0, 'montoPagado': 50.0};
      expect(EstadoPagoHelper.determinarEstadoPago(pedido), EstadoPagoHelper.PAGADO);
    });

    test('returns PAGADO when montoPagado exceeds total', () {
      final pedido = {'total': 50.0, 'montoPagado': 60.0};
      expect(EstadoPagoHelper.determinarEstadoPago(pedido), EstadoPagoHelper.PAGADO);
    });

    test('returns PARCIAL when 0 < montoPagado < total', () {
      final pedido = {'total': 100.0, 'montoPagado': 40.0};
      expect(EstadoPagoHelper.determinarEstadoPago(pedido), EstadoPagoHelper.PARCIAL);
    });

    test('returns PENDIENTE_PAGO when montoPagado is 0 and no evidencias', () {
      final pedido = {'total': 100.0, 'montoPagado': 0.0, 'evidencias': <dynamic>[]};
      expect(EstadoPagoHelper.determinarEstadoPago(pedido), EstadoPagoHelper.PENDIENTE_PAGO);
    });

    test('returns PAGADO when evidencias list is not empty (legacy fallback)', () {
      final pedido = {
        'total': 100.0,
        'montoPagado': 0.0,
        'evidencias': ['voucher_url_1'],
      };
      expect(EstadoPagoHelper.determinarEstadoPago(pedido), EstadoPagoHelper.PAGADO);
    });

    test('returns PENDIENTE_PAGO when fields are missing', () {
      expect(
        EstadoPagoHelper.determinarEstadoPago({}),
        EstadoPagoHelper.PENDIENTE_PAGO,
      );
    });
  });

  group('EstadoPagoHelper.calcularDiasSinPago', () {
    test('returns 0 when estadoPago is PAGADO', () {
      final pedido = {'estadoPago': 'PAGADO', 'total': 100.0, 'montoPagado': 100.0};
      expect(EstadoPagoHelper.calcularDiasSinPago(pedido), 0);
    });

    test('returns 0 when no fecha is present', () {
      final pedido = {'total': 100.0, 'montoPagado': 0.0};
      expect(EstadoPagoHelper.calcularDiasSinPago(pedido), 0);
    });

    test('parses dd/mm/yyyy format correctly', () {
      // A date far in the past should return > 0 days
      final pedido = {'total': 100.0, 'montoPagado': 0.0, 'fecha': '01/01/2024'};
      final dias = EstadoPagoHelper.calcularDiasSinPago(pedido);
      expect(dias, greaterThan(0));
    });

    test('parses ISO format correctly', () {
      final pedido = {'total': 100.0, 'montoPagado': 0.0, 'fecha': '2024-01-01T00:00:00'};
      final dias = EstadoPagoHelper.calcularDiasSinPago(pedido);
      expect(dias, greaterThan(0));
    });

    test('returns 0 for invalid date format', () {
      final pedido = {'total': 100.0, 'montoPagado': 0.0, 'fecha': 'not-a-date'};
      expect(EstadoPagoHelper.calcularDiasSinPago(pedido), 0);
    });
  });

  group('EstadoPagoHelper.getColorEstadoPago', () {
    test('PAGADO is green', () {
      expect(EstadoPagoHelper.getColorEstadoPago('PAGADO'), Colors.green);
    });

    test('PARCIAL is amber', () {
      final color = EstadoPagoHelper.getColorEstadoPago('PARCIAL');
      expect(color, isA<Color>());
      // amber family has red=255, green~191
      expect(color.red, greaterThan(200));
    });

    test('PENDIENTE_PAGO is red family', () {
      final color = EstadoPagoHelper.getColorEstadoPago('PENDIENTE_PAGO');
      expect(color.red, greaterThan(color.blue));
    });

    test('unknown estado returns grey', () {
      expect(EstadoPagoHelper.getColorEstadoPago('OTRO'), Colors.grey);
    });
  });

  group('EstadoPagoHelper.getTextoAlerta', () {
    test('0 days → "Hoy"', () {
      expect(EstadoPagoHelper.getTextoAlerta(0), 'Hoy');
    });

    test('1 day → "1 día"', () {
      expect(EstadoPagoHelper.getTextoAlerta(1), '1 día');
    });

    test('5 days → "5 días"', () {
      expect(EstadoPagoHelper.getTextoAlerta(5), '5 días');
    });
  });
}
