import 'package:http/http.dart' as http;

/// HTTP client that identifies the app and attaches the Firebase ID token, but only
/// on requests to our own backend. Calls to third parties (Open Food Facts, UPCitemdb,
/// Gemini, ...) never receive the token.
class AuthClient extends http.BaseClient {
  AuthClient(
    this._inner, {
    required this.backendHost,
    required this.getToken,
  });

  final http.Client _inner;

  /// Resolved lazily: the .env is loaded after the client is created.
  final String? Function() backendHost;
  final Future<String?> Function() getToken;

  static const clientName = 'apartalo-app';

  bool _isBackend(Uri url) {
    final host = backendHost();
    return host != null && host.isNotEmpty && url.scheme == 'https' && url.host == host;
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (_isBackend(request.url)) {
      request.headers['X-Client'] = clientName;
      if (!request.headers.containsKey('Authorization')) {
        String? token;
        try {
          token = await getToken();
        } catch (_) {
          token = null; // never block a request because the token could not be read
        }
        if (token != null && token.isNotEmpty) {
          request.headers['Authorization'] = 'Bearer $token';
        }
      }
    }
    return _inner.send(request);
  }

  @override
  void close() => _inner.close();
}
