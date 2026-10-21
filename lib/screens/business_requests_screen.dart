import 'package:flutter/material.dart';
import '../services/auth_service.dart';

/// Platform admin only: approve or reject requests to register a new business.
class BusinessRequestsScreen extends StatefulWidget {
  const BusinessRequestsScreen({super.key});

  @override
  State<BusinessRequestsScreen> createState() => _BusinessRequestsScreenState();
}

class _BusinessRequestsScreenState extends State<BusinessRequestsScreen> {
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
      final list = await AuthService.listBusinessRequests();
      if (mounted) setState(() => _requests = list);
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Error de conexión.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _decide(Map<String, dynamic> r, bool approve) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(approve ? 'Aprobar negocio' : 'Rechazar solicitud'),
        content: Text(approve
            ? 'Se creará el negocio "${r['businessName']}" y ${r['email']} será su dueño.'
            : 'La solicitud de "${r['businessName']}" se marcará como rechazada.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: Text(approve ? 'Aprobar' : 'Rechazar')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await AuthService.decideBusinessRequest(r['id'].toString(), approve);
      _snack(approve ? 'Negocio creado' : 'Solicitud rechazada');
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
      appBar: AppBar(title: const Text('Solicitudes de negocios')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_loading)
              const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
            else if (_error != null)
              Text(_error!, style: const TextStyle(color: Colors.red))
            else if (_requests.isEmpty)
              Text('No hay solicitudes pendientes.', style: TextStyle(color: Colors.grey.shade600))
            else
              ..._requests.map((r) => Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(r['businessName'].toString(), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                          Text('${r['city']}  -  +${r['phone']}', style: TextStyle(color: Colors.grey.shade700)),
                          Text('${r['name']}  ${r['email']}', style: TextStyle(color: Colors.grey.shade700)),
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
