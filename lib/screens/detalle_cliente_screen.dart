import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import '../services/api_service.dart';
import 'crear_pedido_screen.dart';
import 'tabs/pedidos/widgets/detalle_pedido/detalle_pedido_sheet.dart';

class DetalleClienteScreen extends StatefulWidget {
  final Map<String, dynamic>? cliente;

  const DetalleClienteScreen({super.key, this.cliente});

  @override
  State<DetalleClienteScreen> createState() => _DetalleClienteScreenState();
}

class _DetalleClienteScreenState extends State<DetalleClienteScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  bool _hasChanges = false;

  // Feature flags del negocio
  bool _preciosPersonalizadosEnabled = true;

  // Stats calculados desde pedidos reales
  Map<String, dynamic> _stats = {};
  bool _statsLoading = false;

  // Direcciones guardadas en customer_addresses
  List<Map<String, dynamic>> _direcciones = [];
  bool _direccionesLoading = false;

  // Controladores
  late TextEditingController _whatsappController;
  late TextEditingController _nombreNegocioController;
  late TextEditingController _nombreResponsableController;
  late TextEditingController _telefonoController;
  late TextEditingController _emailController;
  late TextEditingController _empresaEnvioController;
  late TextEditingController _localEnvioController;
  late TextEditingController _direccionEnvioController;
  late TextEditingController _distritoEnvioController;
  late TextEditingController _departamentoEnvioController;
  late TextEditingController _sedeEnvioController;
  late TextEditingController _notasController;

  String _estado = 'ACTIVO';
  String _tipoEnvio = '';
  bool _esInterno = false;

  // Estado de la conversación Firestore
  bool _botLoading = false;

  bool get _esNuevo => widget.cliente == null;

  String get _nombreCliente {
    final negocio = _nombreNegocioController.text.trim();
    final responsable = _nombreResponsableController.text.trim();
    if (negocio.isNotEmpty) return negocio;
    if (responsable.isNotEmpty) return responsable;
    return 'Cliente';
  }

  String get _whatsappLimpio {
    return _whatsappController.text.trim().replaceAll(RegExp(r'[^0-9]'), '');
  }

  @override
  void initState() {
    super.initState();
    _initControllers();
    if (!_esNuevo) {
      _cargarEstadisticas();
      _cargarDirecciones();
    }
  }

  bool get _esInvitado => widget.cliente?['id'] == 'guest';

  Future<void> _cargarEstadisticas() async {
    if (_esNuevo || _esInvitado) return;
    setState(() => _statsLoading = true);

    try {
      final clienteId = widget.cliente!['id'] as String;
      final response = await http.get(
        Uri.parse('${ApiService.baseUrl}/api/clientes/${ApiService.businessId}/$clienteId'),
        headers: ApiService.headers,
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200 && mounted) {
        final data = jsonDecode(response.body);
        final c = Map<String, dynamic>.from(data['cliente'] ?? {});
        setState(() {
          _stats = Map<String, dynamic>.from(data['estadisticas'] ?? {});
          _statsLoading = false;
          if (c.isNotEmpty) {
            if ((c['nombreResponsable'] ?? '').toString().isNotEmpty)
              _nombreResponsableController.text = c['nombreResponsable'];
            if ((c['nombreNegocio'] ?? '').toString().isNotEmpty)
              _nombreNegocioController.text = c['nombreNegocio'];
            if ((c['whatsapp'] ?? c['telefono'] ?? '').toString().isNotEmpty)
              _whatsappController.text = c['whatsapp'] ?? c['telefono'] ?? '';
            if ((c['telefono'] ?? '').toString().isNotEmpty)
              _telefonoController.text = c['telefono'];
            if ((c['email'] ?? '').toString().isNotEmpty)
              _emailController.text = c['email'];
            if ((c['direccionEnvio'] ?? '').toString().isNotEmpty)
              _direccionEnvioController.text = c['direccionEnvio'];
            if ((c['distritoEnvio'] ?? '').toString().isNotEmpty)
              _distritoEnvioController.text = c['distritoEnvio'];
            if ((c['departamentoEnvio'] ?? '').toString().isNotEmpty)
              _departamentoEnvioController.text = c['departamentoEnvio'];
            if ((c['empresaEnvio'] ?? '').toString().isNotEmpty)
              _empresaEnvioController.text = c['empresaEnvio'];
            if ((c['localEnvio'] ?? '').toString().isNotEmpty)
              _localEnvioController.text = c['localEnvio'];
            if ((c['notas'] ?? '').toString().isNotEmpty)
              _notasController.text = c['notas'];
            if ((c['tipoEnvio'] ?? '').toString().isNotEmpty)
              _tipoEnvio = c['tipoEnvio'];
            if ((c['estado'] ?? '').toString().isNotEmpty)
              _estado = c['estado'];
          }
        });
      } else {
        setState(() => _statsLoading = false);
      }
    } catch (e) {
      if (mounted) setState(() => _statsLoading = false);
    }
  }

  void _initControllers() {
    final c = widget.cliente ?? {};

    _whatsappController = TextEditingController(text: c['whatsapp'] ?? '');
    _nombreNegocioController = TextEditingController(text: c['nombreNegocio'] ?? c['nombre'] ?? '');
    _nombreResponsableController = TextEditingController(text: c['nombreResponsable'] ?? '');
    _telefonoController = TextEditingController(text: c['telefono'] ?? '');
    _emailController = TextEditingController(text: c['email'] ?? '');
    _empresaEnvioController = TextEditingController(text: c['empresaEnvio'] ?? '');
    _localEnvioController = TextEditingController(text: c['localEnvio'] ?? '');
    _direccionEnvioController = TextEditingController(text: c['direccionEnvio'] ?? '');
    _distritoEnvioController = TextEditingController(text: c['distritoEnvio'] ?? '');
    _departamentoEnvioController = TextEditingController(text: c['departamentoEnvio'] ?? '');
    _sedeEnvioController = TextEditingController(text: c['localEnvio'] ?? c['sedeEnvio'] ?? '');
    _notasController = TextEditingController(text: c['notas'] ?? '');

    _estado = c['estado'] ?? 'ACTIVO';
    _tipoEnvio = c['tipoEnvio'] ?? '';
    _esInterno = c['esInterno'] == true || c['esInterno'] == 'true';

    final controllers = [
      _whatsappController, _nombreNegocioController, _nombreResponsableController,
      _telefonoController, _emailController, _empresaEnvioController,
      _localEnvioController, _direccionEnvioController, _distritoEnvioController,
      _departamentoEnvioController, _sedeEnvioController, _notasController
    ];
    for (final ctrl in controllers) {
      ctrl.addListener(() {
        if (!_hasChanges) setState(() => _hasChanges = true);
      });
    }
  }

  Future<void> _cargarDirecciones() async {
    final clienteId = widget.cliente?['id'] as String?;
    if (clienteId == null || clienteId.isEmpty || clienteId == 'guest') return;
    setState(() => _direccionesLoading = true);
    try {
      final response = await http.get(
        Uri.parse('${ApiService.baseUrl}/api/clientes/${ApiService.businessId}/$clienteId/addresses'),
        headers: ApiService.headers,
      ).timeout(const Duration(seconds: 15));
      if (response.statusCode == 200 && mounted) {
        final data = jsonDecode(response.body);
        setState(() {
          _direcciones = List<Map<String, dynamic>>.from(data['addresses'] ?? []);
        });
      }
    } catch (_) {}
    if (mounted) setState(() => _direccionesLoading = false);
  }

  // ==================== ACCIONES ====================

  Future<void> _abrirWhatsApp({String? mensaje}) async {
    final whatsapp = _whatsappLimpio;
    if (whatsapp.isEmpty) {
      _showSnack('No hay número de WhatsApp', Colors.orange);
      return;
    }

    String url = 'https://wa.me/$whatsapp';
    if (mensaje != null && mensaje.isNotEmpty) {
      url += '?text=${Uri.encodeComponent(mensaje)}';
    }

    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      _showSnack('No se pudo abrir WhatsApp', Colors.red);
    }
  }

  void _compartirLinkB2B() {
    final whatsapp = _whatsappLimpio;
    if (whatsapp.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This client has no WhatsApp number')),
      );
      return;
    }
    final link = 'https://fincarosal.com/b2b/$whatsapp';
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(link, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500), textAlign: TextAlign.center),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.copy, color: Colors.blue),
              title: const Text('Copy link'),
              onTap: () {
                Clipboard.setData(ClipboardData(text: link));
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Link copied to clipboard')),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.chat, color: Colors.green),
              title: const Text('Send via WhatsApp'),
              onTap: () async {
                Navigator.pop(ctx);
                final msg = Uri.encodeComponent('Hi! Here is your personal ordering link: $link');
                final url = 'https://wa.me/$whatsapp?text=$msg';
                if (await canLaunchUrl(Uri.parse(url))) {
                  await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
                }
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _enviarMensajeRapido() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _MensajeRapidoSheet(
        nombreCliente: _nombreCliente,
        onEnviar: (mensaje) {
          Navigator.pop(context);
          _abrirWhatsApp(mensaje: mensaje);
        },
      ),
    );
  }

  Future<void> _registrarPedido() async {
    final nuevoPedido = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (_) => CrearPedidoScreen(cliente: widget.cliente),
      ),
    );
    if (!mounted) return;
    if (nuevoPedido != null) {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (ctx) => DetallePedidoSheet(
          pedido: nuevoPedido,
          onActualizado: () {},
        ),
      );
    }
  }

  void _configurarPrecios() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _PreciosPersonalizadosSheet(
        clienteId: widget.cliente?['id'] ?? '',
        nombreCliente: _nombreCliente,
      ),
    );
  }


  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    final datos = {
      'whatsapp': _whatsappController.text.trim(),
      'nombreNegocio': _nombreNegocioController.text.trim(),
      'nombreResponsable': _nombreResponsableController.text.trim(),
      'telefono': _telefonoController.text.trim(),
      'email': _emailController.text.trim(),
      'estado': _estado,
      'tipoEnvio': _tipoEnvio,
      'empresaEnvio': _empresaEnvioController.text.trim(),
      // SEDE usa _sedeEnvioController, NACIONAL usa _localEnvioController — ambos van a col R (localEnvio)
      'localEnvio': _tipoEnvio == 'SEDE'
          ? _sedeEnvioController.text.trim()
          : _localEnvioController.text.trim(),
      'direccionEnvio': _direccionEnvioController.text.trim(),
      'distritoEnvio': _distritoEnvioController.text.trim(),
      'departamentoEnvio': _departamentoEnvioController.text.trim(),
      'notas': _notasController.text.trim(),
      'esInterno': _esInterno,
    };

    final result = _esNuevo
        ? await ApiService.crearCliente(datos: datos)
        : await ApiService.actualizarCliente(clienteId: widget.cliente!['id'], datos: datos);

    setState(() => _isLoading = false);

    if (result.isSuccess && mounted) {
      _showSnack(_esNuevo ? '✅ Cliente creado' : '✅ Cliente actualizado', Colors.green);
      Navigator.pop(context, true);
    } else {
      _showSnack('Error: ${result.error}', Colors.red);
    }
  }

  void _showSnack(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: color),
    );
  }

  Future<void> _confirmarDescartarCambios() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Descartar cambios?'),
        content: const Text('Tienes cambios sin guardar.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Descartar', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if ((result ?? false) && mounted) Navigator.pop(context);
  }

  Color _getEstadoColor(String estado) {
    switch (estado) {
      case 'ACTIVO': return Colors.green;
      case 'INACTIVO': return Colors.grey;
      case 'PROSPECTO': return Colors.orange;
      default: return Colors.blue;
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_hasChanges,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmarDescartarCambios();
      },
      child: Scaffold(
        backgroundColor: Colors.grey.shade100,
        body: GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(),
          behavior: HitTestBehavior.translucent,
          child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : CustomScrollView(
                slivers: [
                  _buildSliverAppBar(),
                  SliverToBoxAdapter(
                    child: Form(
                      key: _formKey,
                      child: Column(
                        children: [
                          if (!_esNuevo) _buildAccionesRapidas(),
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              children: [
                                _buildSeccionDatos(),
                                const SizedBox(height: 16),
                                if (!_esNuevo) ...[
                                  _buildSeccionDirecciones(),
                                  const SizedBox(height: 16),
                                ],
                                _buildSeccionEnvio(),
                                if (!_esNuevo) ...[
                                  const SizedBox(height: 16),
                                  _buildSeccionEstadisticas(),
                                ],
                                const SizedBox(height: 16),
                                _buildSeccionNotas(),
                                const SizedBox(height: 100),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
          ),
        floatingActionButton: _hasChanges
            ? FloatingActionButton.extended(
                heroTag: 'fab_guardar_cliente',
                onPressed: _guardar,
                backgroundColor: Colors.green.shade600,
                icon: Icon(_esNuevo ? Icons.person_add : Icons.save),
                label: Text(_esNuevo ? 'Crear' : 'Guardar'),
              )
            : null,
      ),
    );
  }

  Widget _buildSliverAppBar() {
    return SliverAppBar(
      expandedHeight: _esNuevo ? 0 : 100,
      pinned: true,
      backgroundColor: Colors.green.shade600,
      foregroundColor: Colors.white,
      flexibleSpace: _esNuevo
          ? null
          : FlexibleSpaceBar(
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.green.shade700, Colors.green.shade500],
                  ),
                ),
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(19),
                          ),
                          child: Center(
                            child: Text(
                              _nombreCliente.isNotEmpty ? _nombreCliente[0].toUpperCase() : '?',
                              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.white),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _nombreCliente,
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: _getEstadoColor(_estado).withOpacity(0.3),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      _estado,
                                      style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    _whatsappController.text,
                                    style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.9)),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
      title: Text(_esNuevo ? 'Nuevo Cliente' : ''),
    );
  }

  Widget _buildAccionesRapidas() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: Colors.white,
      child: Row(
        children: [
          _buildAccionBtn(
            icon: Icons.chat,
            label: 'WhatsApp',
            color: Colors.green,
            onTap: _enviarMensajeRapido,
          ),
          const SizedBox(width: 12),
          _buildAccionBtn(
            icon: Icons.add_shopping_cart,
            label: 'Pedido',
            color: Colors.blue,
            onTap: _registrarPedido,
          ),
          if (_preciosPersonalizadosEnabled) ...[
            const SizedBox(width: 12),
            _buildAccionBtn(
              icon: Icons.sell,
              label: 'Precios',
              color: Colors.orange,
              onTap: _configurarPrecios,
            ),
          ],
          const SizedBox(width: 12),
          _buildAccionBtn(
            icon: Icons.link,
            label: 'B2B',
            color: Colors.teal,
            onTap: _compartirLinkB2B,
          ),
        ],
      ),
    );
  }

  Widget _buildAccionBtn({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: Material(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Column(
              children: [
                Icon(icon, color: color, size: 22),
                const SizedBox(height: 4),
                Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSeccionDatos() {
    return _buildSeccion(
      titulo: 'Datos del Cliente',
      icon: Icons.person,
      children: [
        _buildCampo(label: 'WhatsApp *', controller: _whatsappController, hint: '51999888777', icon: Icons.phone, keyboard: TextInputType.phone, validator: (v) => v == null || v.isEmpty ? 'Requerido' : null),
        _buildCampo(label: 'Nombre del Negocio', controller: _nombreNegocioController, hint: 'Café Aromático', icon: Icons.store),
        _buildCampo(label: 'Responsable', controller: _nombreResponsableController, hint: 'Juan Pérez', icon: Icons.badge),
        _buildCampo(label: 'Teléfono', controller: _telefonoController, hint: '01 234 5678', icon: Icons.phone_android, keyboard: TextInputType.phone),
        _buildCampo(label: 'Email', controller: _emailController, hint: 'correo@ejemplo.com', icon: Icons.email, keyboard: TextInputType.emailAddress),
        const SizedBox(height: 8),
        const Text('Estado', style: TextStyle(fontWeight: FontWeight.w500, fontSize: 13)),
        const SizedBox(height: 8),
        Row(
          children: ['ACTIVO', 'PROSPECTO', 'INACTIVO'].map((e) => Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(e, style: TextStyle(fontSize: 12, color: _estado == e ? Colors.white : _getEstadoColor(e))),
              selected: _estado == e,
              selectedColor: _getEstadoColor(e),
              backgroundColor: _getEstadoColor(e).withOpacity(0.1),
              onSelected: (_) => setState(() { _estado = e; _hasChanges = true; }),
            ),
          )).toList(),
        ),
        const SizedBox(height: 12),
        GestureDetector(
          onTap: () => setState(() { _esInterno = !_esInterno; _hasChanges = true; }),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: _esInterno ? Colors.blueGrey.shade50 : Colors.grey.shade50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: _esInterno ? Colors.blueGrey.shade300 : Colors.grey.shade200,
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.business_center,
                    size: 18,
                    color: _esInterno ? Colors.blueGrey.shade600 : Colors.grey.shade400),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Cliente Interno',
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: _esInterno ? Colors.blueGrey.shade700 : Colors.grey.shade600)),
                      Text('Sus pedidos no generan cobro (consumo propio)',
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                    ],
                  ),
                ),
                Switch(
                  value: _esInterno,
                  onChanged: (v) => setState(() { _esInterno = v; _hasChanges = true; }),
                  activeColor: Colors.blueGrey.shade600,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _mostrarFormularioDireccion() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AgregarDireccionSheet(
        clienteId: widget.cliente!['id'] as String,
        esPrimaria: _direcciones.isEmpty,
        onGuardado: (nuevaDireccion) {
          setState(() => _direcciones.add(nuevaDireccion));
        },
      ),
    );
  }

  Widget _buildDireccionCard(Map<String, dynamic> addr) {
    final isPrimary = addr['is_primary'] == true;
    final alias = (addr['alias'] ?? '').toString();
    final addressLine = (addr['address_line'] ?? '').toString();
    final district = (addr['district'] ?? '').toString();
    final department = (addr['department'] ?? '').toString();
    final reference = (addr['reference'] ?? '').toString();
    final courier = addr['customer_address_courier'];

    final partes = [addressLine, district, department]
        .where((s) => s.isNotEmpty)
        .toList();

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isPrimary ? Colors.blue.shade50 : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isPrimary ? Colors.blue.shade200 : Colors.grey.shade200,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isPrimary ? Icons.home_rounded : Icons.location_on_outlined,
                size: 16,
                color: isPrimary ? Colors.blue.shade600 : Colors.grey.shade500,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  alias.isNotEmpty ? alias : (isPrimary ? 'Principal' : 'Dirección'),
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: isPrimary ? Colors.blue.shade700 : Colors.grey.shade700,
                  ),
                ),
              ),
              if (isPrimary)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade600,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text('PRINCIPAL', style: TextStyle(fontSize: 9, color: Colors.white, fontWeight: FontWeight.bold)),
                ),
            ],
          ),
          if (partes.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(partes.join(', '), style: const TextStyle(fontSize: 13)),
          ],
          if (reference.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              'Ref: $reference',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontStyle: FontStyle.italic),
            ),
          ],
          if (courier != null) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(Icons.local_shipping_outlined, size: 14, color: Colors.purple.shade400),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    '${courier['courier_name'] ?? ''} — ${courier['agency_name'] ?? ''}',
                    style: TextStyle(fontSize: 12, color: Colors.purple.shade700),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSeccionDirecciones() {
    return _buildSeccion(
      titulo: 'Direcciones',
      icon: Icons.pin_drop_rounded,
      children: [
        if (_direccionesLoading)
          const Center(child: Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: CircularProgressIndicator(strokeWidth: 2),
          ))
        else if (_direcciones.isEmpty && _esInvitado && _direccionEnvioController.text.trim().isNotEmpty)
          _buildDireccionCard({
            'address_line': _direccionEnvioController.text.trim(),
            'district':     _distritoEnvioController.text.trim(),
            'department':   _departamentoEnvioController.text.trim(),
            'reference':    (widget.cliente?['referencia'] ?? '').toString(),
            'alias':        'Dirección de entrega',
            'is_primary':   true,
          })
        else if (_direcciones.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(
              'Sin direcciones registradas',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
            ),
          )
        else
          ..._direcciones.map(_buildDireccionCard),

        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _mostrarFormularioDireccion,
          icon: const Icon(Icons.add_location_alt_outlined, size: 18),
          label: const Text('Agregar dirección'),
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.blue.shade600,
            side: BorderSide(color: Colors.blue.shade300),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
          ),
        ),
      ],
    );
  }

  Widget _buildSeccionEnvio() {
    return _buildSeccion(
      titulo: 'Datos de Envío',
      icon: Icons.local_shipping,
      children: [
        const Text('Tipo de Envío', style: TextStyle(fontWeight: FontWeight.w500, fontSize: 13)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            ChoiceChip(
              label: Text('LOCAL', style: TextStyle(fontSize: 12, color: _tipoEnvio == 'LOCAL' ? Colors.white : Colors.blue)),
              selected: _tipoEnvio == 'LOCAL',
              selectedColor: Colors.blue,
              backgroundColor: Colors.blue.withOpacity(0.1),
              onSelected: (_) => setState(() { _tipoEnvio = _tipoEnvio == 'LOCAL' ? '' : 'LOCAL'; _hasChanges = true; }),
            ),
            ChoiceChip(
              label: Text('NACIONAL', style: TextStyle(fontSize: 12, color: _tipoEnvio == 'NACIONAL' ? Colors.white : Colors.purple)),
              selected: _tipoEnvio == 'NACIONAL',
              selectedColor: Colors.purple,
              backgroundColor: Colors.purple.withOpacity(0.1),
              onSelected: (_) => setState(() { _tipoEnvio = _tipoEnvio == 'NACIONAL' ? '' : 'NACIONAL'; _hasChanges = true; }),
            ),
            ChoiceChip(
              label: Text('SEDE', style: TextStyle(fontSize: 12, color: _tipoEnvio == 'SEDE' ? Colors.white : Colors.teal)),
              selected: _tipoEnvio == 'SEDE',
              selectedColor: Colors.teal,
              backgroundColor: Colors.teal.withOpacity(0.1),
              onSelected: (_) => setState(() { _tipoEnvio = _tipoEnvio == 'SEDE' ? '' : 'SEDE'; _hasChanges = true; }),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // ── SEDE: sólo punto de recojo ──
        if (_tipoEnvio == 'SEDE') ...[
          _buildCampo(
            label: 'Punto de recojo',
            controller: _sedeEnvioController,
            hint: 'Ej: Jr. Lima 456, Cercado de Lima',
            icon: Icons.store_mall_directory,
          ),
        ],

        // ── NACIONAL: datos de courier ──
        if (_tipoEnvio == 'NACIONAL') ...[
          _buildCampo(label: 'Empresa courier', controller: _empresaEnvioController, hint: 'Shalom, Olva, Serpost…', icon: Icons.business),
          _buildCampo(label: 'Local/Agencia', controller: _localEnvioController, hint: 'Lima Centro', icon: Icons.storefront),
          _buildCampo(label: 'Dirección de agencia', controller: _direccionEnvioController, hint: 'Av. Grau 123', icon: Icons.place),
          Row(
            children: [
              Expanded(child: _buildCampo(label: 'Distrito', controller: _distritoEnvioController, hint: 'Cercado')),
              const SizedBox(width: 12),
              Expanded(child: _buildCampo(label: 'Depto.', controller: _departamentoEnvioController, hint: 'Lima')),
            ],
          ),
        ],

        // ── LOCAL: entrega a domicilio, sin campos extra ──
        if (_tipoEnvio == 'LOCAL') ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.blue.shade100),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 16, color: Colors.blue.shade400),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Se usará la dirección registrada en Ubicación para la entrega.',
                    style: TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildSeccionEstadisticas() {
    if (_statsLoading) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
        child: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: CircularProgressIndicator(),
          ),
        ),
      );
    }

    final totalPedidos = _stats['totalPedidos'] ?? widget.cliente?['totalPedidos'] ?? 0;
    final totalComprado = (_stats['totalComprado'] ?? widget.cliente?['totalComprado'] ?? 0).toDouble();
    final totalCobrado = (_stats['totalCobrado'] ?? 0).toDouble();
    final totalPorCobrar = (_stats['totalPorCobrar'] ?? widget.cliente?['totalPorCobrar'] ?? 0).toDouble();
    final totalKg = (_stats['totalKg'] ?? widget.cliente?['totalKg'] ?? 0).toDouble();
    final pedidosActivos = _stats['pedidosActivos'] ?? widget.cliente?['pedidosActivos'] ?? 0;
    final pedidosPorCobrar = _stats['pedidosPorCobrar'] ?? 0;
    final pedidosPagados = _stats['pedidosPagados'] ?? 0;
    final ultimaCompra = _stats['ultimaCompra'] ?? widget.cliente?['ultimaCompra'] ?? '';
    final fechaRegistro = widget.cliente?['fechaRegistro'] ?? '-';

    return _buildSeccion(
      titulo: 'Estadísticas',
      icon: Icons.bar_chart,
      children: [
        // Resumen visual de pagos
        if (totalComprado > 0) ...[  
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.indigo.shade50, Colors.blue.shade50],
              ),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.indigo.shade100),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _buildMiniStat('Vendido', 'S/ ${totalComprado.toStringAsFixed(0)}', Colors.indigo),
                ),
                Container(width: 1, height: 36, color: Colors.indigo.shade200),
                Expanded(
                  child: _buildMiniStat('Cobrado', 'S/ ${totalCobrado.toStringAsFixed(0)}', Colors.green),
                ),
                Container(width: 1, height: 36, color: Colors.indigo.shade200),
                Expanded(
                  child: _buildMiniStat(
                    'Por cobrar',
                    'S/ ${totalPorCobrar.toStringAsFixed(0)}',
                    totalPorCobrar > 0 ? Colors.red : Colors.grey,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
        _buildStatItem('Total Pedidos', '$totalPedidos', Icons.shopping_bag),
        if (pedidosActivos > 0)
          _buildStatItem('Pedidos Activos', '$pedidosActivos', Icons.pending_actions, color: Colors.orange),
        if (pedidosPorCobrar > 0)
          _buildStatItem('Pedidos por Cobrar', '$pedidosPorCobrar', Icons.warning_amber_rounded, color: Colors.red),
        if (pedidosPagados > 0)
          _buildStatItem('Pedidos Pagados', '$pedidosPagados', Icons.check_circle, color: Colors.green),
        if (totalKg > 0)
          _buildStatItem('Total Kg', '${totalKg.toStringAsFixed(1)} kg', Icons.scale),
        _buildStatItem('Última Compra', ultimaCompra.isNotEmpty ? ultimaCompra : 'Sin compras', Icons.calendar_today),
        _buildStatItem('Registrado', fechaRegistro, Icons.event),
      ],
    );
  }

  Widget _buildMiniStat(String label, String value, Color color) {
    return Column(
      children: [
        Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: color),
        ),
      ],
    );
  }

  /// Sección de chat con Firestore (tiempo real)
  Widget _buildSeccionNotas() {
    return _buildSeccion(
      titulo: 'Notas',
      icon: Icons.note,
      children: [
        _buildCampo(label: '', controller: _notasController, hint: 'Observaciones sobre el cliente...', maxLines: 3),
      ],
    );
  }

  Widget _buildSeccion({required String titulo, required IconData icon, required List<Widget> children}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: Colors.green.shade600),
              const SizedBox(width: 8),
              Text(titulo, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey.shade800)),
            ],
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }

  Widget _buildCampo({
    required String label,
    required TextEditingController controller,
    String? hint,
    IconData? icon,
    TextInputType? keyboard,
    int maxLines = 1,
    String? Function(String?)? validator,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (label.isNotEmpty) ...[
            Text(label, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13)),
            const SizedBox(height: 6),
          ],
          TextFormField(
            controller: controller,
            keyboardType: keyboard,
            maxLines: maxLines,
            validator: validator,
            style: const TextStyle(fontSize: 15),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
              prefixIcon: icon != null ? Icon(icon, size: 18, color: Colors.grey.shade400) : null,
              filled: true,
              fillColor: Colors.grey.shade50,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.shade300)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.shade300)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.green.shade400, width: 1.5)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value, IconData icon, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color ?? Colors.grey.shade500),
          const SizedBox(width: 12),
          Text(label, style: TextStyle(color: Colors.grey.shade600, fontSize: 14)),
          const Spacer(),
          Text(value, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: color)),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _whatsappController.dispose();
    _nombreNegocioController.dispose();
    _nombreResponsableController.dispose();
    _telefonoController.dispose();
    _emailController.dispose();
    _empresaEnvioController.dispose();
    _localEnvioController.dispose();
    _direccionEnvioController.dispose();
    _distritoEnvioController.dispose();
    _departamentoEnvioController.dispose();
    _notasController.dispose();
    super.dispose();
  }
}

