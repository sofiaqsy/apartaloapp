import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'api_service.dart';

/// Enlaces de invitación: fincas://unirse?codigo=ABCD-EFGH (lo abre la página web /unirse/ABCD-EFGH).
/// El código espera aquí hasta que la pantalla de ingreso lo use.
class InviteLink {
  static final ValueNotifier<String?> codigo = ValueNotifier(null);

  /// La página que se comparte: muestra el código y abre la app.
  static String paginaWeb(String code) => '${ApiService.baseUrl}/unirse/$code';

  /// El código de un enlace, o null si el enlace no es una invitación.
  static String? codigoDe(Uri? uri) {
    if (uri == null) return null;
    String? raw;
    if (uri.scheme == 'fincas' && uri.host == 'unirse') raw = uri.queryParameters['codigo'];
    if ((uri.scheme == 'https' || uri.scheme == 'http') && uri.pathSegments.length == 2 && uri.pathSegments.first == 'unirse') {
      raw = uri.pathSegments.last;
    }
    final limpio = (raw ?? '').toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    if (limpio.length != 8) return null;
    return '${limpio.substring(0, 4)}-${limpio.substring(4)}';
  }

  static Future<void> escuchar() async {
    final links = AppLinks();
    try {
      final c = codigoDe(await links.getInitialLink());
      if (c != null) codigo.value = c;
    } catch (e) {
      debugPrint('Enlace de invitación no leído: $e');
    }
    links.uriLinkStream.listen((uri) {
      final c = codigoDe(uri);
      if (c != null) codigo.value = c;
    }, onError: (_) {});
  }
}
