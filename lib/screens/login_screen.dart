import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/notification_service.dart';
import 'main_screen.dart';

enum _Step { signIn, pending, onboarding, ownerForm, businessPending, enterCode, joinPending, explore, revoked }

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _codeController = TextEditingController();
  final TextEditingController _bizNameController = TextEditingController();
  final TextEditingController _bizCityController = TextEditingController();
  bool _isLoading = false;
  bool _checking = true; // looking for a saved session at startup
  String? _errorMessage;
  _Step _step = _Step.signIn;
  Map<String, String>? _savedPending; // request in review remembered on this device
  AuthSession? _session;

  @override
  void initState() {
    super.initState();
    _loadPending();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkExistingLogin());
  }

  @override
  void dispose() {
    _codeController.dispose();
    _bizNameController.dispose();
    _bizCityController.dispose();
    super.dispose();
  }

  /// A saved business is only restored while the Firebase session is alive. After a
  /// re-install (or a sign out) there is no session and the login is requested again.
  Future<void> _loadPending() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final kind = prefs.getString('pending_kind');
      if (kind == null) return;
      if (mounted) {
        setState(() => _savedPending = {
              'kind': kind,
              'name': prefs.getString('pending_name') ?? '',
              'email': prefs.getString('pending_email') ?? '',
              'provider': prefs.getString('pending_provider') ?? '',
            });
      }
    } catch (_) {}
  }

  Future<void> _rememberPending(String kind, String name) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('pending_kind', kind);
      await prefs.setString('pending_name', name);
      await prefs.setString('pending_email', AuthService.maskEmail(AuthService.currentEmail));
      final provider = AuthService.currentProvider ?? '';
      await prefs.setString('pending_provider', provider.startsWith('apple') ? 'Apple' : (provider.startsWith('google') ? 'Google' : ''));
    } catch (_) {}
  }

  Future<void> _clearPending() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final k in ['pending_kind', 'pending_name', 'pending_email', 'pending_provider']) {
        await prefs.remove(k);
      }
      if (mounted) setState(() => _savedPending = null);
    } catch (_) {}
  }

  Future<void> _checkExistingLogin() async {
    try {
      await _restoreSession();
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _restoreSession() async {
    try {
      if (!AuthService.isSignedIn) return;
      final prefs = await SharedPreferences.getInstance();
      final businessId = prefs.getString('business_id');
      final businessName = prefs.getString('business_name');
      if (businessId == null || businessName == null) {
        // Signed in but no business saved on this device (for example a request still in
        // review): ask the server where this account stands and show the matching screen.
        try {
          await _continueWithSession();
        } catch (e) {
          if (mounted) setState(() => _errorMessage = 'No se pudo verificar tu cuenta. Revisa tu internet.');
        }
        return;
      }

      // Sesión restaurada: hay que repoblar ApiService igual que al iniciar sesión,
      // si no el nombre del negocio sale vacío en los PDF y las etiquetas.
      ApiService.businessId = businessId;
      ApiService.businessName = businessName;
      ApiService.businessDireccion = prefs.getString('business_direccion') ?? '';
      ApiService.businessCiudad = prefs.getString('business_ciudad') ?? '';
      ApiService.isTostador = prefs.getBool('is_tostador') ?? false;
      await NotificationService().resendTokenAfterLogin();
      _goToMain(businessId, businessName);
    } catch (e) {
      debugPrint('⚠️ Error verificando login: $e');
    }
  }

  Future<void> _signIn(Future<void> Function() provider) async {
    setState(() { _isLoading = true; _errorMessage = null; });
    try {
      await provider();
      await _continueWithSession();
    } on AuthException catch (e) {
      if (e.message != 'cancelled') setState(() => _errorMessage = e.message);
    } catch (e) {
      setState(() => _errorMessage = 'Error de conexión. Verifica tu internet.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _continueWithSession() async {
    final session = await AuthService.fetchSession();
    _session = session;
    switch (session.status) {
      case 'active':
        if (session.businesses.isNotEmpty) await _clearPending();
        if (session.businesses.isEmpty) {
          setState(() => _step = _Step.onboarding);
        } else {
          await _openBusiness(session);
        }
        break;
      case 'pending':
        setState(() => _step = _Step.pending);
        break;
      case 'join_pending':
        await _rememberPending('join', session.businessName);
        setState(() => _step = _Step.joinPending);
        break;
      case 'business_pending':
        await _rememberPending('business', session.businessName);
        setState(() => _step = _Step.businessPending);
        break;
      case 'revoked':
        setState(() => _step = _Step.revoked);
        break;
      default:
        setState(() => _step = _Step.onboarding);
    }
  }

  Future<void> _submitCode() async {
    final code = _codeController.text.trim();
    if (code.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').length != 8) {
      setState(() => _errorMessage = 'El código tiene 8 caracteres, por ejemplo ABCD-EFGH');
      return;
    }
    setState(() { _isLoading = true; _errorMessage = null; });
    try {
      final error = await AuthService.submitJoinCode(code);
      if (error != null) {
        setState(() => _errorMessage = error);
        return;
      }
      _codeController.clear();
      _session = AuthSession(status: 'join_pending');
      await _rememberPending('join', '');
      setState(() => _step = _Step.joinPending);
      _snack('Solicitud enviada. El dueño del negocio debe aprobarla.');
      await _continueWithSession(); // fills in the business name when the server knows it
    } catch (e) {
      setState(() => _errorMessage = 'Error de conexión. Verifica tu internet.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text), duration: const Duration(seconds: 5)));
  }

  Future<void> _submitBusiness() async {
    final name = _bizNameController.text.trim();
    final city = _bizCityController.text.trim();
    if (name.length < 3) { setState(() => _errorMessage = 'Escribe el nombre de tu negocio'); return; }
    if (city.length < 2) { setState(() => _errorMessage = 'Escribe la ciudad'); return; }
    setState(() { _isLoading = true; _errorMessage = null; });
    try {
      final error = await AuthService.requestBusiness(name: name, city: city);
      if (error != null) {
        setState(() => _errorMessage = error);
        return;
      }
      // Confirm right away; do not depend on the follow-up session check to show it.
      _session = AuthSession(status: 'business_pending', businessName: name);
      await _rememberPending('business', name);
      setState(() => _step = _Step.businessPending);
      _snack('Solicitud enviada. Te avisaremos cuando tu negocio esté activo.');
    } catch (e) {
      setState(() => _errorMessage = 'Error de conexión. Verifica tu internet.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Widget _field(TextEditingController c, String label, {TextInputType? type, String? prefix, int? max}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: c,
        keyboardType: type,
        maxLength: max,
        decoration: InputDecoration(
          labelText: label,
          prefixText: prefix,
          counterText: '',
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
    );
  }

  Future<void> _refreshStatus() async {
    setState(() { _isLoading = true; _errorMessage = null; });
    try {
      await _continueWithSession();
    } catch (e) {
      setState(() => _errorMessage = 'Error de conexión. Verifica tu internet.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _openBusiness(AuthSession session) async {
    Map<String, dynamic>? business;
    if (session.businesses.length == 1) {
      business = session.businesses.first;
    } else {
      if (!mounted) return;
      business = await _mostrarSelectorNegocio(session.businesses);
    }
    if (business == null) return;
    await _iniciarSesion(business);
  }

  Future<void> _iniciarSesion(Map<String, dynamic> negocio) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('business_id', negocio['businessId']);
    await prefs.setString('business_name', negocio['name']);
    await prefs.setString('business_direccion', negocio['address'] ?? '');
    await prefs.setString('business_ciudad', negocio['city'] ?? '');
    // Antes se decidía por teléfono; ahora toda cuenta activa con negocio es miembro.
    await prefs.setBool('is_tostador', true);
    await prefs.setString('business_role', (negocio['role'] ?? '').toString());
    await prefs.setBool('is_platform_admin', _session?.isAdmin ?? false);

    ApiService.businessId = negocio['businessId'];
    ApiService.businessName = negocio['name'] ?? '';
    ApiService.businessDireccion = negocio['address'] ?? '';
    ApiService.businessCiudad = negocio['city'] ?? '';
    ApiService.isTostador = true;

    await NotificationService().resendTokenAfterLogin();
    _goToMain(negocio['businessId'], negocio['name']);
  }

  void _goToMain(String businessId, String businessName) {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => MainScreen(businessId: businessId, businessName: businessName),
      ),
    );
  }

  Future<void> _backToSignIn() async {
    await AuthService.signOut();
    if (!mounted) return;
    setState(() { _step = _Step.signIn; _errorMessage = null; _session = null; });
  }

  Future<Map<String, dynamic>?> _mostrarSelectorNegocio(List<Map<String, dynamic>> negocios) {
    return showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.symmetric(vertical: 10),
              width: 40, height: 4,
              decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 4, 20, 16),
              child: Text('Selecciona tu negocio', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            ),
            ...negocios.map((n) => ListTile(
              leading: CircleAvatar(
                backgroundColor: Colors.blue.shade50,
                child: Text(
                  (n['name'] ?? '?').toString().substring(0, 1).toUpperCase(),
                  style: TextStyle(color: Colors.blue.shade700, fontWeight: FontWeight.bold),
                ),
              ),
              title: Text(n['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: (n['city'] ?? '').toString().isNotEmpty ? Text(n['city']) : null,
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.pop(ctx, n),
            )),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  // ── UI ───────────────────────────────────────────────────────────────────

  Widget _primaryButton(String label, VoidCallback? onPressed, {Color? color, Color? textColor}) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: _isLoading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: color ?? Colors.brown.shade700,
          foregroundColor: textColor ?? Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        child: _isLoading
            ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
      ),
    );
  }

  Widget _pendingReminder() {
    final p = _savedPending!;
    final what = p['kind'] == 'join'
        ? 'unirte a un negocio'
        : (p['name']!.isNotEmpty ? 'registrar "${p['name']}"' : 'registrar tu negocio');
    final account = [
      if (p['provider']!.isNotEmpty) p['provider'],
      if (p['email']!.isNotEmpty) p['email'],
    ].join(' - ');
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        border: Border.all(color: Colors.amber.shade300),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Tienes una solicitud en revisión', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(
            'Pediste $what desde este teléfono. Inicia sesión con la misma cuenta${account.isNotEmpty ? ' ($account)' : ''} '
            'para ver el estado.',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade800),
          ),
        ],
      ),
    );
  }

  Widget _option(String title, String body, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: _isLoading ? null : onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(body, style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _message(String title, String body) {
    return Column(
      children: [
        Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text(body, textAlign: TextAlign.center, style: TextStyle(fontSize: 15, color: Colors.grey.shade700)),
        const SizedBox(height: 20),
        _primaryButton('Usar otra cuenta', _backToSignIn),
      ],
    );
  }

  Widget _stepContent() {
    switch (_step) {
      case _Step.pending:
        return _message('Cuenta en revisión',
            'Reconocimos tu correo. Falta que el administrador confirme tu acceso. Vuelve a intentarlo en unos minutos.');
      case _Step.onboarding:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Bienvenido a Fincas',
                textAlign: TextAlign.center, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text('¿Cómo quieres empezar?',
                textAlign: TextAlign.center, style: TextStyle(fontSize: 15, color: Colors.grey.shade600)),
            const SizedBox(height: 16),
            _option('Tengo un negocio', 'Quiero registrar mi negocio y manejar su operación.',
                () => setState(() { _step = _Step.ownerForm; _errorMessage = null; })),
            _option('Trabajo en un negocio', 'Ya pertenezco a un negocio y quiero unirme a su equipo.',
                () => setState(() { _step = _Step.enterCode; _errorMessage = null; })),
            _option('Estoy explorando', 'Todavía no quiero registrar ni unirme a un negocio.',
                () => setState(() { _step = _Step.explore; _errorMessage = null; })),
            const SizedBox(height: 8),
            TextButton(onPressed: _isLoading ? null : _backToSignIn, child: const Text('Usar otra cuenta')),
          ],
        );
      case _Step.ownerForm:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Registra tu negocio', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text('El administrador de Fincas revisará tu solicitud antes de activar el negocio.',
                style: TextStyle(fontSize: 14, color: Colors.grey.shade600)),
            const SizedBox(height: 14),
            _field(_bizNameController, 'Nombre del negocio', max: 80),
            _field(_bizCityController, 'Ciudad', max: 60),
            if (_errorMessage != null) ...[
              Text(_errorMessage!, style: const TextStyle(color: Colors.red, fontSize: 13)),
              const SizedBox(height: 8),
            ],
            _primaryButton('Enviar solicitud', _submitBusiness),
            const SizedBox(height: 8),
            Center(
              child: TextButton(
                onPressed: _isLoading ? null : () => setState(() { _step = _Step.onboarding; _errorMessage = null; }),
                child: const Text('Volver'),
              ),
            ),
          ],
        );
      case _Step.businessPending:
        return Column(
          children: [
            const Text('Solicitud enviada', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(
              _session != null && _session!.businessName.isNotEmpty
                  ? 'Recibimos el registro de "${_session!.businessName}". El administrador de Fincas lo revisará y, cuando lo apruebe, '
                      'toca "Revisar estado" para entrar a tu negocio.'
                  : 'Recibimos el registro de tu negocio. El administrador de Fincas lo revisará.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, color: Colors.grey.shade700),
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 8),
              Text(_errorMessage!, style: const TextStyle(color: Colors.red, fontSize: 13)),
            ],
            const SizedBox(height: 20),
            _primaryButton('Revisar estado', _refreshStatus),
            TextButton(onPressed: _isLoading ? null : _backToSignIn, child: const Text('Usar otra cuenta')),
            Text('Tu solicitud queda guardada. Para verla de nuevo, inicia sesión con esta misma cuenta.',
                textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
          ],
        );
      case _Step.explore:
        return Column(
          children: [
            const Text('Fincas', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(
              'Fincas es una herramienta para negocios de café: pedidos, productos, clientes y tostado. '
              'Si solo quieres comprar, hazlo por WhatsApp con tu negocio. Vuelve cuando quieras registrar o unirte a uno.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, color: Colors.grey.shade700),
            ),
            const SizedBox(height: 20),
            _primaryButton('Volver', () => setState(() => _step = _Step.onboarding)),
          ],
        );
      case _Step.enterCode:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Código de invitación', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text('Pídeselo al dueño del negocio. El dueño debe aprobar tu solicitud.',
                style: TextStyle(fontSize: 14, color: Colors.grey.shade600)),
            const SizedBox(height: 14),
            TextField(
              controller: _codeController,
              textCapitalization: TextCapitalization.characters,
              maxLength: 9,
              onSubmitted: (_) => _submitCode(),
              decoration: InputDecoration(
                hintText: 'ABCD-EFGH',
                counterText: '',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 8),
              Text(_errorMessage!, style: const TextStyle(color: Colors.red, fontSize: 13)),
            ],
            const SizedBox(height: 16),
            _primaryButton('Enviar solicitud', _submitCode),
            const SizedBox(height: 8),
            Center(
              child: TextButton(
                onPressed: _isLoading ? null : () => setState(() { _step = _Step.onboarding; _errorMessage = null; }),
                child: const Text('Volver'),
              ),
            ),
          ],
        );
      case _Step.joinPending:
        return Column(
          children: [
            const Text('Solicitud enviada', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(
              _session != null && _session!.businessName.isNotEmpty
                  ? 'Esperando que el dueño de ${_session!.businessName} apruebe tu acceso.'
                  : 'Esperando que el dueño del negocio apruebe tu acceso.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, color: Colors.grey.shade700),
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 8),
              Text(_errorMessage!, style: const TextStyle(color: Colors.red, fontSize: 13)),
            ],
            const SizedBox(height: 20),
            _primaryButton('Revisar estado', _refreshStatus),
            TextButton(onPressed: _isLoading ? null : _backToSignIn, child: const Text('Usar otra cuenta')),
            Text('Tu solicitud queda guardada. Para verla de nuevo, inicia sesión con esta misma cuenta.',
                textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
          ],
        );
      case _Step.revoked:
        return _message('Acceso bloqueado', 'El acceso de esta cuenta fue desactivado. Contacta al administrador.');
      case _Step.signIn:
        if (_checking) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        return Column(
          children: [
            if (_savedPending != null) _pendingReminder(),
            _primaryButton('Continuar con Google', () => _signIn(AuthService.signInWithGoogle),
                color: Colors.white, textColor: Colors.black87),
            const SizedBox(height: 12),
            _primaryButton('Continuar con Apple', () => _signIn(AuthService.signInWithApple),
                color: Colors.black, textColor: Colors.white),
            if (_errorMessage != null) ...[
              const SizedBox(height: 12),
              Text(_errorMessage!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.red, fontSize: 13)),
            ],
          ],
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        behavior: HitTestBehavior.translucent,
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.all(24.0),
              child: ConstrainedBox(
                // Fills the screen when there is room (Spacers center the content) and scrolls when
                // the form or the keyboard needs more height.
                constraints: BoxConstraints(minHeight: constraints.maxHeight - 48),
                child: IntrinsicHeight(
                  child: Column(
                    children: [
                      const Spacer(),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(24),
                        child: Image.asset('assets/splash/splash.png', width: 100, height: 100, fit: BoxFit.cover),
                      ),
                      const SizedBox(height: 24),
                      Text('Fincas',
                          style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.brown.shade800)),
                      const SizedBox(height: 8),
                      Text('Gestiona tu negocio fácilmente', style: TextStyle(fontSize: 16, color: Colors.grey.shade600)),
                      const Spacer(),
                      if (_isLoading)
                        const Padding(
                          padding: EdgeInsets.only(bottom: 12),
                          child: LinearProgressIndicator(minHeight: 3),
                        ),
                      _stepContent(),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
