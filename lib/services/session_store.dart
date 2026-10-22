import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';
import 'notification_service.dart';

/// Saves the chosen business on the device and in [ApiService]. One place for the login
/// screen and the "Mis negocios" screen, so both set up the session the same way.
class SessionStore {
  static Future<void> activateBusiness(Map<String, dynamic> negocio, {required bool isPlatformAdmin}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('business_id', negocio['businessId']);
    await prefs.setString('business_name', negocio['name']);
    await prefs.setString('business_direccion', negocio['address'] ?? '');
    await prefs.setString('business_ciudad', negocio['city'] ?? '');
    // Antes se decidía por teléfono; ahora toda cuenta activa con negocio es miembro.
    await prefs.setBool('is_tostador', true);
    await prefs.setString('business_role', (negocio['role'] ?? '').toString());
    await prefs.setBool('is_platform_admin', isPlatformAdmin);

    ApiService.businessId = negocio['businessId'];
    ApiService.businessName = negocio['name'] ?? '';
    ApiService.businessDireccion = negocio['address'] ?? '';
    ApiService.businessCiudad = negocio['city'] ?? '';
    ApiService.isTostador = true;

    await NotificationService().resendTokenAfterLogin();
  }
}
