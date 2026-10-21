import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/api_service.dart';
import 'tabs/pedidos/widgets/detalle_pedido/lista_productos_widget.dart';
import '../services/pedido_pdf_service.dart';

/// Flujo de cotización en 4 pasos:
///   1. Cliente     — existente (búsqueda) o nuevo (formulario ligero)
///   2. Precios     — lista de precios para esta cotización
///   3. Productos   — qué entra y en qué cantidad
///   4. Resumen     — revisión y PDF
class CrearCotizacionScreen extends StatefulWidget {
  /// Cliente ya elegido (al entrar desde su ficha). Si es null, el flujo
  /// arranca en el paso 1.
  final Map<String, dynamic>? cliente;

  const CrearCotizacionScreen({super.key, this.cliente});

  @override
  State<CrearCotizacionScreen> createState() => _CrearCotizacionScreenState();
}

/// Fila del catálogo: un producto con UNA de sus presentaciones ya resuelta.
///
/// La molienda (grano / molido) se ignora a propósito: en una cotización el
/// precio no cambia según el tipo de molienda, así que desdoblar cada fila
/// por molienda sólo alargaría la lista sin aportar nada.
class _FilaCatalogo {
  final String codigo;
  final String nombre;
  final String? presentacionId;
  final String? presentacion; // etiqueta legible, p. ej. "250 g"
  final double precioLista;

  /// Etiquetas de molienda ya traducidas: Grano / Molido / Verde.
  final List<String> molienda;

  /// Imagen de la presentación (nunca la portada del producto), igual que
  /// en la pantalla de crear pedido.
  final String? imageUrl;

  const _FilaCatalogo({
    required this.codigo,
    required this.nombre,
    this.presentacionId,
    this.presentacion,
    required this.precioLista,
    this.molienda = const [],
    this.imageUrl,
  });

  bool get esVerde => molienda.contains('Verde');

  /// Identidad única: un mismo producto aparece varias veces, una por
  /// presentación.
  String get clave => '$codigo::${presentacionId ?? ''}';

  String get titulo => presentacion != null && presentacion!.isNotEmpty
      ? '$nombre  ·  $presentacion'
      : nombre;
}

class _CrearCotizacionScreenState extends State<CrearCotizacionScreen> {
  int _paso = 0;

  // ── Paso 1: cliente ─────────────────────────────────────────────
  Map<String, dynamic>? _clienteSel;
  bool _clienteNuevo = false;
  final _nombreCtrl = TextEditingController();
  final _whatsappCtrl = TextEditingController();
  final _empresaCtrl = TextEditingController();
  final _buscarCtrl = TextEditingController();
  List<Map<String, dynamic>> _clientes = [];
  bool _cargandoClientes = false;

  /// Todos los clientes, para detectar un WhatsApp repetido sin depender
  /// del texto que haya en el buscador.
  List<Map<String, dynamic>> _todosClientes = [];
  Map<String, dynamic>? _clienteDuplicado;

  // ── Catálogo (compartido por los pasos 2 y 3) ───────────────────
  List<_FilaCatalogo> _catalogo = [];
  bool _cargandoProductos = false;

  /// Precio de esta cotización por fila. Arranca en el precio de lista y
  /// se sobrescribe con el precio personalizado del cliente si lo hay.
  final Map<String, double> _precios = {};

  /// Cantidad elegida por fila. Una fila sin entrada aquí no entra en la
  /// cotización.
  final Map<String, double> _cantidades = {};

  /// Un controller por fila, igual que en `_PreciosPersonalizadosSheet`,
  /// para poder restablecer el precio base desde el botón de restaurar.
  final Map<String, TextEditingController> _ctrlPrecios = {};

  bool _guardarPrecios = true;

  // ── Paso 4 ──────────────────────────────────────────────────────
  final _obsCtrl = TextEditingController();
  bool _generando = false;

