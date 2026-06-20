import 'package:flutter_test/flutter_test.dart';
import 'package:apartalo_app/models/models.dart';

void main() {
  // ── Producto ────────────────────────────────────────────────────────────────

  group('Producto.fromJson', () {
    test('parses all fields correctly', () {
      final json = {
        'codigo': 'PROD-001',
        'nombre': 'Cafe Especial 250g',
        'descripcion': 'Descripcion',
        'precio': 35.0,
        'stock': 10,
        'stockReservado': 2,
        'imagenUrl': 'https://img.example.com/cafe.jpg',
        'estado': 'ACTIVO',
        'categoria': 'BEBIDAS',
      };
      final p = Producto.fromJson(json);
      expect(p.codigo, 'PROD-001');
      expect(p.nombre, 'Cafe Especial 250g');
      expect(p.precio, 35.0);
      expect(p.stock, 10);
      expect(p.stockReservado, 2);
      expect(p.estado, 'ACTIVO');
      expect(p.categoria, 'BEBIDAS');
    });

    test('uses default values for missing fields', () {
      final p = Producto.fromJson({'codigo': 'X', 'nombre': 'Test', 'precio': 0, 'stock': 0});
      expect(p.stockReservado, 0);
      expect(p.estado, 'ACTIVO');
      expect(p.imagenUrl, isNull);
      expect(p.categoria, isNull);
    });

    test('coerces int precio to double', () {
      final p = Producto.fromJson({'codigo': 'X', 'nombre': 'T', 'precio': 10, 'stock': 1});
      expect(p.precio, isA<double>());
      expect(p.precio, 10.0);
    });

    test('disponible = stock - stockReservado', () {
      final p = Producto.fromJson({
        'codigo': 'X', 'nombre': 'T', 'precio': 0, 'stock': 8, 'stockReservado': 3,
      });
      expect(p.disponible, 5);
    });

    test('toJson round-trips correctly', () {
      final json = {
        'codigo': 'P-1',
        'nombre': 'Azucar',
        'descripcion': null,
        'precio': 5.0,
        'stock': 20,
        'stockReservado': 0,
        'imagenUrl': null,
        'estado': 'ACTIVO',
        'categoria': null,
      };
      final p = Producto.fromJson(json);
      expect(p.toJson(), json);
    });
  });

  // ── Cliente ─────────────────────────────────────────────────────────────────

  group('Cliente.fromJson', () {
    test('parses all fields correctly', () {
      final json = {
        'id': 'CLI-001',
        'whatsapp': '51936958201',
        'nombre': 'Juan Perez',
        'telefono': '51936958201',
        'direccion': 'Jr. Lima 123',
        'fechaRegistro': '01/01/2024',
        'ultimaCompra': '10/03/2025',
        'departamento': 'Lima',
        'ciudad': 'Lima',
        'empresa': 'Mi Empresa',
        'notas': 'Cliente frecuente',
      };
      final c = Cliente.fromJson(json);
      expect(c.id, 'CLI-001');
      expect(c.whatsapp, '51936958201');
      expect(c.nombre, 'Juan Perez');
      expect(c.departamento, 'Lima');
      expect(c.empresa, 'Mi Empresa');
    });

    test('uses empty string for missing required fields', () {
      final c = Cliente.fromJson({});
      expect(c.id, '');
      expect(c.whatsapp, '');
      expect(c.nombre, '');
    });

    test('optional fields are null when missing', () {
      final c = Cliente.fromJson({'id': 'X', 'whatsapp': '1', 'nombre': 'T'});
      expect(c.direccion, isNull);
      expect(c.departamento, isNull);
      expect(c.empresa, isNull);
    });
  });

  // ── Pedido ──────────────────────────────────────────────────────────────────

  group('Pedido.fromJson', () {
    test('parses all fields correctly', () {
      final json = {
        'id': 'PED-12345678',
        'fecha': '17/03/2026',
        'hora': '10:30 a. m.',
        'whatsapp': '51936958201',
        'cliente': 'Juan Perez',
        'telefono': '51936958201',
        'direccion': 'Jr. Lima 123',
        'productos': '1x Cafe - S/35.00',
        'total': 35.0,
        'estado': 'PENDIENTE',
        'voucherUrls': null,
        'observaciones': 'Sin azucar',
      };
      final p = Pedido.fromJson(json);
      expect(p.id, 'PED-12345678');
      expect(p.fecha, '17/03/2026');
      expect(p.total, 35.0);
      expect(p.estado, 'PENDIENTE');
      expect(p.observaciones, 'Sin azucar');
    });

    test('coerces int total to double', () {
      final p = Pedido.fromJson({
        'id': 'X', 'fecha': '01/01/2026', 'whatsapp': '1',
        'cliente': 'T', 'productos': '', 'total': 50, 'estado': 'PENDIENTE',
      });
      expect(p.total, isA<double>());
      expect(p.total, 50.0);
    });

    test('uses default empty string for missing fields', () {
      final p = Pedido.fromJson({});
      expect(p.id, '');
      expect(p.fecha, '');
      expect(p.estado, '');
      expect(p.total, 0.0);
    });
  });
}
