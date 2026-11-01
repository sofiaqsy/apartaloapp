import 'package:flutter/cupertino.dart' show CupertinoPageRoute;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/administracion_service.dart';
import '../services/auth_service.dart';
import 'settings/settings_screen.dart';
import 'tabs/administracion_tab.dart' show MiAreaScreen, claveAreasElegidas;
import 'team_screen.dart';

const _nombresAreas = {
  'farm': 'Finca', 'sourcing': 'Compras', 'production': 'Producción', 'quality': 'Calidad', 'commercial': 'Comercial',
  'marketing': 'Marketing', 'fulfillment': 'Logística', 'people': 'Personas', 'finance': 'Finanzas', 'compliance': 'Cumplimiento',
  'risk': 'Riesgos', 'technology': 'Tecnología', 'strategy': 'Estrategia', 'shared': 'Compartido',
};

Future<T?> _abrir<T>(BuildContext context, Widget pantalla) =>
    Navigator.of(context).push<T>(CupertinoPageRoute(builder: (_) => pantalla));

/// Perfil: quién soy, mis áreas, Mi área, Equipo (sólo dueños) y Configuración.
class PerfilScreen extends StatefulWidget {
  const PerfilScreen({super.key, required this.businessId, required this.businessName, required this.esDueno});
  final String businessId;
  final String businessName;
  final bool esDueno;

  @override
  State<PerfilScreen> createState() => _PerfilScreenState();
}