  @override
  void initState() {
    super.initState();
    if (widget.cliente != null) {
      _clienteSel = widget.cliente;
      _paso = 1; // ya hay cliente: saltamos directo a precios
      _cargarPreciosCliente();
    }
    _cargarProductos();
    _cargarTodosClientes();
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _whatsappCtrl.dispose();
    _empresaCtrl.dispose();
    _buscarCtrl.dispose();
    _obsCtrl.dispose();
    for (final c in _ctrlPrecios.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// Mismo criterio que la lista de clientes (`_ClienteCard`):
  /// nombreNegocio → nombre → nombreResponsable.
  static String _displayName(Map<String, dynamic> c) {
    final nombreNegocio = (c['nombreNegocio'] ?? c['nombre'] ?? '').toString();
    final nombreResponsable = (c['nombreResponsable'] ?? '').toString();
    final display =
        nombreNegocio.isNotEmpty ? nombreNegocio : nombreResponsable;
    return display.isEmpty ? 'Sin nombre' : display;
  }

  static Color _colorEstado(String? estado) {
    switch (estado) {
      case 'ACTIVO':   return Colors.green;
      case 'INACTIVO': return Colors.grey;
      case 'INVITADO': return Colors.purple;
      default:         return Colors.blue;
    }
  }

  // ── Carga de datos ──────────────────────────────────────────────

  /// Carga inicial: llena la lista visible del paso 1 (igual que la pestaña
  /// de clientes, que carga sin filtro al abrir) y a la vez guarda la lista
  /// completa para detectar WhatsApp repetidos.
  Future<void> _cargarTodosClientes() async {
    setState(() => _cargandoClientes = true);
    final res = await ApiService.getClientes();
    if (!mounted) return;
    final lista = res.data ?? [];
    setState(() {
      _todosClientes = lista;
      // Sólo si el usuario todavía no buscó nada.
      if (_buscarCtrl.text.isEmpty) _clientes = lista;
      _cargandoClientes = false;
    });
  }

  /// Sólo dígitos, para comparar "+51 987 654 321" con "987654321".
  static String _soloDigitos(String s) => s.replaceAll(RegExp(r'[^0-9]'), '');

  /// Busca un cliente ya registrado con el mismo WhatsApp.
  void _verificarDuplicado(String valor) {
    final buscado = _soloDigitos(valor);
    if (buscado.length < 6) {
      setState(() => _clienteDuplicado = null);
      return;
    }
    Map<String, dynamic>? encontrado;
    for (final c in _todosClientes) {
      final wa = _soloDigitos((c['whatsapp'] ?? '').toString());
      final tel = _soloDigitos((c['telefono'] ?? '').toString());
      if (wa == buscado || tel == buscado) {
        encontrado = c;
        break;
      }
    }
    setState(() => _clienteDuplicado = encontrado);
  }

  Future<void> _buscarClientes(String q) async {
    setState(() => _cargandoClientes = true);
    final res = await ApiService.getClientes(buscar: q.isEmpty ? null : q);
    if (!mounted) return;
    setState(() {
      _clientes = res.data ?? [];
      _cargandoClientes = false;
    });
  }

  /// Arma el catálogo: una fila por presentación. Las presentaciones ya
  /// vienen embebidas en cada producto, así que no hacen falta más llamadas.
  Future<void> _cargarProductos() async {
    setState(() => _cargandoProductos = true);
    final res = await ApiService.getProductos(limite: 100, estado: 'ACTIVO');
    if (!mounted) return;

    final filas = <_FilaCatalogo>[];
    for (final producto in (res.data?.productos ?? <Map<String, dynamic>>[])) {
      final codigo = producto['codigo']?.toString() ?? '';
      final nombre = producto['nombre']?.toString() ?? '';
      final presRaw = producto['presentaciones'] as List<dynamic>? ?? [];

      if (presRaw.isEmpty) {
        filas.add(_FilaCatalogo(
          codigo: codigo,
          nombre: nombre,
          precioLista: (producto['precio'] as num?)?.toDouble() ?? 0,
        ));
      } else {
        for (final pp in presRaw) {
          final ppMap = pp as Map<String, dynamic>;
          final presentationId = ppMap['id']?.toString() ?? '';
          if (presentationId.isEmpty) continue;
          filas.add(_FilaCatalogo(
            codigo: codigo,
            nombre: nombre,
            presentacionId: presentationId,
            presentacion: _etiquetaPresentacion(ppMap),
            precioLista: (ppMap['precio'] as num?)?.toDouble() ?? 0,
            molienda: _etiquetasMolienda(ppMap),
            imageUrl: ppMap['imageUrl']?.toString(),
          ));
        }
      }
    }

    setState(() {
      _catalogo = filas;
      for (final f in filas) {
        _precios.putIfAbsent(f.clave, () => f.precioLista);
        _ctrlPrecios.putIfAbsent(
          f.clave,
          () => TextEditingController(text: f.precioLista.toStringAsFixed(2)),
        );
      }
      _cargandoProductos = false;
    });
    _aplicarPreciosCliente();
  }

  /// Mismo formato que `_PreciosPersonalizadosSheet`: "250g", "1kg".
  static String _etiquetaPresentacion(Map<String, dynamic> pp) {
    final contenido = (pp['contenido'] as num?)?.toDouble() ?? 0;
    final unidad = pp['unidad']?.toString() ?? '';
    if (unidad == 'g' && contenido >= 1000) {
      final kg = contenido / 1000;
      return '${kg % 1 == 0 ? kg.toInt() : kg}kg';
    }
    return '${contenido % 1 == 0 ? contenido.toInt() : contenido}$unidad';
  }

  /// Misma traducción que la hoja de precios personalizados.
  static List<String> _etiquetasMolienda(Map<String, dynamic> pp) {
    final raw = pp['molienda'] as List<dynamic>? ?? [];
    return raw
        .map((e) => switch (e.toString()) {
              'ground' => 'Molido',
              'whole' => 'Grano',
              'green' => 'Verde',
              _ => e.toString(),
            })
        .where((e) => e.isNotEmpty)
        .toList();
  }

  /// Precios personalizados del cliente, que pisan al precio de lista.
  Map<String, double> _preciosCliente = {};

  Future<void> _cargarPreciosCliente() async {
    final id = _clienteSel?['id']?.toString();
    if (id == null || id.isEmpty) return;
    final res = await ApiService.getPreciosCliente(clienteId: id);
    if (!mounted) return;
    setState(() => _preciosCliente = res.data ?? {});
    _aplicarPreciosCliente();
  }

  void _aplicarPreciosCliente() {
    if (_preciosCliente.isEmpty || _catalogo.isEmpty) return;
    setState(() {
      for (final f in _catalogo) {
        final personalizado =
            _preciosCliente[f.presentacionId] ?? _preciosCliente[f.codigo];
        if (personalizado != null && personalizado > 0) {
          _precios[f.clave] = personalizado;
          _ctrlPrecios[f.clave]?.text = personalizado.toStringAsFixed(2);
        }
      }
    });
  }

  // ── Derivados ───────────────────────────────────────────────────

  List<_FilaCatalogo> get _elegidas => _catalogo
      .where((f) => (_cantidades[f.clave] ?? 0) > 0)
      .toList();

  double _precioDe(_FilaCatalogo f) => _precios[f.clave] ?? f.precioLista;
  double _cantidadDe(_FilaCatalogo f) => _cantidades[f.clave] ?? 0;
  double _totalDe(_FilaCatalogo f) => _precioDe(f) * _cantidadDe(f);

  double get _total =>
      _elegidas.fold<double>(0, (s, f) => s + _totalDe(f));

  /// Líneas en el formato que esperan `ListaProductosWidget` y el PDF de
  /// pedido, para que el resumen en pantalla y el documento coincidan.
  List<Map<String, dynamic>> get _productosMap => _elegidas
      .map((f) => {
            'nombre': f.nombre,
            'presentacionId': f.presentacionId ?? '',
            'cantidad': _cantidadDe(f).toInt(),
            'precio': _precioDe(f),
            'subtotal': _totalDe(f),
            'unit': f.presentacion ?? '',
            'grind': f.molienda.length == 1 ? f.molienda.first : '',
          })
      .toList();

  String get _nombreCliente => _clienteSel != null
      ? _displayName(_clienteSel!)
      : _nombreCtrl.text.trim();

  // ── Navegación entre pasos ──────────────────────────────────────

  bool get _pasoValido => switch (_paso) {
        0 => _clienteNuevo
            ? _nombreCtrl.text.trim().isNotEmpty &&
                _whatsappCtrl.text.trim().isNotEmpty &&
                _clienteDuplicado == null
            : _clienteSel != null,
        1 => _catalogo.isNotEmpty &&
            _catalogo.every((f) => _precioDe(f) > 0),
        2 => _elegidas.isNotEmpty,
        _ => true,
      };

  void _siguiente() {
    if (_paso == 0 && !_clienteNuevo) _cargarPreciosCliente();
    setState(() => _paso++);
  }

  // ── Generación final ────────────────────────────────────────────

  Future<void> _generarPdf() async {
    setState(() => _generando = true);

    try {
      // Cliente nuevo: se crea recién ahora, para no ensuciar la lista con
      // prospectos si el usuario abandona el flujo a mitad de camino.
      if (_clienteNuevo && _clienteSel == null) {
        // Mismos campos que usa la ficha de cliente (`_guardar`): el API
        // espera nombreNegocio / nombreResponsable, no 'nombre'.
        // Se crea como PROSPECTO: todavía no compró nada.
        final res = await ApiService.crearCliente(datos: {
          'whatsapp': _whatsappCtrl.text.trim(),
          'nombreNegocio': _empresaCtrl.text.trim(),
          'nombreResponsable': _nombreCtrl.text.trim(),
          'estado': 'PROSPECTO',
          'notas': 'Creado desde una cotización',
        });
        if (res.data == null) {
          throw Exception(res.error ?? 'No se pudo crear el cliente');
        }
        _clienteSel = res.data;
      }

      // Los precios se guardan como precios del cliente, no sólo para esta
      // cotización: se manda TODA fila cuyo precio se haya cambiado respecto
      // al de lista, entre o no en la cotización.
      final clienteId = _clienteSel?['id']?.toString();
      if (_guardarPrecios && clienteId != null && clienteId.isNotEmpty) {
        final modificados = <String, double>{};
        for (final f in _catalogo) {
          final precio = _precioDe(f);
          if ((precio - f.precioLista).abs() > 0.01) {
            modificados[f.presentacionId ?? f.codigo] = precio;
          }
        }
        if (modificados.isNotEmpty) {
          await ApiService.guardarPreciosCliente(
            clienteId: clienteId,
            precios: modificados,
          );
        }
      }

      // Se reutiliza el PDF de pedido en modo cotización, para que ambos
      // documentos sean idénticos salvo los rótulos.
      final ahora = DateTime.now();
      final fecha = '${ahora.day.toString().padLeft(2, '0')}/'
          '${ahora.month.toString().padLeft(2, '0')}/${ahora.year}';

      await PedidoPdfService.generarCotizacionYCompartir(
        cotizacion: {
          'id': 'COT-${ahora.millisecondsSinceEpoch ~/ 1000}',
          'fecha': fecha,
          'cliente': _nombreCliente,
          'whatsapp': _clienteSel?['whatsapp']?.toString() ??
              _whatsappCtrl.text.trim(),
          'observaciones': _obsCtrl.text.trim(),
          'subtotal': _total,
          'total': _total,
          'costoEnvio': 0,
        },
        productos: _productosMap,
      );

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Error generando la cotización: $e'),
            backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _generando = false);
    }
  }

  // ── UI ──────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    const titulos = ['Cliente', 'Precios', 'Productos', 'Resumen'];

    return Scaffold(
      backgroundColor: const Color(0xFFF7F5F2),
      appBar: AppBar(
        backgroundColor: const Color(0xFF2d2720),
        foregroundColor: Colors.white,
        title: Text('Cotizar · ${titulos[_paso]}',
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
      ),
      body: Column(
        children: [
          _buildIndicadorPasos(titulos),
          Expanded(
            child: switch (_paso) {
              0 => _buildPasoCliente(),
              1 => _buildPasoPrecios(),
              2 => _buildPasoProductos(),
              _ => _buildPasoResumen(),
            },
          ),
          _buildBarraInferior(),
        ],
      ),
    );
  }

  Widget _buildIndicadorPasos(List<String> titulos) {
    return Container(
      color: const Color(0xFF2d2720),
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Row(
        children: List.generate(titulos.length, (i) {
          final activo = i <= _paso;
          return Expanded(
            child: Container(
              height: 4,
              margin: EdgeInsets.only(right: i < titulos.length - 1 ? 6 : 0),
              decoration: BoxDecoration(
                color: activo ? Colors.orange : Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          );
        }),
      ),
    );
  }

  // ── Paso 1: cliente ─────────────────────────────────────────────

  Widget _buildPasoCliente() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('Cliente existente')),
              ButtonSegment(value: true, label: Text('Cliente nuevo')),
            ],
            selected: {_clienteNuevo},
            onSelectionChanged: (s) {
              setState(() {
                _clienteNuevo = s.first;
                _clienteSel = null;
              });
              if (!_clienteNuevo && _clientes.isEmpty) _cargarTodosClientes();
            },
          ),
        ),
        Expanded(
          child:
              _clienteNuevo ? _buildFormNuevoCliente() : _buildListaClientes(),
        ),
      ],
    );
  }

  Widget _buildFormNuevoCliente() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      children: [
        const Text(
          'Sólo lo indispensable para la cotización. '
          'El cliente se crea recién al generar el PDF.',
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _nombreCtrl,
          decoration: const InputDecoration(
            labelText: 'Nombre *',
            border: OutlineInputBorder(),
          ),
          textCapitalization: TextCapitalization.words,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _whatsappCtrl,
          decoration: InputDecoration(
            labelText: 'WhatsApp *',
            border: const OutlineInputBorder(),
            prefixText: '+51 ',
            errorText: _clienteDuplicado != null
                ? 'Ya existe un cliente con este número'
                : null,
          ),
          keyboardType: TextInputType.phone,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          onChanged: _verificarDuplicado,
        ),
        if (_clienteDuplicado != null) ...[
          const SizedBox(height: 8),
          _buildAvisoDuplicado(),
        ],
        const SizedBox(height: 12),
        TextField(
          controller: _empresaCtrl,
          decoration: const InputDecoration(
            labelText: 'Empresa / negocio (opcional)',
            border: OutlineInputBorder(),
          ),
          textCapitalization: TextCapitalization.words,
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.orange.shade50,
            border: Border.all(color: Colors.orange.shade200),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(Icons.info_outline,
                  size: 16, color: Colors.orange.shade800),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Se registrará con estado PROSPECTO hasta que haga su '
                  'primer pedido.',
                  style: TextStyle(
                      fontSize: 11, color: Colors.orange.shade900),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Aviso de WhatsApp repetido, con un atajo para usar el cliente que ya
  /// existe en vez de crear un duplicado.
  Widget _buildAvisoDuplicado() {
    final c = _clienteDuplicado!;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        border: Border.all(color: Colors.red.shade200),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.person_search, size: 18, color: Colors.red.shade700),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Este número ya está registrado',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.red.shade900)),
                Text(_displayName(c),
                    style:
                        TextStyle(fontSize: 11, color: Colors.red.shade800)),
              ],
            ),
          ),
          TextButton(
            onPressed: () => setState(() {
              _clienteSel = c;
              _clienteNuevo = false;
              _clienteDuplicado = null;
              _cargarPreciosCliente();
            }),
            child: const Text('Usarlo'),
          ),
        ],
      ),
    );
  }

  Widget _buildListaClientes() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            controller: _buscarCtrl,
            decoration: InputDecoration(
              hintText: 'Buscar cliente...',
              prefixIcon: const Icon(Icons.search),
              border: const OutlineInputBorder(),
              isDense: true,
              suffixIcon: _buscarCtrl.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _buscarCtrl.clear();
                        _buscarClientes('');
                      },
                    )
                  : null,
            ),
            onChanged: _buscarClientes,
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: _cargandoClientes
              ? const Center(child: CircularProgressIndicator())
              : _clientes.isEmpty
                  ? const Center(
                      child: Text('Sin clientes',
                          style: TextStyle(color: Colors.grey)))
                  : ListView.builder(
                      itemCount: _clientes.length,
                      itemBuilder: (_, i) {
                        final c = _clientes[i];
                        final nombre = _displayName(c);
                        final estado = c['estado']?.toString() ?? 'ACTIVO';
                        final sel = _clienteSel?['id'] == c['id'];
                        final color =
                            sel ? Colors.orange : _colorEstado(estado);
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: color.withValues(alpha: 0.12),
                            child: Text(
                              nombre[0].toUpperCase(),
                              style: TextStyle(
                                  color: color, fontWeight: FontWeight.bold),
                            ),
                          ),
                          title: Text(nombre,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text(c['whatsapp']?.toString() ?? ''),
                          trailing: sel
                              ? const Icon(Icons.check_circle,
                                  color: Colors.orange)
                              : null,
                          onTap: () => setState(() => _clienteSel = c),
                        );
                      },
                    ),
        ),
      ],
    );
  }

  // ── Paso 2: precios ─────────────────────────────────────────────
  // Mismo diseño que `_PreciosPersonalizadosSheet` en la ficha de cliente:
  // lista plana, tarjeta naranja cuando el precio difiere del base, chip
  // ESPECIAL, campo de 100px centrado y botón para restablecer.

  Widget _buildPasoPrecios() {
    if (_cargandoProductos) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_catalogo.isEmpty) {
      return const Center(
        child: Text('Sin productos', style: TextStyle(color: Colors.grey)),
      );
    }

    return Column(
      children: [
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
                    Text(
                        _clienteSel != null
                            ? 'Precios para $_nombreCliente'
                            : 'Precios de la cotización',
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                    Text('Precio especial por presentación',
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey.shade600)),
                  ],
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: _catalogo.length,
            itemBuilder: (context, index) => _buildFilaPrecio(_catalogo[index]),
          ),
        ),
        Material(
          color: Colors.white,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: CheckboxListTile(
              value: _guardarPrecios,
              onChanged: (v) => setState(() => _guardarPrecios = v ?? false),
              title: const Text('Guardar estos precios para el cliente',
                  style: TextStyle(fontSize: 13)),
              subtitle: const Text(
                  'Se aplicarán a sus próximos pedidos, no sólo a esta cotización',
                  style: TextStyle(fontSize: 11)),
              controlAffinity: ListTileControlAffinity.leading,
              activeColor: Colors.orange,
              dense: true,
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFilaPrecio(_FilaCatalogo f) {
    final precio = _precioDe(f);
    // "Especial" = distinto del precio de lista, con el mismo umbral de
    // 0.01 que usa la hoja de precios personalizados.
    final especial = (precio - f.precioLista).abs() > 0.01;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: especial ? Colors.orange.shade50 : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: especial ? Border.all(color: Colors.orange.shade200) : null,
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
                        f.presentacion != null && f.presentacion!.isNotEmpty
                            ? '${f.nombre} – ${f.presentacion}'
                            : f.nombre,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    if (especial)
                      Container(
                        margin: const EdgeInsets.only(left: 6),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                            color: Colors.orange,
                            borderRadius: BorderRadius.circular(8)),
                        child: const Text('ESPECIAL',
                            style: TextStyle(
                                fontSize: 9,
                                color: Colors.white,
                                fontWeight: FontWeight.bold)),
                      ),
                  ],
                ),
                const SizedBox(height: 2),
                Text('Base: S/ ${f.precioLista.toStringAsFixed(2)}',
                    style:
                        TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                if (f.molienda.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Wrap(
                    spacing: 4,
                    children: f.molienda
                        .map((m) => Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.brown.shade50,
                                borderRadius: BorderRadius.circular(4),
                                border:
                                    Border.all(color: Colors.brown.shade200),
                              ),
                              child: Text(m,
                                  style: TextStyle(
                                      fontSize: 10,
                                      color: Colors.brown.shade700,
                                      fontWeight: FontWeight.w500)),
                            ))
                        .toList(),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 100,
            child: TextField(
              controller: _ctrlPrecios[f.clave],
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: especial ? Colors.orange.shade700 : Colors.black87),
              decoration: InputDecoration(
                prefixText: 'S/ ',
                filled: true,
                fillColor: Colors.white,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: Colors.grey.shade300)),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide:
                        const BorderSide(color: Colors.orange, width: 2)),
              ),
              onChanged: (v) => setState(() =>
                  _precios[f.clave] = double.tryParse(v.replaceAll(',', '.')) ?? 0),
            ),
          ),
          if (especial) ...[
            const SizedBox(width: 6),
            IconButton(
              icon: Icon(Icons.restore, color: Colors.red.shade400, size: 20),
              tooltip: 'Restablecer precio base',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              onPressed: () => setState(() {
                _precios[f.clave] = f.precioLista;
                _ctrlPrecios[f.clave]?.text =
                    f.precioLista.toStringAsFixed(2);
              }),
            ),
          ],
        ],
      ),
    );
  }

  // ── Paso 3: productos ───────────────────────────────────────────
  // Mismo diseño que la lista de `crear_pedido_screen`: Card + ListTile
  // denso, miniatura de la presentación, chips de presentación / molienda /
  // precio, y controles − cantidad + a la derecha.

  Widget _buildPasoProductos() {
    if (_catalogo.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inventory_2_outlined,
                size: 48, color: Colors.grey.shade300),
            const SizedBox(height: 8),
            Text('No hay productos',
                style: TextStyle(color: Colors.grey.shade500)),
          ],
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        itemCount: _catalogo.length,
        itemBuilder: (context, index) => _buildFilaProducto(_catalogo[index]),
      ),
    );
  }

  Widget _buildFilaProducto(_FilaCatalogo f) {
    final cantidad = _cantidadDe(f);
    final precio = _precioDe(f);
    // Precio "preferencial": el que se ajustó en el paso de precios.
    final especial = (precio - f.precioLista).abs() > 0.01;

    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        dense: true,
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Colors.blue.shade50,
            borderRadius: BorderRadius.circular(8),
          ),
          child: f.imageUrl != null && f.imageUrl!.isNotEmpty
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    f.imageUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) =>
                        Icon(Icons.inventory_2, color: Colors.blue.shade300),
                  ),
                )
              : Icon(Icons.inventory_2, color: Colors.blue.shade300),
        ),
        title: Text(
          f.nombre,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Wrap(
            spacing: 4,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (f.presentacion != null && f.presentacion!.isNotEmpty)
                _ChipCot(
                    label: f.presentacion!,
                    fg: Colors.blue.shade700,
                    bg: Colors.blue.shade50),
              ...f.molienda.map((m) => _ChipCot(
                  label: m,
                  fg: Colors.brown.shade700,
                  bg: Colors.brown.shade50)),
              _ChipCot(
                label: especial
                    ? 'S/ ${precio.toStringAsFixed(2)} ★'
                    : 'S/ ${precio.toStringAsFixed(2)}',
                fg: especial ? Colors.purple.shade700 : Colors.green.shade700,
                bg: especial ? Colors.purple.shade50 : Colors.green.shade50,
              ),
            ],
          ),
        ),
        trailing: cantidad > 0
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  InkWell(
                    onTap: () => setState(() {
                      if (cantidad > 1) {
                        _cantidades[f.clave] = cantidad - 1;
                      } else {
                        _cantidades.remove(f.clave);
                      }
                    }),
                    borderRadius: BorderRadius.circular(20),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(Icons.remove_circle,
                          color: Colors.red.shade400, size: 28),
                    ),
                  ),
                  Container(
                    constraints: const BoxConstraints(minWidth: 32),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${cantidad.toInt()}',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.blue.shade700,
                          fontSize: 14),
                    ),
                  ),
                  InkWell(
                    onTap: () =>
                        setState(() => _cantidades[f.clave] = cantidad + 1),
                    borderRadius: BorderRadius.circular(20),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(Icons.add_circle,
                          color: Colors.blue.shade600, size: 28),
                    ),
                  ),
                ],
              )
            : IconButton(
                icon: Icon(Icons.add_circle,
                    color: Colors.blue.shade600, size: 28),
                onPressed: () => setState(() => _cantidades[f.clave] = 1),
              ),
      ),
    );
  }

  // ── Paso 4: resumen ─────────────────────────────────────────────

  Widget _buildPasoResumen() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Cliente
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(color: Colors.grey.shade300),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('CLIENTE',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Colors.grey,
                        letterSpacing: 1)),
                const SizedBox(height: 4),
                Text(_nombreCliente,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700)),
                if (_clienteNuevo && _clienteSel == null)
                  const Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: Text('Se creará como PROSPECTO al generar el PDF',
                        style: TextStyle(fontSize: 11, color: Colors.orange)),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        // Mismo listado que el detalle de un pedido
        ListaProductosWidget(productos: _productosMap),
        const SizedBox(height: 12),

        // Total
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: const Color(0xFF2d2720),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('TOTAL',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1)),
              Text('S/ ${_total.toStringAsFixed(2)}',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w700)),
            ],
          ),
        ),
        const SizedBox(height: 16),

        TextField(
          controller: _obsCtrl,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Observaciones (opcional)',
            border: OutlineInputBorder(),
            alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'La cotización se marcará como válida por '
          '${PedidoPdfService.validezCotizacionDias} días.',
          style: TextStyle(fontSize: 11, color: Colors.grey),
        ),
      ],
    );
  }

  // ── Barra inferior ──────────────────────────────────────────────

  Widget _buildBarraInferior() {
    final ultimo = _paso == 3;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(color: Color(0x0F000000), blurRadius: 8),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            if (_paso > 0)
              TextButton(
                onPressed: _generando ? null : () => setState(() => _paso--),
                child: const Text('Atrás'),
              ),
            if (_elegidas.isNotEmpty && _paso >= 2) ...[
              const SizedBox(width: 8),
              Text('S/ ${_total.toStringAsFixed(2)}',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700)),
            ],
            const Spacer(),
            FilledButton.icon(
              icon: _generando
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : Icon(ultimo ? Icons.picture_as_pdf : Icons.arrow_forward),
              label: Text(ultimo ? 'Generar PDF' : 'Siguiente'),
              onPressed: (!_pasoValido || _generando)
                  ? null
                  : (ultimo ? _generarPdf : _siguiente),
            ),
          ],
        ),
      ),
    );
  }
}

/// Igual que `_Chip` en `crear_pedido_screen`.
class _ChipCot extends StatelessWidget {
  final String label;
  final Color fg;
  final Color bg;
  const _ChipCot({required this.label, required this.fg, required this.bg});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(4)),
      child: Text(label,
          style: TextStyle(fontSize: 11, color: fg, fontWeight: FontWeight.w600)),
    );
  }
}
