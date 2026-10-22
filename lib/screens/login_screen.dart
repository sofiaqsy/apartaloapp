import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/notification_service.dart';
import '../services/session_store.dart';
import 'package:flutter/services.dart';
import '../theme/fincas_theme.dart';
import '../theme/fincas_tokens.dart';
import '../widgets/fincas_widgets.dart';
import 'businesses_screen.dart';
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

  Widget _field(TextEditingController c, String label, {TextInputType? type, int? max}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: FincasSpacing.field),
      child: TextField(
        controller: c,
        keyboardType: type,
        maxLength: max,
        decoration: InputDecoration(labelText: label, counterText: ''),
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

  /// After an explicit sign-in, show the businesses of the account (and the options to join or
  /// register another one) instead of entering one automatically.
  Future<void> _openBusiness(AuthSession session) async {
    if (!mounted) return;
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => BusinessesScreen(
          session: session,
          onSelect: (screenContext, business, s) async {
            await SessionStore.activateBusiness(business, isPlatformAdmin: s.isAdmin);
            // Use the hub's own context: this login page was replaced by the hub and is no longer mounted.
            if (!screenContext.mounted) return;
            Navigator.of(screenContext).pushReplacement(
              MaterialPageRoute(
                builder: (_) => MainScreen(businessId: business['businessId'], businessName: business['name']),
              ),
            );
          },
        ),
      ),
    );
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

  // ── UI ───────────────────────────────────────────────────────────────────

  Widget _errorText() => _errorMessage == null
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.only(bottom: FincasSpacing.m),
          child: Text(_errorMessage!, style: const TextStyle(color: FincasColors.error, fontSize: 14, height: 1.4)),
        );

  Widget _pendingReminder() {
    final p = _savedPending!;
    final what = p['kind'] == 'join'
        ? 'unirte a un negocio'
        : (p['name']!.isNotEmpty ? 'registrar "${p['name']}"' : 'registrar tu negocio');
    final account = [
      if (p['provider']!.isNotEmpty) p['provider'],
      if (p['email']!.isNotEmpty) p['email'],
    ].join(' - ');
    return Padding(
      padding: const EdgeInsets.only(bottom: FincasSpacing.l),
      child: FincasCard(
        tone: FincasTone.warning,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Tienes una solicitud en revisión', style: FincasText.label.copyWith(color: FincasColors.warning, fontWeight: FontWeight.w600)),
            const SizedBox(height: FincasSpacing.xs),
            Text(
              'Pediste $what desde este teléfono. Inicia sesión con la misma cuenta${account.isNotEmpty ? ' ($account)' : ''} '
              'para ver el estado.',
              style: FincasText.metadata.copyWith(color: FincasColors.warning),
            ),
          ],
        ),
      ),
    );
  }

  Widget _option(String title, String body, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(bottom: FincasSpacing.m),
      child: Semantics(
        button: true,
        label: '$title. $body',
        excludeSemantics: true,
        child: FincasCard(
          onTap: _isLoading ? null : onTap,
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: FincasText.sectionTitle),
                    const SizedBox(height: FincasSpacing.xs),
                    Text(body, style: FincasText.metadata),
                  ],
                ),
              ),
              const SizedBox(width: FincasSpacing.s),
              const Icon(Icons.chevron_right, size: FincasIcons.regular, color: FincasColors.espresso),
            ],
          ),
        ),
      ),
    );
  }

  /// Status or notice with the matching actions underneath.
  Widget _statusScreen(String title, String body, List<Widget> actions, {FincasTone tone = FincasTone.neutral}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FincasMessageState(title: title, message: body, tone: tone),
        const SizedBox(height: FincasSpacing.xl),
        if (_errorMessage != null) Center(child: _errorText()),
        ...actions,
      ],
    );
  }

  static const _savedNote = 'Tu solicitud queda guardada. Para verla de nuevo, inicia sesión con esta misma cuenta.';

  Widget _formHeader(String title, String body) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(header: true, child: Text(title, style: FincasText.sectionTitle)),
        const SizedBox(height: FincasSpacing.xs),
        Text(body, style: FincasText.bodySecondary),
        const SizedBox(height: FincasSpacing.l),
      ],
    );
  }

  Widget _stepContent() {
    switch (_step) {
      case _Step.pending:
        return _statusScreen(
          'Cuenta en revisión',
          'Reconocimos tu correo. Falta que el administrador confirme tu acceso. Vuelve a intentarlo en unos minutos.',
          [FincasPrimaryButton(label: 'Usar otra cuenta', onPressed: _isLoading ? null : _backToSignIn)],
        );
      case _Step.onboarding:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Bienvenido a Fincas', textAlign: TextAlign.center, style: FincasText.sectionTitle),
            const SizedBox(height: FincasSpacing.xs),
            const Text('¿Cómo quieres empezar?', textAlign: TextAlign.center, style: FincasText.bodySecondary),
            const SizedBox(height: FincasSpacing.l),
            _option('Tengo un negocio', 'Quiero registrar mi negocio y manejar su operación.',
                () => setState(() { _step = _Step.ownerForm; _errorMessage = null; })),
            _option('Trabajo en un negocio', 'Ya pertenezco a un negocio y quiero unirme a su equipo.',
                () => setState(() { _step = _Step.enterCode; _errorMessage = null; })),
            _option('Estoy explorando', 'Todavía no quiero registrar ni unirme a un negocio.',
                () => setState(() { _step = _Step.explore; _errorMessage = null; })),
            FincasTextButton(label: 'Usar otra cuenta', onPressed: _isLoading ? null : _backToSignIn),
          ],
        );
      case _Step.ownerForm:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _formHeader('Registra tu negocio', 'El administrador de Fincas revisará tu solicitud antes de activar el negocio.'),
            _field(_bizNameController, 'Nombre del negocio', max: 80),
            _field(_bizCityController, 'Ciudad', max: 60),
            _errorText(),
            FincasPrimaryButton(label: 'Enviar solicitud', onPressed: _submitBusiness, loading: _isLoading),
            FincasTextButton(
              label: 'Volver',
              onPressed: _isLoading ? null : () => setState(() { _step = _Step.onboarding; _errorMessage = null; }),
            ),
          ],
        );
      case _Step.businessPending:
        return _statusScreen(
          'Solicitud enviada',
          _session != null && _session!.businessName.isNotEmpty
              ? 'Recibimos el registro de "${_session!.businessName}". El administrador de Fincas lo revisará y, cuando lo apruebe, '
                  'toca "Revisar estado" para entrar a tu negocio.'
              : 'Recibimos el registro de tu negocio. El administrador de Fincas lo revisará.',
          [
            FincasPrimaryButton(label: 'Revisar estado', onPressed: _refreshStatus, loading: _isLoading),
            FincasTextButton(label: 'Usar otra cuenta', onPressed: _isLoading ? null : _backToSignIn),
            const Text(_savedNote, textAlign: TextAlign.center, style: FincasText.caption),
          ],
        );
      case _Step.explore:
        return _statusScreen(
          'Fincas',
          'Fincas es una herramienta para negocios de café: pedidos, productos, clientes y tostado. '
              'Si solo quieres comprar, hazlo por WhatsApp con tu negocio. Vuelve cuando quieras registrar o unirte a uno.',
          [FincasPrimaryButton(label: 'Volver', onPressed: () => setState(() => _step = _Step.onboarding))],
        );
      case _Step.enterCode:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _formHeader('Código de invitación', 'Pídeselo al dueño del negocio. El dueño debe aprobar tu solicitud.'),
            Padding(
              padding: const EdgeInsets.only(bottom: FincasSpacing.field),
              child: TextField(
                controller: _codeController,
                textCapitalization: TextCapitalization.characters,
                maxLength: 9,
                onSubmitted: (_) => _submitCode(),
                decoration: const InputDecoration(labelText: 'Código', hintText: 'ABCD-EFGH', counterText: ''),
              ),
            ),
            _errorText(),
            FincasPrimaryButton(label: 'Enviar solicitud', onPressed: _submitCode, loading: _isLoading),
            FincasTextButton(
              label: 'Volver',
              onPressed: _isLoading ? null : () => setState(() { _step = _Step.onboarding; _errorMessage = null; }),
            ),
          ],
        );
      case _Step.joinPending:
        return _statusScreen(
          'Solicitud enviada',
          _session != null && _session!.businessName.isNotEmpty
              ? 'Esperando que el dueño de ${_session!.businessName} apruebe tu acceso.'
              : 'Esperando que el dueño del negocio apruebe tu acceso.',
          [
            FincasPrimaryButton(label: 'Revisar estado', onPressed: _refreshStatus, loading: _isLoading),
            FincasTextButton(label: 'Usar otra cuenta', onPressed: _isLoading ? null : _backToSignIn),
            const Text(_savedNote, textAlign: TextAlign.center, style: FincasText.caption),
          ],
        );
      case _Step.revoked:
        return _statusScreen(
          'Acceso bloqueado',
          'El acceso de esta cuenta fue desactivado. Contacta al administrador.',
          [FincasPrimaryButton(label: 'Usar otra cuenta', onPressed: _isLoading ? null : _backToSignIn)],
          tone: FincasTone.error,
        );
      case _Step.signIn:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_savedPending != null) _pendingReminder(),
            FincasSecondaryButton(label: 'Continuar con Google', onPressed: () => _signIn(AuthService.signInWithGoogle)),
            const SizedBox(height: FincasSpacing.m),
            FincasPrimaryButton(label: 'Continuar con Apple', onPressed: () => _signIn(AuthService.signInWithApple)),
            if (_errorMessage != null) ...[
              const SizedBox(height: FincasSpacing.m),
              Center(child: _errorText()),
            ],
          ],
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Checking a saved session or signing in: the loader sits right under the brand, as part of it.
    final loadingOnly = _step == _Step.signIn && (_checking || _isLoading);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: FincasTheme.statusBarOnLight,
      child: Scaffold(
      backgroundColor: FincasColors.background,
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        behavior: HitTestBehavior.translucent,
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.all(FincasSpacing.screenH),
              child: ConstrainedBox(
                // As wide as the screen so narrow content stays centered; as tall as the screen when there is room;
                // it scrolls when a form or the keyboard needs more height.
                constraints: BoxConstraints(
                  minWidth: constraints.maxWidth - FincasSpacing.screenH * 2,
                  minHeight: constraints.maxHeight - FincasSpacing.screenH * 2,
                ),
                child: IntrinsicHeight(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const Spacer(),
                      FincasBrandMark(logoSize: _step == _Step.signIn ? 104 : 80, showTagline: _step == _Step.signIn),
                      if (loadingOnly) ...[
                        const SizedBox(height: FincasSpacing.xxl),
                        FincasLoader(message: _checking ? 'Verificando tu sesión...' : 'Iniciando sesión...'),
                        const Spacer(),
                      ] else ...[
                        const Spacer(),
                        _stepContent(),
                        const SizedBox(height: FincasSpacing.xl),
                      ],
                    ],
                  ),
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