class _PerfilScreenState extends State<PerfilScreen> {
  List<Map<String, dynamic>> _areas = [];
  final Set<String> _elegidas = {}; // las áreas marcadas, que Mi área muestra juntas
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final r = await AdministracionService.miArea();
    final guardadas = await _leerElegidas();
    if (!mounted) return;
    setState(() {
      _cargando = false;
      _areas = r.isSuccess ? ((r.data!['areas'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList() : [];
      final validas = _mias.map((a) => '${a['area']}').toSet();
      _elegidas
        ..clear()
        ..addAll(guardadas.where(validas.contains));
      // Sin nada guardado: la principal (o la primera).
      if (_elegidas.isEmpty && _mias.isNotEmpty) {
        _elegidas.add('${(_mias.firstWhere((a) => a['principal'] == true, orElse: () => _mias.first))['area']}');
      }
    });
  }

  /// Las áreas de la persona; los dueños sin áreas asignadas ven todas.
  List<Map<String, dynamic>> get _mias => _areas.any((a) => a['role'] == 'lead' || a['role'] == 'member')
      ? _areas.where((a) => a['role'] == 'lead' || a['role'] == 'member').toList()
      : _areas;

  static Future<List<String>> _leerElegidas() async {
    try {
      return (await SharedPreferences.getInstance()).getStringList(claveAreasElegidas) ?? [];
    } catch (_) {
      return [];
    }
  }

  /// Tocar un área la marca o la desmarca (no abre otra pantalla); siempre queda al menos una.
  Future<void> _alternar(String area) async {
    final nuevas = {..._elegidas};
    if (!nuevas.remove(area)) nuevas.add(area);
    if (nuevas.isEmpty) return;
    setState(() => _elegidas..clear()..addAll(nuevas));
    try {
      await (await SharedPreferences.getInstance()).setStringList(claveAreasElegidas, nuevas.toList());
    } catch (_) {}
  }

  String _iniciales(String texto) {
    final partes = texto.trim().split(RegExp(r'[\s@.]+')).where((p) => p.isNotEmpty).toList();
    return partes.take(2).map((p) => p[0].toUpperCase()).join();
  }

  @override
  Widget build(BuildContext context) {
    String? cuenta;
    try {
      cuenta = AuthService.currentName ?? AuthService.currentEmail;
    } catch (_) {
      cuenta = null; // sin sesión de Firebase (por ejemplo en pruebas)
    }
    final nombre = cuenta ?? 'Mi cuenta';
    final mias = _mias;
    final nombresElegidas = [for (final a in mias) if (_elegidas.contains('${a['area']}')) '${a['name']}'];
    return Scaffold(
      appBar: AppBar(title: const Text('Perfil')),
      body: RefreshIndicator(
        onRefresh: _cargar,
        child: ListView(
          children: [
            ListTile(
              leading: CircleAvatar(child: Text(_iniciales(nombre))),
              title: Text(nombre, style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text('${widget.businessName} · ${widget.esDueno ? 'Dueño' : 'Equipo'}'),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Text('Mis áreas', style: TextStyle(color: Colors.grey.shade700, fontWeight: FontWeight.w600)),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _cargando
                  ? const LinearProgressIndicator()
                  : mias.isEmpty
                      ? Text('Todavía no estás en ningún área. Administración te asigna una.', style: TextStyle(color: Colors.grey.shade600))
                      : Wrap(spacing: 8, runSpacing: 8, children: [
                          for (final a in mias)
                            FilterChip(
                              label: Text('${a['name']}${a['principal'] == true ? ' · principal' : ''}'),
                              selected: _elegidas.contains('${a['area']}'),
                              onSelected: (_) => _alternar('${a['area']}'),
                            ),
                        ]),
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.bar_chart),
              title: const Text('Mi área'),
              subtitle: Text(nombresElegidas.isEmpty ? 'Gastos por mes y los últimos' : nombresElegidas.join(' + '),
                  maxLines: 2, overflow: TextOverflow.ellipsis),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                await _abrir(context, MiAreaScreen(area: _elegidas.isEmpty ? null : _elegidas.join(',')));
                _cargar(); // Mi área pudo cambiar las marcadas
              },
            ),
            // Sólo dueños: para el equipo el botón no se muestra (no aparece deshabilitado).
            if (widget.esDueno)
              ListTile(
                leading: const Icon(Icons.groups),
                title: const Text('Equipo'),
                subtitle: const Text('Personas, sus áreas e invitaciones'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _abrir(context, EquipoScreen(businessId: widget.businessId, businessName: widget.businessName)),
              ),
            ListTile(
              leading: const Icon(Icons.settings),
              title: const Text('Configuración'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _abrir(context, SettingsScreen(businessName: widget.businessName)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Equipo (sólo dueños): cada persona con su rol y sus áreas; invitar y aprobar solicitudes.
class EquipoScreen extends StatefulWidget {
  const EquipoScreen({super.key, required this.businessId, required this.businessName});
  final String businessId;
  final String businessName;

  @override
  State<EquipoScreen> createState() => _EquipoScreenState();
}

class _EquipoScreenState extends State<EquipoScreen> {
  List<Map<String, dynamic>>? _equipo;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final r = await AdministracionService.equipo();
    if (!mounted) return;
    setState(() {
      _error = r.isSuccess ? null : r.error;
      _equipo = r.isSuccess ? ((r.data!['equipo'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList() : [];
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Equipo')),
      body: RefreshIndicator(
        onRefresh: _cargar,
        child: ListView(
          children: [
            ListTile(
              leading: const Icon(Icons.person_add_alt),
              title: const Text('Invitar y solicitudes'),
              subtitle: const Text('Código de invitación y personas que piden unirse'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                await _abrir(context, TeamScreen(businessId: widget.businessId, businessName: widget.businessName));
                _cargar();
              },
            ),
            const Divider(height: 1),
            if (_equipo == null) const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
            if (_error != null) Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center)),
            for (final p in _equipo ?? const <Map<String, dynamic>>[])
              ListTile(
                title: Text('${p['name']}'),
                subtitle: Text([
                  p['role'] == 'owner' ? 'Dueño' : 'Equipo',
                  ...((p['areas'] as List?) ?? []).map((a) => '${a['name']}${a['principal'] == true ? ' (principal)' : ''}'),
                ].join(' · '), maxLines: 2, overflow: TextOverflow.ellipsis),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  final guardado = await _abrir<bool>(context, AreasPersonaScreen(persona: p));
                  if (guardado == true) _cargar();
                },
              ),
          ],
        ),
      ),
    );
  }
}

/// "Áreas de …": una persona puede estar en dos o más áreas, con una principal. Las sugeridas vienen de lo
/// que registró en 60 días. Cerrar con la X no guarda nada.
class AreasPersonaScreen extends StatefulWidget {
  const AreasPersonaScreen({super.key, required this.persona});
  final Map<String, dynamic> persona;

  @override
  State<AreasPersonaScreen> createState() => _AreasPersonaScreenState();
}

class _AreasPersonaScreenState extends State<AreasPersonaScreen> {
  late final String _clave = AdministracionService.nuevaClave('areasPersona');
  final Set<String> _elegidas = {};
  final Map<String, int> _sugeridas = {}; // área -> registros en 60 días
  String? _principal;
  bool _guardando = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    for (final a in (widget.persona['areas'] as List?) ?? []) {
      _elegidas.add('${a['area']}');
      if (a['principal'] == true) _principal = '${a['area']}';
    }
    AdministracionService.sugerenciaAreas('${widget.persona['profile_id']}').then((r) {
      if (!mounted || !r.isSuccess) return;
      setState(() {
        for (final s in (r.data!['sugeridas'] as List?) ?? []) {
          _sugeridas['${s['area']}'] = int.tryParse('${s['records']}') ?? 0;
        }
        // Sin áreas todavía: se marcan las sugeridas; la que más registros tiene queda como principal.
        if (_elegidas.isEmpty && _sugeridas.isNotEmpty) {
          _elegidas.addAll(_sugeridas.keys);
          _principal = _sugeridas.keys.first;
        }
      });
    });
  }

  void _tocar(String area) => setState(() {
        if (_elegidas.remove(area)) {
          if (_principal == area) _principal = _elegidas.isEmpty ? null : _elegidas.first;
        } else {
          _elegidas.add(area);
          _principal ??= area;
        }
      });

  Future<void> _confirmar() async {
    setState(() { _guardando = true; _error = null; });
    final r = await AdministracionService.registrar('areasPersona', {
      'perfilId': widget.persona['profile_id'],
      'areas': _elegidas.toList(),
      if (_principal != null) 'principal': _principal,
    }, clave: _clave);
    if (!mounted) return;
    if (r.isSuccess) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Áreas de ${widget.persona['name']} guardadas ✓')));
      Navigator.of(context).pop(true);
    } else {
      setState(() { _guardando = false; _error = r.error; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.close), tooltip: 'Cerrar', onPressed: () => Navigator.of(context).pop(false)),
        title: Text('Áreas de ${widget.persona['name']}'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(_sugeridas.isEmpty ? 'Elige sus áreas. Puede tener dos o más.' : 'Sugeridas por lo que registró en 60 días. Puede tener dos o más.',
              style: TextStyle(color: Colors.grey.shade700)),
          const SizedBox(height: 12),
          for (final e in _nombresAreas.entries)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: Icon(_elegidas.contains(e.key) ? Icons.check_box : Icons.check_box_outline_blank,
                    color: _elegidas.contains(e.key) ? Colors.blue.shade700 : null),
                title: Text(e.value),
                subtitle: _sugeridas.containsKey(e.key) ? Text('Sugerida · ${_sugeridas[e.key]} registros') : null,
                trailing: !_elegidas.contains(e.key)
                    ? null
                    : _principal == e.key
                        ? Text('Principal', style: TextStyle(color: Colors.blue.shade700, fontWeight: FontWeight.w600))
                        : TextButton(onPressed: () => setState(() => _principal = e.key), child: const Text('Hacer principal')),
                onTap: () => _tocar(e.key),
              ),
            ),
          const SizedBox(height: 4),
          Text('El área marca dónde van sus gastos. No cambia su pago ni su rol.', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
          Text('Quién lo cubre: pendiente (las descripciones de rol se escriben hasta el 15 de enero).',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
          Text('Cada cambio queda guardado con quién lo hizo y cuándo.', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
          const SizedBox(height: 16),
          if (_error != null)
            Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(_error!, style: TextStyle(color: Colors.red.shade700))),
          FilledButton(onPressed: _guardando ? null : _confirmar, child: Text(_guardando ? 'Guardando…' : 'Confirmar')),
        ],
      ),
    );
  }
}
