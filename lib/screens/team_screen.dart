import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/auth_service.dart';

/// Owner-only: invite team members with a temporary code and approve join requests.
class TeamScreen extends StatefulWidget {
  const TeamScreen({super.key, required this.businessId, required this.businessName});

  final String businessId;
  final String businessName;

  @override
  State<TeamScreen> createState() => _TeamScreenState();
}

class _TeamScreenState extends State<TeamScreen> {
  List<Map<String, dynamic>> _requests = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final list = await AuthService.listJoinRequests(widget.businessId);
      if (mounted) setState(() => _requests = list);
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Error de conexión.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _createCode() async {
    try {
      final data = await AuthService.createJoinCode(widget.businessId);
      if (!mounted) return;
      final code = data['code'].toString();
      final expires = DateTime.tryParse(data['expiresAt'].toString())?.toLocal();
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Código de invitación'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: SelectableText(code,
                    style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, letterSpacing: 3)),
              ),
              const SizedBox(height: 12),
              Text('Úsalo una sola vez. Vence ${expires != null ? _fmt(expires) : 'en 48 horas'}. '
                  'Solo se muestra ahora; si lo pierdes, genera otro.'),
              const SizedBox(height: 8),
              const Text('Quien lo ingrese quedará pendiente hasta que lo apruebes aquí.'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Clipboard.setData(ClipboardData(text: code)),
              child: const Text('Copiar'),
            ),
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cerrar')),
          ],
        ),
      );
    } on AuthException catch (e) {
      _snack(e.message);
    } catch (_) {
      _snack('Error de conexión.');
    }
  }

  String _fmt(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  Future<void> _decide(Map<String, dynamic> r, bool approve) async {
    try {
      await AuthService.decideJoinRequest(widget.businessId, r['id'].toString(), approve);
      _snack(approve ? 'Solicitud aprobada' : 'Solicitud rechazada');
      await _load();
    } on AuthException catch (e) {
      _snack(e.message);
    } catch (_) {
      _snack('Error de conexión.');
    }
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Equipo - ${widget.businessName}')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            ElevatedButton(onPressed: _createCode, child: const Text('Generar código de invitación')),
            const SizedBox(height: 24),
            const Text('Solicitudes pendientes', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            if (_loading)
              const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
            else if (_error != null)
              Text(_error!, style: const TextStyle(color: Colors.red))
            else if (_requests.isEmpty)
              Text('No hay solicitudes.', style: TextStyle(color: Colors.grey.shade600))
            else
              ..._requests.map((r) => Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text((r['name'] ?? '').toString().isEmpty ? 'Sin nombre' : r['name'].toString(),
                              style: const TextStyle(fontWeight: FontWeight.w600)),
                          Text(r['email']?.toString() ?? '', style: TextStyle(color: Colors.grey.shade700)),
                          Text('Rol solicitado: ${r['role']}', style: TextStyle(color: Colors.grey.shade700)),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              TextButton(onPressed: () => _decide(r, false), child: const Text('Rechazar')),
                              const SizedBox(width: 8),
                              ElevatedButton(onPressed: () => _decide(r, true), child: const Text('Aprobar')),
                            ],
                          ),
                        ],
                      ),
                    ),
                  )),
          ],
        ),
      ),
    );
  }
}
