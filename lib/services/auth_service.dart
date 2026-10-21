import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';

/// Result of POST /api/auth/session.
class AuthSession {
  AuthSession({
    required this.status,
    this.fullName = '',
    this.hasPhone = false,
    this.businesses = const [],
    this.businessName = '',
  });

  /// active | pending | join_pending | no_invitation | revoked
  final String status;

  /// Business the person asked to join (only with join_pending).
  final String businessName;
  final String fullName;
  final bool hasPhone;
  final List<Map<String, dynamic>> businesses;

  bool get isActive => status == 'active';

  factory AuthSession.fromJson(Map<String, dynamic> json) {
    final profile = (json['profile'] as Map?) ?? const {};
    return AuthSession(
      status: (json['status'] ?? 'no_invitation').toString(),
      fullName: (profile['fullName'] ?? '').toString(),
      hasPhone: profile['hasPhone'] == true,
      businessName: (json['businessName'] ?? '').toString(),
      businesses: ((json['businesses'] as List?) ?? const [])
          .map((b) => Map<String, dynamic>.from(b as Map))
          .toList(),
    );
  }
}

class AuthException implements Exception {
  AuthException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Sign in with Google / Apple through Firebase Authentication. Who the person is comes
/// from Firebase; what they may access comes only from the backend (farm_members).
class AuthService {
  static const _installMarkerKey = 'install_marker_v1';

  static FirebaseAuth get _auth => FirebaseAuth.instance;

  static bool get isSignedIn => _auth.currentUser != null;

  /// The iOS keychain keeps the Firebase session after the app is uninstalled. On a fresh
  /// install (no marker in SharedPreferences) we sign out so the login screen is shown again.
  static Future<void> clearStaleSessionOnFreshInstall() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_installMarkerKey) == true) return;
      if (_auth.currentUser != null) await _auth.signOut();
      await prefs.setBool(_installMarkerKey, true);
    } catch (e) {
      debugPrint('⚠️ clearStaleSessionOnFreshInstall: $e');
    }
  }

  static Future<String?> idToken() async => _auth.currentUser?.getIdToken();

  static Future<void> signInWithGoogle() => _signIn(GoogleAuthProvider());

  static Future<void> signInWithApple() =>
      _signIn(AppleAuthProvider()..addScope('email')..addScope('name'));

  static Future<void> _signIn(AuthProvider provider) async {
    try {
      await _auth.signInWithProvider(provider);
    } on FirebaseAuthException catch (e) {
      if (e.code == 'canceled' || e.code == 'web-context-canceled' || e.code == 'popup-closed-by-user') {
        throw AuthException('cancelled');
      }
      debugPrint('⚠️ signIn error: ${e.code}');
      throw AuthException('No se pudo iniciar sesión. Intenta de nuevo.');
    }
  }

  /// Asks the backend who this signed-in person is and which businesses they can use.
  static Future<AuthSession> fetchSession() async {
    final res = await http
        .post(Uri.parse('${ApiService.baseUrl}/api/auth/session'),
            headers: {'Content-Type': 'application/json'}, body: '{}')
        .timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) {
      throw AuthException('No se pudo verificar tu cuenta (${res.statusCode}).');
    }
    return AuthSession.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  /// Stores the phone on the profile. Returns null on success or an error message.
  static Future<String?> savePhone(String phone) async {
    final res = await http
        .post(Uri.parse('${ApiService.baseUrl}/api/auth/phone'),
            headers: {'Content-Type': 'application/json'}, body: jsonEncode({'phone': phone}))
        .timeout(const Duration(seconds: 15));
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    if (body['saved'] == true || body['reason'] == 'already-set') return null;
    switch (body['reason']) {
      case 'invalid-phone':
        return 'Número inválido. Usa 9 dígitos, por ejemplo 987654321.';
      case 'phone-in-use':
        return 'Ese número ya está registrado en otra cuenta.';
      default:
        return 'No se pudo guardar el número.';
    }
  }

  static Map<String, String> get _json => {'Content-Type': 'application/json'};

  static Map<String, dynamic> _decode(http.Response res) {
    try {
      return jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }

  /// Sends the invitation code. Returns null on success or an error message.
  static Future<String?> submitJoinCode(String code) async {
    final res = await http
        .post(Uri.parse('${ApiService.baseUrl}/api/auth/join'), headers: _json, body: jsonEncode({'code': code}))
        .timeout(const Duration(seconds: 15));
    if (res.statusCode == 200) return null;
    return (_decode(res)['error'] ?? 'No se pudo enviar el código.').toString();
  }

  /// Owner: creates a temporary invitation code. Returns {code, expiresAt, role, maxUses}.
  static Future<Map<String, dynamic>> createJoinCode(String businessId) async {
    final res = await http
        .post(Uri.parse('${ApiService.baseUrl}/api/auth/join-codes'),
            headers: _json, body: jsonEncode({'businessId': businessId, 'role': 'staff'}))
        .timeout(const Duration(seconds: 15));
    final body = _decode(res);
    if (res.statusCode != 200) throw AuthException((body['error'] ?? 'No se pudo crear el código.').toString());
    return body;
  }

  /// Owner: pending requests to join the business.
  static Future<List<Map<String, dynamic>>> listJoinRequests(String businessId) async {
    final res = await http
        .get(Uri.parse('${ApiService.baseUrl}/api/auth/join-requests?businessId=$businessId'))
        .timeout(const Duration(seconds: 15));
    final body = _decode(res);
    if (res.statusCode != 200) throw AuthException((body['error'] ?? 'No se pudieron cargar las solicitudes.').toString());
    return ((body['requests'] as List?) ?? const []).map((r) => Map<String, dynamic>.from(r as Map)).toList();
  }

  static Future<void> decideJoinRequest(String businessId, String requestId, bool approve) async {
    final res = await http
        .post(Uri.parse('${ApiService.baseUrl}/api/auth/join-requests/$requestId/decision'),
            headers: _json, body: jsonEncode({'businessId': businessId, 'approve': approve}))
        .timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) {
      throw AuthException((_decode(res)['error'] ?? 'No se pudo resolver la solicitud.').toString());
    }
  }

  static Future<void> signOut() async {
    try {
      await _auth.signOut();
    } catch (e) {
      debugPrint('⚠️ signOut: $e');
    }
  }
}
