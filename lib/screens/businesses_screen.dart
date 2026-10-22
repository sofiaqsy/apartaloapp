import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../theme/fincas_tokens.dart';
import '../widgets/fincas_widgets.dart';

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

  /// Called when the person picks a business to enter. [context] belongs to this screen, which is
  /// still mounted (the page that opened it may already have been replaced).
  final Future<void> Function(BuildContext context, Map<String, dynamic> business, AuthSession session) onSelect;

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
    final code = await showDialog<String>(context: context, builder: (_) => const _JoinCodeDialog());
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
    final result = await showDialog<(String, String)>(context: context, builder: (_) => const _RegisterBusinessDialog());
    if (result == null) return;
    final businessName = result.$1.trim();
    final cityName = result.$2.trim();
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
    final canGoBack = Navigator.of(context).canPop();
    return Scaffold(
      backgroundColor: FincasColors.background,
      // Back arrow only when reached from the menu; after sign-in there is nothing to go back to.
      appBar: AppBar(
        toolbarHeight: canGoBack ? kToolbarHeight : 0,
        backgroundColor: Colors.transparent,
        centerTitle: false,
      ),
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          color: FincasColors.ink,
          onRefresh: _refresh,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(FincasSpacing.screenH, FincasSpacing.s, FincasSpacing.screenH, FincasSpacing.xxl),
            children: [
              if (_loading) const Padding(padding: EdgeInsets.only(bottom: FincasSpacing.m), child: LinearProgressIndicator(minHeight: 3)),
              // Header: greeting first, small; then the screen title.
              if (_session.fullName.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: FincasSpacing.xs),
                  child: Text('Hola, ${_session.fullName}', maxLines: 1, overflow: TextOverflow.ellipsis, style: FincasText.bodySecondary),
                ),
              Semantics(header: true, child: const Text('Tus negocios', style: FincasText.screenTitle)),
              const SizedBox(height: FincasSpacing.xl),
              if (_error != null) ...[
                FincasMessageState(title: 'No se pudo actualizar', message: _error!, tone: FincasTone.error),
                FincasTextButton(label: 'Reintentar', onPressed: _loading ? null : _refresh),
                const SizedBox(height: FincasSpacing.l),
              ],
              if (businesses.isEmpty && pending.isEmpty && _error == null)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: FincasSpacing.xl),
                  child: FincasMessageState(
                    title: 'Aún no tienes negocios',
                    message: 'Únete a uno con un código de invitación o registra el tuyo.',
                  ),
                ),
              ...businesses.map((b) => Padding(
                    padding: const EdgeInsets.only(bottom: FincasSpacing.m),
                    child: FincasBusinessCard(
                      name: (b['name'] ?? '').toString(),
                      city: (b['city'] ?? '').toString(),
                      roleLabel: _roleLabel((b['role'] ?? '').toString()),
                      isCurrent: b['businessId'] == widget.currentBusinessId,
                      onTap: _loading ? null : () => widget.onSelect(context, b, _session),
                    ),
                  )),
              if (pending.isNotEmpty) ...[
                const SizedBox(height: FincasSpacing.l),
                const FincasSectionHeader('En revisión'),
                ...pending.map((p) {
                  final isBusiness = p['kind'] == 'business';
                  final name = (p['businessName'] ?? '').toString();
                  return Padding(
                    padding: const EdgeInsets.only(bottom: FincasSpacing.m),
                    child: FincasCard(
                      tone: FincasTone.warning,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(name.isNotEmpty ? name : 'Solicitud para unirte a un negocio',
                              maxLines: 2, overflow: TextOverflow.ellipsis,
                              style: FincasText.sectionTitle.copyWith(color: FincasColors.warning)),
                          const SizedBox(height: FincasSpacing.xs),
                          Text(isBusiness ? 'Registro de negocio nuevo. Lo revisa el administrador.' : 'Falta que el dueño apruebe tu acceso.',
                              style: FincasText.metadata.copyWith(color: FincasColors.warning)),
                        ],
                      ),
                    ),
                  );
                }),
              ],
              const SizedBox(height: FincasSpacing.section),
              FincasSecondaryButton(label: 'Unirme a otro negocio', onPressed: _loading ? null : _joinWithCode),
              const SizedBox(height: FincasSpacing.s),
              FincasTextButton(label: 'Registrar un negocio nuevo', onPressed: _loading ? null : _registerBusiness),
            ],
          ),
        ),
      ),
    );
  }
}

/// Owns its controller, so it is disposed only when the dialog is really removed.
class _JoinCodeDialog extends StatefulWidget {
  const _JoinCodeDialog();

  @override
  State<_JoinCodeDialog> createState() => _JoinCodeDialogState();
}

class _JoinCodeDialogState extends State<_JoinCodeDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Unirme a otro negocio'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Pídele el código de invitación al dueño. Él debe aprobar tu solicitud.'),
          const SizedBox(height: FincasSpacing.m),
          TextField(
            controller: _controller,
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            maxLength: 9,
            decoration: const InputDecoration(labelText: 'Código', hintText: 'ABCD-EFGH', counterText: ''),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        ElevatedButton(onPressed: () => Navigator.pop(context, _controller.text.trim()), child: const Text('Enviar solicitud')),
      ],
    );
  }
}

class _RegisterBusinessDialog extends StatefulWidget {
  const _RegisterBusinessDialog();

  @override
  State<_RegisterBusinessDialog> createState() => _RegisterBusinessDialogState();
}

class _RegisterBusinessDialogState extends State<_RegisterBusinessDialog> {
  final _name = TextEditingController();
  final _city = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _city.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Registrar un negocio nuevo'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('El administrador de Fincas revisará tu solicitud antes de activarlo.'),
            const SizedBox(height: FincasSpacing.m),
            TextField(controller: _name, maxLength: 80, decoration: const InputDecoration(labelText: 'Nombre del negocio', counterText: '')),
            const SizedBox(height: FincasSpacing.field),
            TextField(controller: _city, maxLength: 60, decoration: const InputDecoration(labelText: 'Ciudad', counterText: '')),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        ElevatedButton(onPressed: () => Navigator.pop(context, (_name.text, _city.text)), child: const Text('Enviar solicitud')),
      ],
    );
  }
}
