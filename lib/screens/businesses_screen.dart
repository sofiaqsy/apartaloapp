import 'package:flutter/material.dart';
import '../services/auth_service.dart';

/// "Tus negocios": the businesses of this account, the requests still in review, and the options
/// to join another business with a code or to register a new one.
class BusinessesScreen extends StatefulWidget {
  const BusinessesScreen({
    super.key,
    required this.session,
    required this.onSelect,
    this.currentBusinessId,
  });

  final AuthSession session;

  /// Called when the person picks a business to enter.
  final Future<void> Function(Map<String, dynamic> business, AuthSession session) onSelect;

  /// Business currently open (when this screen is reached from the menu).
  final String? currentBusinessId;

  @override
  State<BusinessesScreen> createState() => _BusinessesScreenState();
}

class _BusinessesScreenState extends State<BusinessesScreen> {
  late AuthSession _session = widget.session;
  bool _loading = false;
  String? _error;

  Future<void> _refresh() async {
    setState(() { _loading = true; _error = null; });
    try {
      final s = await AuthService.fetchSession();
      if (mounted) setState(() => _session = s);
    } catch (_) {
      if (mounted) setState(() => _error = 'No se pudo actualizar. Revisa tu internet.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text), duration: const Duration(seconds: 5)));
  }

  Future<void> _joinWithCode() async {
    final controller = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Unirme a otro negocio'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Pídele el código de invitación al dueño. Él debe aprobar tu solicitud.'),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              textCapitalization: TextCapitalization.characters,
              maxLength: 9,
              decoration: const InputDecoration(hintText: 'ABCD-EFGH', counterText: '', border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, controller.text.trim()), child: const Text('Enviar solicitud')),
        ],
      ),
    );
    controller.dispose();
    if (code == null || code.isEmpty) return;
    setState(() => _loading = true);
    try {
      final error = await AuthService.submitJoinCode(code);
      _snack(error ?? 'Solicitud enviada. El dueño del negocio debe aprobarla.');
      if (error == null) await _refresh();
    } catch (_) {
      _snack('Error de conexión.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _registerBusiness() async {
    final name = TextEditingController();
    final city = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Registrar un negocio nuevo'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('El administrador de Fincas revisará tu solicitud antes de activarlo.'),
            const SizedBox(height: 12),
            TextField(controller: name, maxLength: 80, decoration: const InputDecoration(labelText: 'Nombre del negocio', counterText: '', border: OutlineInputBorder())),
            const SizedBox(height: 10),
            TextField(controller: city, maxLength: 60, decoration: const InputDecoration(labelText: 'Ciudad', counterText: '', border: OutlineInputBorder())),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Enviar solicitud')),
        ],
      ),
    );
    final businessName = name.text.trim();
    final cityName = city.text.trim();
    name.dispose();
    city.dispose();
    if (ok != true) return;
    if (businessName.length < 3 || cityName.length < 2) {
      _snack('Escribe el nombre del negocio y la ciudad.');
      return;
    }
    setState(() => _loading = true);
    try {
      final error = await AuthService.requestBusiness(name: businessName, city: cityName);
      _snack(error ?? 'Solicitud enviada. Te avisaremos cuando tu negocio esté activo.');
      if (error == null) await _refresh();
    } catch (_) {
      _snack('Error de conexión.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _roleLabel(String role) => role == 'owner' ? 'Dueño' : (role == 'staff' ? 'Equipo' : role);

  @override
  Widget build(BuildContext context) {
    final businesses = _session.businesses;
    final pending = _session.pending;
    return Scaffold(
      appBar: AppBar(title: const Text('Tus negocios')),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_loading) const Padding(padding: EdgeInsets.only(bottom: 12), child: LinearProgressIndicator(minHeight: 3)),
            if (_error != null) Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(_error!, style: const TextStyle(color: Colors.red))),
            if (_session.fullName.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text('Hola, ${_session.fullName}', style: TextStyle(fontSize: 15, color: Colors.grey.shade700)),
              ),
            ...businesses.map((b) {
              final current = b['businessId'] == widget.currentBusinessId;
              return Card(
                child: ListTile(
                  title: Text((b['name'] ?? '').toString(), style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text([
                    if ((b['city'] ?? '').toString().isNotEmpty) b['city'],
                    _roleLabel((b['role'] ?? '').toString()),
                    if (current) 'Abierto ahora',
                  ].join('  -  ')),
                  trailing: const Text('Entrar'),
                  onTap: _loading ? null : () => widget.onSelect(b, _session),
                ),
              );
            }),
            if (pending.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Text('En revisión', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              ...pending.map((p) => Card(
                    color: Colors.amber.shade50,
                    child: ListTile(
                      title: Text(p['businessName']?.toString().isNotEmpty == true ? p['businessName'].toString() : 'Solicitud para unirte a un negocio'),
                      subtitle: Text(p['kind'] == 'business' ? 'Registro de negocio nuevo, lo revisa el administrador' : 'Falta que el dueño apruebe tu acceso'),
                    ),
                  )),
            ],
            const SizedBox(height: 24),
            OutlinedButton(onPressed: _loading ? null : _joinWithCode, child: const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('Unirme a otro negocio'))),
            const SizedBox(height: 10),
            OutlinedButton(onPressed: _loading ? null : _registerBusiness, child: const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('Registrar un negocio nuevo'))),
          ],
        ),
      ),
    );
  }
}
