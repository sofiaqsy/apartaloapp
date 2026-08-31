import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import '../services/notification_service.dart';
import 'main_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _phoneController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkExistingLogin());
  }

  Future<void> _checkExistingLogin() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final businessId = prefs.getString('business_id');
      final businessName = prefs.getString('business_name');

      if (businessId != null && businessName != null) {
        ApiService.isTostador = prefs.getBool('is_tostador') ?? false;
        await NotificationService().resendTokenAfterLogin();
        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => MainScreen(businessId: businessId, businessName: businessName),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('⚠️ Error verificando login: $e');
    }
  }

  Future<void> _login() async {
    final phone = _phoneController.text.trim();

    if (phone.isEmpty) {
      setState(() => _errorMessage = 'Ingresa tu número de WhatsApp');
      return;
    }
    if (phone.length < 9) {
      setState(() => _errorMessage = 'Número inválido');
      return;
    }

    setState(() { _isLoading = true; _errorMessage = null; });

    try {
      final result = await ApiService.buscarNegocioPorWhatsapp(phone);

      if (result['encontrado'] != true) {
        setState(() => _errorMessage = result['mensaje'] ?? 'Acceso no autorizado');
        return;
      }

      // Múltiples negocios → mostrar selector
      if (result['negocios'] != null) {
        final negocios = List<Map<String, dynamic>>.from(result['negocios']);
        if (!mounted) return;
        final seleccionado = await _mostrarSelectorNegocio(negocios);
        if (seleccionado == null) return;
        await _iniciarSesion(seleccionado);
      } else {
        await _iniciarSesion(result['negocio']);
      }
    } catch (e) {
      setState(() => _errorMessage = 'Error de conexión. Verifica tu internet.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _iniciarSesion(Map<String, dynamic> negocio) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('business_id', negocio['id']);
    await prefs.setString('business_name', negocio['nombre']);
    await prefs.setString('user_phone', _phoneController.text.trim());

    ApiService.businessId        = negocio['id'];
    ApiService.businessName      = negocio['nombre'] ?? '';
    ApiService.businessDireccion = negocio['direccion'] ?? '';
    ApiService.businessCiudad    = negocio['ciudad'] ?? '';
    ApiService.checkAndSetTostador(_phoneController.text.trim()).ignore();

    await NotificationService().resendTokenAfterLogin();

    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => MainScreen(
            businessId: negocio['id'],
            businessName: negocio['nombre'],
          ),
        ),
      );
    }
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
                  (n['nombre'] ?? '?')[0].toUpperCase(),
                  style: TextStyle(color: Colors.blue.shade700, fontWeight: FontWeight.bold),
                ),
              ),
              title: Text(n['nombre'] ?? '', style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: n['ciudad'] != null && (n['ciudad'] as String).isNotEmpty
                  ? Text(n['ciudad'])
                  : null,
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.pop(ctx, n),
            )),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        behavior: HitTestBehavior.translucent,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              children: [
                const Spacer(),

                // Logo
                ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: Image.asset(
                    'assets/splash/splash.png',
                    width: 100,
                    height: 100,
                    fit: BoxFit.cover,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Fincas',
                  style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.brown.shade800),
                ),
                const SizedBox(height: 8),
                Text(
                  'Gestiona tu negocio fácilmente',
                  style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
                ),

                const Spacer(),

                // Campo de teléfono
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Tu número de WhatsApp',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.grey.shade700),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: _errorMessage != null ? Colors.red.shade300 : Colors.transparent,
                          width: 2,
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade200,
                              borderRadius: const BorderRadius.only(
                                topLeft: Radius.circular(14),
                                bottomLeft: Radius.circular(14),
                              ),
                            ),
                            child: Row(
                              children: [
                                Image.network(
                                  'https://flagcdn.com/w40/pe.png',
                                  width: 24, height: 16,
                                  errorBuilder: (_, __, ___) => const Text('🇵🇪'),
                                ),
                                const SizedBox(width: 8),
                                Text('+51', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
                              ],
                            ),
                          ),
                          Expanded(
                            child: TextField(
                              controller: _phoneController,
                              keyboardType: TextInputType.phone,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                                LengthLimitingTextInputFormatter(9),
                              ],
                              decoration: const InputDecoration(
                                hintText: '999 888 777',
                                border: InputBorder.none,
                                contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 18),
                              ),
                              style: const TextStyle(fontSize: 18, letterSpacing: 1),
                              onSubmitted: (_) => _login(),
                            ),
                          ),
                        ],
                      ),
                    ),

                    if (_errorMessage != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.lock_outline, color: Colors.red.shade400, size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _errorMessage!,
                                style: TextStyle(color: Colors.red.shade700, fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),

                const SizedBox(height: 24),

                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _login,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF231e14),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      elevation: 0,
                    ),
                    child: _isLoading
                        ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Text('Continuar', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  ),
                ),

                const Spacer(),

                Text(
                  'Solo administradores autorizados pueden acceder',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }
}
