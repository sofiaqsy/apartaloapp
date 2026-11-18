import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// El último registro que la persona abrió en la app (General Manager, 18 nov 2026: al compartir una imagen, "add a
/// third option that says the same about the last register open in the app"): un pedido, o una compra, un gasto o un
/// adelanto de Finanzas. Se guarda en el teléfono, por negocio, para ofrecerlo al compartir un comprobante.
class UltimoRegistro {
  UltimoRegistro._(this.clase, this.id, this.titulo, this.tipo, this.fila);

  /// 'pedido' o 'finanzas'.
  final String clase;
  final String id;
  final String titulo;

  /// En Finanzas: purchase, expense o advance_request, y la fila como se abrió.
  final String? tipo;
  final Map<String, dynamic>? fila;

  static String _clave(String negocio) => 'ultimo_registro_$negocio';

  static Future<void> pedido(String negocio, Map<String, dynamic> p) async {
    final id = '${p['id'] ?? ''}';
    if (id.isEmpty) return;
    final cliente = '${p['cliente'] ?? p['clienteNombre'] ?? p['nombreCliente'] ?? ''}'.trim();
    await _guardar(negocio, {'clase': 'pedido', 'id': id, 'titulo': cliente.isEmpty ? 'Pedido $id' : 'Pedido $id · $cliente'});
  }

  static Future<void> finanzas(String negocio, String tipo, Map<String, dynamic> f) async {
    final id = '${f['id'] ?? ''}';
    if (id.isEmpty) return;
    final titulo = switch (tipo) {
      'purchase' => 'Compra · ${f['agricultor'] ?? id}',
      'expense' => '${f['categoria'] ?? 'Gasto'} · ${f['proveedor'] ?? f['descripcion'] ?? id}',
      _ => 'Adelanto · ${f['para'] ?? id}',
    };
    await _guardar(negocio, {'clase': 'finanzas', 'id': id, 'titulo': titulo, 'tipo': tipo, 'fila': f});
  }

  static Future<void> _guardar(String negocio, Map<String, dynamic> v) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_clave(negocio), jsonEncode(v));
    } catch (_) {}
  }

  static Future<UltimoRegistro?> leer(String negocio) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_clave(negocio));
      if (raw == null) return null;
      final v = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      final fila = v['fila'] is Map ? Map<String, dynamic>.from(v['fila'] as Map) : null;
      return UltimoRegistro._('${v['clase']}', '${v['id']}', '${v['titulo']}', v['tipo']?.toString(), fila);
    } catch (_) {
      return null;
    }
  }
}
