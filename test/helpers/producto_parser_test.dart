import 'package:flutter_test/flutter_test.dart';
import 'package:apartalo_app/screens/tabs/pedidos/helpers/producto_parser.dart';

void main() {
  group('parseProductos', () {
    // ── Null / empty ──────────────────────────────────────────────────────────

    test('returns [] for null', () {
      expect(parseProductos(null), isEmpty);
    });

    test('returns [] for empty string', () {
      expect(parseProductos(''), isEmpty);
    });

    // ── List<Map> input ───────────────────────────────────────────────────────

    test('parses a List<Map> directly', () {
      final input = [
        {'nombre': 'Cafe 250g', 'cantidad': 2, 'precio': 17.50, 'subtotal': 35.0},
      ];
      final result = parseProductos(input);
      expect(result.length, 1);
      expect(result[0]['nombre'], 'Cafe 250g');
      expect(result[0]['cantidad'], 2);
      expect(result[0]['precio'], 17.50);
      expect(result[0]['subtotal'], 35.0);
    });

    test('computes subtotal from precio*cantidad when subtotal is missing', () {
      final input = [
        {'nombre': 'Producto A', 'cantidad': 3, 'precio': 10.0},
      ];
      final result = parseProductos(input);
      expect(result[0]['subtotal'], 30.0);
    });

    test('fills defaults for empty maps in list (nombre stays empty)', () {
      final input = [
        {'nombre': 'Valido', 'cantidad': 1, 'precio': 5.0},
        <String, dynamic>{},
      ];
      final result = parseProductos(input);
      // Empty map gets default cantidad/precio/subtotal, not filtered out
      expect(result.length, 2);
      expect(result[0]['nombre'], 'Valido');
      expect(result[1]['cantidad'], 1);   // default
      expect(result[1]['precio'], 0.0);   // default
    });

    // ── JSON string input ─────────────────────────────────────────────────────

    test('parses a JSON array string', () {
      const json = '[{"nombre":"Cafe","cantidad":1,"precio":35.0,"subtotal":35.0}]';
      final result = parseProductos(json);
      expect(result.length, 1);
      expect(result[0]['nombre'], 'Cafe');
      expect(result[0]['precio'], 35.0);
    });

    test('falls back to string parser when JSON is malformed', () {
      const bad = '[{nombre: Cafe, precio: 35}]'; // invalid JSON
      final result = parseProductos(bad);
      // Should not throw; result may be 1 fallback item or parsed items
      expect(result, isA<List>());
    });

    // ── "Nx Nombre - S/precio" string format ──────────────────────────────────

    test('parses "1x Cafe Especial 250g - S/35.00"', () {
      final result = parseProductos('1x Cafe Especial 250g - S/35.00');
      expect(result.length, 1);
      expect(result[0]['nombre'], 'Cafe Especial 250g');
      expect(result[0]['cantidad'], 1);
      expect(result[0]['subtotal'], 35.0);
    });

    test('parses "2x Cafe - S/35.00" — cantidad 2, precio unitario 17.50', () {
      final result = parseProductos('2x Cafe - S/35.00');
      expect(result.length, 1);
      expect(result[0]['cantidad'], 2);
      expect(result[0]['subtotal'], 35.0);
      expect(result[0]['precio'], closeTo(17.50, 0.01));
    });

    test('parses multiple products separated by comma+space', () {
      const input = '1x Producto A - S/10.00, 2x Producto B - S/20.00';
      final result = parseProductos(input);
      expect(result.length, 2);
      expect(result[0]['nombre'], 'Producto A');
      expect(result[1]['nombre'], 'Producto B');
      expect(result[1]['cantidad'], 2);
    });

    test('parses multiple products separated by newlines', () {
      const input = '1x Cafe - S/35.00\n2x Azucar - S/10.00';
      final result = parseProductos(input);
      expect(result.length, 2);
      expect(result[0]['nombre'], 'Cafe');
      expect(result[1]['nombre'], 'Azucar');
    });

    test('parses product with no quantity prefix (defaults to 1)', () {
      final result = parseProductos('Manzana - S/5.00');
      expect(result.length, 1);
      expect(result[0]['cantidad'], 1);
      expect(result[0]['subtotal'], 5.0);
    });

    test('returns fallback item for unrecognized plain string', () {
      final result = parseProductos('Pedido especial sin precio');
      expect(result.length, 1);
      expect(result[0]['nombre'], 'Pedido especial sin precio');
      expect(result[0]['precio'], 0.0);
    });

    // ── Type coercion ─────────────────────────────────────────────────────────

    test('coerces int precio to double in List<Map>', () {
      final input = [
        {'nombre': 'Test', 'cantidad': 1, 'precio': 10, 'subtotal': 10},
      ];
      final result = parseProductos(input);
      expect(result[0]['precio'], isA<double>());
    });
  });
}