// ==================== SHEETS MODALES ====================

class _MensajeRapidoSheet extends StatefulWidget {
  final String nombreCliente;
  final Function(String) onEnviar;

  const _MensajeRapidoSheet({required this.nombreCliente, required this.onEnviar});

  @override
  State<_MensajeRapidoSheet> createState() => _MensajeRapidoSheetState();
}

class _MensajeRapidoSheetState extends State<_MensajeRapidoSheet> {
  final _controller = TextEditingController();
  
  final _plantillas = [
    '¡Hola! ¿Cómo estás? 😊',
    '¡Hola! ¿Te gustaría hacer un pedido?',
    '¡Hola! Quería confirmar tu último pedido.',
    '¡Hola! Tu pedido está listo para envío 📦',
    '¡Hola! ¿Recibiste tu pedido? ¿Todo bien?',
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.chat, color: Colors.green),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text('Mensaje a ${widget.nombreCliente}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _plantillas.map((p) => GestureDetector(
                    onTap: () => _controller.text = p,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(p, style: const TextStyle(fontSize: 13)),
                    ),
                  )).toList(),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _controller,
                  maxLines: 3,
                  decoration: InputDecoration(
                    hintText: 'Escribe tu mensaje...',
                    hintStyle: TextStyle(color: Colors.grey.shade400),
                    filled: true,
                    fillColor: Colors.grey.shade50,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Cancelar'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          if (_controller.text.trim().isNotEmpty) {
                            widget.onEnviar(_controller.text.trim());
                          }
                        },
                        icon: const Icon(Icons.send),
                        label: const Text('Abrir WhatsApp'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PreciosPersonalizadosSheet extends StatefulWidget {
  final String clienteId;
  final String nombreCliente;

  const _PreciosPersonalizadosSheet({required this.clienteId, required this.nombreCliente});

  @override
  State<_PreciosPersonalizadosSheet> createState() => _PreciosPersonalizadosSheetState();
}

class _PreciosPersonalizadosSheetState extends State<_PreciosPersonalizadosSheet> {
  bool _isLoading = true;
  bool _isSaving = false;
  final Set<String> _eliminando = {};

  // Each entry: { presentationId, productName, etiqueta, precioBase, molienda }
  final List<Map<String, dynamic>> _filas = [];
  Map<String, double> _preciosPersonalizados = {};
  final Map<String, TextEditingController> _controllers = {};

  @override
  void initState() {
    super.initState();
    _cargarDatos();
  }

  String _etiquetaPresentacion(Map<String, dynamic> pp) {
    final contenido = (pp['contenido'] as num?)?.toDouble() ?? 1;
    final unidad = pp['unidad']?.toString() ?? 'und';
    if (unidad == 'g' && contenido >= 1000) {
      final kg = contenido / 1000;
      return '${kg % 1 == 0 ? kg.toInt() : kg}kg';
    }
    return '${contenido % 1 == 0 ? contenido.toInt() : contenido}$unidad';
  }

  Future<void> _cargarDatos() async {
    final resultados = await Future.wait([
      ApiService.getProductos(limite: 100),
      ApiService.getPreciosCliente(clienteId: widget.clienteId),
    ]);

    final productosResult = resultados[0] as ApiResponse<ProductosResponse>;
    final preciosResult = resultados[1] as ApiResponse<Map<String, double>>;

    if (productosResult.isSuccess) {
      if (preciosResult.isSuccess && preciosResult.data != null) {
        _preciosPersonalizados = preciosResult.data!;
      }

      for (final p in productosResult.data!.productos) {
        final nombre = p['nombre']?.toString() ?? '';
        final presentaciones = p['presentaciones'] as List<dynamic>? ?? [];
        for (final pp in presentaciones) {
          final ppMap = pp as Map<String, dynamic>;
          final presentationId = ppMap['id']?.toString() ?? '';
          if (presentationId.isEmpty) continue;
          final precioBase = (ppMap['precio'] as num?)?.toDouble() ?? 0;
          final etiqueta = _etiquetaPresentacion(ppMap);
          final moliendaRaw = ppMap['molienda'] as List<dynamic>? ?? [];
          final molienda = moliendaRaw.map((e) => switch (e.toString()) {
            'ground' => 'Molido',
            'whole'  => 'Grano',
            'green'  => 'Verde',
            _        => e.toString(),
          }).where((e) => e.isNotEmpty).toList();
          _filas.add({
            'presentationId': presentationId,
            'productName': nombre,
            'etiqueta': etiqueta,
            'precioBase': precioBase,
            'molienda': molienda,
          });
          final precioPersonalizado = _preciosPersonalizados[presentationId];
          _controllers[presentationId] = TextEditingController(
            text: (precioPersonalizado ?? precioBase).toStringAsFixed(2),
          );
        }
      }
    }

    setState(() => _isLoading = false);
  }

  Future<void> _eliminarPrecio(String presentationId, double precioBase) async {
    setState(() => _eliminando.add(presentationId));
    final result = await ApiService.eliminarPrecioCliente(
      clienteId: widget.clienteId,
      presentationId: presentationId,
    );
    if (mounted) {
      if (result.isSuccess) {
        setState(() {
          _preciosPersonalizados.remove(presentationId);
          _controllers[presentationId]?.text = precioBase.toStringAsFixed(2);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Precio restablecido al valor base'), backgroundColor: Colors.green),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${result.error}'), backgroundColor: Colors.red),
        );
      }
      setState(() => _eliminando.remove(presentationId));
    }
  }

  Future<void> _guardarPrecios() async {
    setState(() => _isSaving = true);

    final preciosAGuardar = <String, double>{};

    for (final fila in _filas) {
      final presentationId = fila['presentationId'] as String;
      final precioBase = fila['precioBase'] as double;
      final controller = _controllers[presentationId];
      if (controller != null) {
        final texto = controller.text.trim().replaceAll(',', '.');
        final precioIngresado = double.tryParse(texto) ?? precioBase;
        if ((precioIngresado - precioBase).abs() > 0.01) {
          preciosAGuardar[presentationId] = precioIngresado;
        }
      }
    }

    if (preciosAGuardar.isEmpty) {
      setState(() => _isSaving = false);
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No hay cambios de precios'), backgroundColor: Colors.grey),
        );
      }
      return;
    }

    final result = await ApiService.guardarPreciosCliente(
      clienteId: widget.clienteId,
      precios: preciosAGuardar,
    );

    setState(() => _isSaving = false);

    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.isSuccess ? '✅ ${preciosAGuardar.length} precios guardados' : 'Error: ${result.error}'),
          backgroundColor: result.isSuccess ? Colors.green : Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final keyboardVisible = bottomInset > 0;

    return Container(
      height: MediaQuery.of(context).size.height * (keyboardVisible ? 0.95 : 0.75),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(Icons.sell, color: Colors.orange),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Precios para ${widget.nombreCliente}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      Text('Precio especial por presentación', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                    ],
                  ),
                ),
                IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _filas.length,
                    itemBuilder: (context, index) {
                      final fila = _filas[index];
                      final presentationId = fila['presentationId'] as String;
                      final productName = fila['productName'] as String;
                      final etiqueta = fila['etiqueta'] as String;
                      final precioBase = fila['precioBase'] as double;
                      final molienda = fila['molienda'] as List<String>? ?? [];
                      final tienePersonalizado = _preciosPersonalizados.containsKey(presentationId);

                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: tienePersonalizado ? Colors.orange.shade50 : Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: tienePersonalizado ? Border.all(color: Colors.orange.shade200) : null,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          '$productName – $etiqueta',
                                          style: const TextStyle(fontWeight: FontWeight.w600),
                                        ),
                                      ),
                                      if (tienePersonalizado)
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(color: Colors.orange, borderRadius: BorderRadius.circular(8)),
                                          child: const Text('ESPECIAL', style: TextStyle(fontSize: 9, color: Colors.white, fontWeight: FontWeight.bold)),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Text('Base: S/ ${precioBase.toStringAsFixed(2)}', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                                  if (molienda.isNotEmpty) ...[
                                    const SizedBox(height: 3),
                                    Wrap(
                                      spacing: 4,
                                      children: molienda.map((m) => Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Colors.brown.shade50,
                                          borderRadius: BorderRadius.circular(4),
                                          border: Border.all(color: Colors.brown.shade200),
                                        ),
                                        child: Text(m, style: TextStyle(fontSize: 10, color: Colors.brown.shade700, fontWeight: FontWeight.w500)),
                                      )).toList(),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            SizedBox(
                              width: 100,
                              child: TextField(
                                controller: _controllers[presentationId],
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                textAlign: TextAlign.center,
                                style: TextStyle(fontWeight: FontWeight.w600, color: tienePersonalizado ? Colors.orange.shade700 : Colors.black87),
                                decoration: InputDecoration(
                                  prefixText: 'S/ ',
                                  filled: true,
                                  fillColor: Colors.white,
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
                                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Colors.orange, width: 2)),
                                ),
                              ),
                            ),
                            if (tienePersonalizado) ...[
                              const SizedBox(width: 6),
                              _eliminando.contains(presentationId)
                                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                                  : IconButton(
                                      icon: Icon(Icons.restore, color: Colors.red.shade400, size: 20),
                                      tooltip: 'Restablecer precio base',
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                      onPressed: () => _eliminarPrecio(presentationId, precioBase),
                                    ),
                            ],
                          ],
                        ),
                      );
                    },
                  ),
          ),
          Container(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + bottomInset),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, -2))],
            ),
            child: SafeArea(
              top: false,
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isSaving ? null : _guardarPrecios,
                  icon: _isSaving ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.save),
                  label: Text(_isSaving ? 'Guardando...' : 'Guardar Precios'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SHEET: Agregar dirección
// ─────────────────────────────────────────────────────────────────────────────

class _AgregarDireccionSheet extends StatefulWidget {
  final String clienteId;
  final bool esPrimaria;
  final void Function(Map<String, dynamic>) onGuardado;

  const _AgregarDireccionSheet({
    required this.clienteId,
    required this.esPrimaria,
    required this.onGuardado,
  });

  @override
  State<_AgregarDireccionSheet> createState() => _AgregarDireccionSheetState();
}

class _AgregarDireccionSheetState extends State<_AgregarDireccionSheet> {
  bool _isSaving = false;
  bool _isPrimary = false;

  final _aliasCtrl       = TextEditingController();
  final _addressLineCtrl = TextEditingController();
  final _districtCtrl    = TextEditingController();
  final _departmentCtrl  = TextEditingController();
  final _referenceCtrl   = TextEditingController();

  @override
  void initState() {
    super.initState();
    _isPrimary = widget.esPrimaria;
  }

  @override
  void dispose() {
    _aliasCtrl.dispose();
    _addressLineCtrl.dispose();
    _districtCtrl.dispose();
    _departmentCtrl.dispose();
    _referenceCtrl.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    if (_addressLineCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('La dirección es obligatoria'), backgroundColor: Colors.orange),
      );
      return;
    }
    setState(() => _isSaving = true);

    final result = await ApiService.crearDireccion(
      clienteId:   widget.clienteId,
      addressLine: _addressLineCtrl.text.trim(),
      alias:       _aliasCtrl.text.trim(),
      district:    _districtCtrl.text.trim(),
      department:  _departmentCtrl.text.trim(),
      reference:   _referenceCtrl.text.trim(),
      isPrimary:   _isPrimary,
    );

    setState(() => _isSaving = false);

    if (!mounted) return;

    if (result.isSuccess) {
      Navigator.pop(context);
      widget.onGuardado(result.data!);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Dirección guardada'), backgroundColor: Colors.green),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: ${result.error}'), backgroundColor: Colors.red),
      );
    }
  }

  Widget _campo({required String label, required TextEditingController controller, String? hint, bool required = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        decoration: InputDecoration(
          labelText: required ? '$label *' : label,
          hintText: hint,
          filled: true,
          fillColor: Colors.grey.shade50,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.shade300)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.shade300)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Colors.blue, width: 2)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + bottomInset),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 16),
          Row(
            children: [
              const Icon(Icons.add_location_alt_outlined, color: Colors.blue),
              const SizedBox(width: 8),
              const Expanded(child: Text('Nueva dirección', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold))),
              IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
            ],
          ),
          const Divider(),
          const SizedBox(height: 4),
          _campo(label: 'Alias', controller: _aliasCtrl, hint: 'Casa, Trabajo, Local…'),
          _campo(label: 'Dirección', controller: _addressLineCtrl, hint: 'Av. Principal 123, Dpto 4', required: true),
          Row(
            children: [
              Expanded(child: _campo(label: 'Distrito', controller: _districtCtrl, hint: 'Miraflores')),
              const SizedBox(width: 10),
              Expanded(child: _campo(label: 'Departamento', controller: _departmentCtrl, hint: 'Lima')),
            ],
          ),
          _campo(label: 'Referencia', controller: _referenceCtrl, hint: 'Frente al parque, color azul…'),
          SwitchListTile(
            value: _isPrimary,
            onChanged: (v) => setState(() => _isPrimary = v),
            title: const Text('Dirección principal', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
            subtitle: const Text('Se usará por defecto al crear pedidos', style: TextStyle(fontSize: 12)),
            contentPadding: EdgeInsets.zero,
            activeColor: Colors.blue,
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isSaving ? null : _guardar,
              icon: _isSaving
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.save),
              label: Text(_isSaving ? 'Guardando…' : 'Guardar dirección'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue.shade600,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
