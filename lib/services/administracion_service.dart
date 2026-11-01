import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'api_service.dart';

/// Administración: gastos, adelantos, entregas de café, pagos y pendientes.
/// Habla con /api/administracion del backend, que reenvía el login de la persona a la base de
/// operaciones (fincas). Las reglas las decide la base: miembro de la finca, sólo el dueño entrega
/// adelantos, nada se borra.
class AdministracionService {
  static String get _base => '${ApiService.baseUrl}/api/administracion/${ApiService.businessId}';
  static const _json = {'Content-Type': 'application/json'};
  static final _random = Random.secure();

  /// Clave única por envío: si la señal falla y se reintenta, la base guarda una sola vez.
  static String nuevaClave(String formulario) {
    final suffix = List.generate(8, (_) => _random.nextInt(36).toRadixString(36)).join();
    return '$formulario-${DateTime.now().millisecondsSinceEpoch}-$suffix';
  }

  /// formulario: gasto, pagoGasto, adelanto, aprobarAdelanto, rechazarAdelanto, entrega, precio, pago, proveedor, retiro.
  static Future<ApiResponse<Map<String, dynamic>>> registrar(
    String formulario,
    Map<String, dynamic> datos, {
    required String clave,
  }) async {
    try {
      final res = await http
          .post(Uri.parse('$_base/registrar/$formulario'), headers: _json, body: jsonEncode({...datos, 'clientRef': clave}))
          .timeout(const Duration(seconds: 25));
      final body = _decode(res.body);
      if (res.statusCode == 200 && body is Map && body['ok'] == true) {
        return ApiResponse.success(Map<String, dynamic>.from(body['result'] ?? {}));
      }
      return ApiResponse.error(_mensaje(res.statusCode, body));
    } catch (_) {
      return ApiResponse.error('No se guardó: revisa la señal e inténtalo de nuevo. No se duplicará.');
    }
  }

  static Future<ApiResponse<Map<String, dynamic>>> pendientes() => _get('pendientes');

  static Future<ApiResponse<Map<String, dynamic>>> resumen() => _get('resumen');

  /// Mis solicitudes: lo que la persona pidió y en qué quedó (Administración ve todas).
  static Future<ApiResponse<Map<String, dynamic>>> solicitudes() => _get('solicitudes');

  /// Categorías de gasto con el área y el centro de costo que sugieren, y la lista de áreas.
  static Future<ApiResponse<Map<String, dynamic>>> categorias() => _get('categorias');

  /// Qué área pondría la base a un gasto (para Combustible: compra o entrega del mismo día, o la de la persona).
  static Future<ApiResponse<Map<String, dynamic>>> sugerirArea(String categoria, [String? fecha]) => _get(
      'sugerir-area?categoria=${Uri.encodeQueryComponent(categoria)}${fecha == null ? '' : '&fecha=$fecha'}');

  /// Mi área: las áreas de la persona y, de la elegida, sus gastos por mes y los últimos.
  static Future<ApiResponse<Map<String, dynamic>>> miArea([String? area]) =>
      _get(area == null ? 'mi-area' : 'mi-area?area=${Uri.encodeQueryComponent(area)}');

  static Future<ApiResponse<List<Map<String, dynamic>>>> personas() async {
    try {
      final res = await http.get(Uri.parse('$_base/personas')).timeout(const Duration(seconds: 20));
      final body = _decode(res.body);
      if (res.statusCode == 200 && body is List) {
        return ApiResponse.success(body.map((e) => Map<String, dynamic>.from(e as Map)).toList());
      }
      return ApiResponse.error(_mensaje(res.statusCode, body));
    } catch (_) {
      return ApiResponse.error('Sin conexión');
    }
  }

  static Future<ApiResponse<Map<String, dynamic>>> _get(String path) async {
    try {
      final res = await http.get(Uri.parse('$_base/$path')).timeout(const Duration(seconds: 20));
      final body = _decode(res.body);
      if (res.statusCode == 200 && body is Map) return ApiResponse.success(Map<String, dynamic>.from(body));
      return ApiResponse.error(_mensaje(res.statusCode, body));
    } catch (_) {
      return ApiResponse.error('Sin conexión');
    }
  }

  static dynamic _decode(String text) {
    try {
      return jsonDecode(text);
    } catch (_) {
      return null;
    }
  }

  static String _mensaje(int status, dynamic body) {
    if (status == 401) return 'Vuelve a iniciar sesión';
    if (status == 403) return 'Sin acceso a la administración de este negocio';
    if (status == 503) return 'La administración aún no está activada en el servidor';
    if (body is Map && body['error'] != null) return body['error'].toString();
    return 'No se pudo guardar';
  }
}
