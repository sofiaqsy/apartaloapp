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

  /// Tarjetas Compras y Producción: {compras: {...}, produccion: {...}} (el dinero sólo para dueños).
  /// Con [solo] (p. ej. 'compras') el servidor calcula sólo ese proceso: la pantalla de un proceso no pide todos.
  static Future<ApiResponse<Map<String, dynamic>>> procesos({String? solo}) =>
      _get(solo == null ? 'procesos' : 'procesos?solo=${Uri.encodeComponent(solo)}');

  /// Pestaña Compras: compras de la más nueva a la más antigua, de [limit] en [limit] ({compras, total, hayMas}).
  static Future<ApiResponse<Map<String, dynamic>>> compras({int offset = 0, int limit = 20}) => _get('compras?offset=$offset&limit=$limit');

  /// Finanzas: una pestaña ('compras', 'gastos' o 'adelantos') de [limit] en [limit] ({filas, total, hayMas}): lo que
  /// espera (Pendiente o Urgente) y lo pagado o decidido el último mes. Sólo dueños (lo decide la base).
  static Future<ApiResponse<Map<String, dynamic>>> finanzasLista(String tipo, {int offset = 0, int limit = 20}) =>
      _get('finanzas/lista?tipo=${Uri.encodeComponent(tipo)}&offset=$offset&limit=$limit');

  /// Compras → Adelantos: los pedidos por aprobar (en la primera página) y los adelantos, del más nuevo al más antiguo.
  static Future<ApiResponse<Map<String, dynamic>>> adelantos({int offset = 0, int limit = 20}) => _get('adelantos?offset=$offset&limit=$limit');

  /// Detalle de un proveedor ({proveedor}); DNI o RUC, teléfono, cuentas y dinero sólo para dueños.
  static Future<ApiResponse<Map<String, dynamic>>> proveedor(String id) => _get('proveedores/${Uri.encodeComponent(id)}');

  /// Reporte de un proveedor para el PDF ({reporte}): se pide sólo al tocar Generar reporte.
  /// Reporte de Compras de [desde] a [hasta] (meses; a lo más 12, lo revisa la base). El dinero sólo llega a dueños.
  static Future<ApiResponse<Map<String, dynamic>>> reporteCompras(DateTime desde, DateTime hasta) {
    String mes(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}';
    return _get('compras/reporte?desde=${mes(desde)}&hasta=${mes(hasta)}');
  }

  /// Reporte de Producción de [desde] a [hasta] (meses; a lo más 12). Los costos sólo llegan a dueños.
  static Future<ApiResponse<Map<String, dynamic>>> reporteProduccion(DateTime desde, DateTime hasta) {
    String mes(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}';
    return _get('produccion/reporte?desde=${mes(desde)}&hasta=${mes(hasta)}');
  }

  /// Detalle de un lote de tostado (General Manager, 4 nov 2026): entró, salió, merma, lote verde, datos del tueste,
  /// notas, fotos y kilos por producto.
  static Future<ApiResponse<Map<String, dynamic>>> tostado(String id) => _get('produccion/tostados/${Uri.encodeComponent(id)}');

  static Future<ApiResponse<Map<String, dynamic>>> reporteProveedor(String id) => _get('proveedores/${Uri.encodeComponent(id)}/reporte');

  /// Subir evidencia (dueños): una foto o PDF del voucher o recibo de una compra (purchase), un gasto (expense),
  /// un pedido de adelanto (advance_request) o un adelanto (advance). El servidor revisa que sea foto o PDF.
  static Future<ApiResponse<Map<String, dynamic>>> subirEvidencia(
      {required String tipo, required String id, required List<int> bytes, String? nota}) async {
    try {
      final res = await http
          .post(Uri.parse('$_base/evidencias'),
              headers: _json,
              body: jsonEncode({'tipo': tipo, 'id': id, 'archivoBase64': base64Encode(bytes), 'nota': nota, 'clientRef': nuevaClave('evidencia')}))
          .timeout(const Duration(seconds: 60));
      final body = _decode(res.body);
      if (res.statusCode == 200 && body is Map && body['ok'] == true) return ApiResponse.success(Map<String, dynamic>.from(body));
      return ApiResponse.error(_mensaje(res.statusCode, body));
    } catch (_) {
      return ApiResponse.error('No se subió: revisa la señal e inténtalo de nuevo.');
    }
  }

  /// La evidencia de un registro ({evidencias}), con enlaces que sirven 10 minutos.
  static Future<ApiResponse<Map<String, dynamic>>> evidencias(String tipo, String id) =>
      _get('evidencias?tipo=${Uri.encodeComponent(tipo)}&id=${Uri.encodeComponent(id)}');

  /// Detalle de una compra ({compra}); el precio y los pagos sólo para dueños.
  static Future<ApiResponse<Map<String, dynamic>>> compra(String id) => _get('compras/${Uri.encodeComponent(id)}');

  /// Mis solicitudes: lo que la persona pidió y en qué quedó (Administración ve todas).
  static Future<ApiResponse<Map<String, dynamic>>> solicitudes() => _get('solicitudes');

  /// Categorías de gasto con el área y el centro de costo que sugieren, y la lista de áreas.
  static Future<ApiResponse<Map<String, dynamic>>> categorias() => _get('categorias');

  /// Qué área pondría la base a un gasto (para Combustible: compra o entrega del mismo día, o la de la persona).
  static Future<ApiResponse<Map<String, dynamic>>> sugerirArea(String categoria, [String? fecha]) =>
      _get('sugerir-area?categoria=${Uri.encodeQueryComponent(categoria)}${fecha == null ? '' : '&fecha=$fecha'}');

  /// Mi área: las áreas de la persona y, de la elegida, sus gastos por mes y los últimos.
  static Future<ApiResponse<Map<String, dynamic>>> miArea([String? area]) =>
      _get(area == null ? 'mi-area' : 'mi-area?area=${Uri.encodeQueryComponent(area)}');

  /// El equipo del negocio (sólo dueños): nombre, rol y áreas activas de cada persona.
  static Future<ApiResponse<Map<String, dynamic>>> equipo() => _get('equipo');

  /// Áreas sugeridas para una persona según lo que registró en 60 días (sólo dueños).
  static Future<ApiResponse<Map<String, dynamic>>> sugerenciaAreas(String perfilId) => _get('equipo/${Uri.encodeComponent(perfilId)}/sugerencia');

  /// Busca personas por nombre o apodo, de a una página: {personas, total, hayMas}.
  /// [area]: sólo los proveedores de ese proceso (los asignados o los que le vendieron un gasto).
  static Future<ApiResponse<Map<String, dynamic>>> buscarPersonas({String q = '', String? rol, String? area, int offset = 0, int limit = 20}) {
    final qs = Uri(queryParameters: {
      if (q.isNotEmpty) 'q': q,
      if (rol != null) 'rol': rol,
      if (area != null) 'area': area,
      'offset': '$offset',
      'limit': '$limit',
    }).query;
    return _get('personas/buscar?$qs');
  }

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
