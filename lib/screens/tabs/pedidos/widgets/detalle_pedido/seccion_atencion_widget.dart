import 'package:flutter/material.dart';
import '../../../../../services/api_service.dart';
import '../../helpers/producto_parser.dart';

/// Sección de Gestión de Atención del Pedido
/// Muestra el stock actual de cada producto pedido y sugiere recetas
/// para cubrir el déficit cuando no hay stock suficiente.
class SeccionAtencionWidget extends StatefulWidget {
  final Map<String, dynamic> pedido;
  final VoidCallback onStockActualizado;

  const SeccionAtencionWidget({
    super.key,
    required this.pedido,
    required this.onStockActualizado,
  });

  @override
  State<SeccionAtencionWidget> createState() => _SeccionAtencionWidgetState();
}

class _SeccionAtencionWidgetState extends State<SeccionAtencionWidget> {
  FulfillmentPlan? _plan;
  bool _loading = true;
  String? _error;
  final Set<String> _expanded = {};

  // ── Colors ───────────────────────────────────────────────────
  static const _colorOk       = Color(0xFF2E7D32);   // green.800
  static const _colorPartial  = Color(0xFFE65100);   // deepOrange.800
  static const _colorPending  = Color(0xFF455A64);   // blueGrey.700 — calm, not alarming
  static const _colorRecipe   = Color(0xFF00695C);   // teal.800

  @override
  void initState() {
    super.initState();
    // No auto-carga — el usuario activa cuando lo necesita
    setState(() => _loading = false);
  }

  /// Builds the fulfillment plan entirely in Flutter:
  /// 1. Parse pedido products (handles JSON, text, list formats)
  /// 2. Load own inventory + recipes in parallel
  /// 3. Match each product by codigo first, then by name (case-insensitive)
  /// 4. Build PlanItem + RecetaSugerencia list locally
  Future<void> _cargarPlan() async {
    if (mounted) setState(() { _loading = true; _error = null; });

    try {
      final _rawDetalle = widget.pedido['productosDetalle'];
      final pedidoProductos = (_rawDetalle is List && _rawDetalle.isNotEmpty)
          ? parseProductos(_rawDetalle)
          : parseProductos(widget.pedido['productos']);
      if (pedidoProductos.isEmpty) {
        if (mounted) setState(() {
          _loading = false;
          _plan = FulfillmentPlan(pedidoId: '', plan: [], todoCubierto: true, algunoSinStock: false);
        });
        return;
      }

      final results = await Future.wait([
        ApiService.getProductos(limite: 200),
        ApiService.getRecetas(),
      ]);

      final invResult    = results[0] as ApiResponse<ProductosResponse>;
      final recetaResult = results[1] as ApiResponse<List<Receta>>;

      final inventario = invResult.isSuccess ? (invResult.data?.productos ?? []) : <Map<String, dynamic>>[];
      final recetas    = recetaResult.isSuccess ? (recetaResult.data ?? <Receta>[]) : <Receta>[];

      final byCode = <String, Map<String, dynamic>>{};
      final byName = <String, Map<String, dynamic>>{};
      for (final p in inventario) {
        final code = (p['codigo'] ?? '').toString();
        final name = (p['nombre'] ?? '').toString().toLowerCase().trim();
        if (code.isNotEmpty) byCode[code] = p;
        if (name.isNotEmpty) byName[name] = p;
      }

      final stockMap = <String, double>{};
      for (final p in inventario) {
        stockMap[(p['codigo'] ?? '').toString()] = (p['stock'] as num?)?.toDouble() ?? 0;
      }

      final planItems = <PlanItem>[];
      for (final pp in pedidoProductos) {
        final nombre   = (pp['nombre'] ?? '').toString();
        final cantidad = (pp['cantidad'] as num?)?.toDouble() ?? 1;
        final codigo   = (pp['codigo'] ?? '').toString();

        Map<String, dynamic>? inv = codigo.isNotEmpty ? byCode[codigo] : null;
        inv ??= byName[nombre.toLowerCase().trim()];

        final invCodigo   = inv != null ? (inv['codigo'] ?? '').toString() : '';
        final stockActual = inv != null ? ((inv['stock'] as num?)?.toDouble() ?? 0) : 0.0;
        final deficit     = (cantidad - stockActual).clamp(0, double.infinity);
        final cubierto    = deficit == 0;
        final parcial     = !cubierto && stockActual > 0;

        final sugerencias = <RecetaSugerencia>[];
        if (invCodigo.isNotEmpty) {
          for (final r in recetas) {
            if (r.codigoDestino != invCodigo) continue;
            final stockOrigen       = stockMap[r.codigoOrigen] ?? 0;
            final batchesNecesarios = deficit > 0 ? (deficit / r.cantidadDestino).ceil() : 0;
            final origenNecesario   = batchesNecesarios * r.cantidadOrigen;
            final posible           = stockOrigen >= origenNecesario;
            final maxProducible     = r.cantidadOrigen > 0 ? (stockOrigen / r.cantidadOrigen).floor() * r.cantidadDestino : 0.0;

            final origenInv    = byCode[r.codigoOrigen];
            final origenNombre = r.nombreOrigen.isNotEmpty ? r.nombreOrigen : (origenInv?['nombre'] ?? r.codigoOrigen).toString();

            sugerencias.add(RecetaSugerencia(
              recetaId:                r.id,
              descripcion:             r.descripcion,
              codigoOrigen:            r.codigoOrigen,
              nombreOrigen:            origenNombre,
              stockOrigen:             stockOrigen,
              cantidadOrigen:          r.cantidadOrigen,
              cantidadDestino:         r.cantidadDestino,
              origenNecesario:         origenNecesario.toDouble(),
              posible:                 posible,
              maxProducible:           maxProducible.toDouble(),
              stockOrigenInsuficiente: posible ? 0 : origenNecesario - stockOrigen,
            ));
          }
          sugerencias.sort((a, b) => b.posible ? 1 : -1);
        }

        planItems.add(PlanItem(
          codigo:      invCodigo.isNotEmpty ? invCodigo : nombre,
          nombre:      inv != null ? (inv['nombre'] ?? nombre).toString() : nombre,
          cantidad:    cantidad,
          stockActual: stockActual,
          deficit:     deficit.toDouble(),
          cubierto:    cubierto,
          parcial:     parcial,
          sugerencias: sugerencias,
        ));
      }

      final pedidoId     = widget.pedido['id']?.toString() ?? '';
      final todoCubierto = planItems.every((p) => p.cubierto);
      final sinStock     = planItems.any((p) => p.stockActual == 0 && !p.cubierto);

      if (mounted) setState(() {
        _loading = false;
        _plan = FulfillmentPlan(
          pedidoId:       pedidoId,
          plan:           planItems,
          todoCubierto:   todoCubierto,
          algunoSinStock: sinStock,
        );
      });
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = e.toString(); });
    }
  }

  // ── Conversion sheet ────────────────────────────────────────

  void _mostrarConvertirDesdeReceta(RecetaSugerencia sug, PlanItem item) {
    final cantidadOrigen  = (item.deficit > 0)
        ? (item.deficit / sug.cantidadDestino * sug.cantidadOrigen).ceil().toDouble()
        : sug.cantidadOrigen;
    final cantidadDestino = (item.deficit > 0) ? item.deficit : sug.cantidadDestino;

    final origenCtrl  = TextEditingController(text: cantidadOrigen.toStringAsFixed(cantidadOrigen == cantidadOrigen.roundToDouble() ? 0 : 2));
    final destinoCtrl = TextEditingController(text: cantidadDestino.toStringAsFixed(cantidadDestino == cantidadDestino.roundToDouble() ? 0 : 2));

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(builder: (ctx, ss) {
        Future<void> confirmar() async {
          final usarOrigen     = double.tryParse(origenCtrl.text.trim()) ?? 0;
          final produceDestino = double.tryParse(destinoCtrl.text.trim()) ?? 0;
          if (usarOrigen <= 0 || produceDestino <= 0) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Las cantidades deben ser mayores a 0'), backgroundColor: Colors.orange),
            );
            return;
          }
          if (usarOrigen > sug.stockOrigen) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Stock insuficiente de ${sug.nombreOrigen} (disponible: ${sug.stockOrigen})'),
                backgroundColor: Colors.orange,
              ),
            );
            return;
          }
          Navigator.pop(ctx);

          final restar = await ApiService.actualizarStock(
            codigo: sug.codigoOrigen,
            cantidad: usarOrigen.round(),
            operacion: 'restar',
          );
          if (!restar.isSuccess) {
            if (mounted) ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Error al descontar origen: ${restar.error}'), backgroundColor: Colors.orange),
            );
            return;
          }
          final agregar = await ApiService.actualizarStock(
            codigo: item.codigo,
            cantidad: produceDestino.round(),
            operacion: 'agregar',
          );
          if (!agregar.isSuccess) {
            await ApiService.actualizarStock(codigo: sug.codigoOrigen, cantidad: usarOrigen.round(), operacion: 'agregar');
            if (mounted) ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Error al agregar destino (revertido): ${agregar.error}'), backgroundColor: Colors.orange),
            );
            return;
          }
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('-${usarOrigen.toStringAsFixed(0)} ${sug.nombreOrigen}  →  +${produceDestino.toStringAsFixed(0)} ${item.nombre}'),
                backgroundColor: const Color(0xFF00695C),
              ),
            );
            widget.onStockActualizado();
            _cargarPlan();
          }
        }

        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: EdgeInsets.only(
            left: 20, right: 20, top: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(child: Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
                )),
                const SizedBox(height: 16),
                Row(children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: const Color(0xFFE0F2F1), shape: BoxShape.circle),
                    child: const Icon(Icons.transform_rounded, color: Color(0xFF00695C), size: 20),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Producir desde receta', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                    if (sug.descripcion.isNotEmpty)
                      Text(sug.descripcion, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                  ])),
                ]),
                const SizedBox(height: 20),
                _infoCard(icon: Icons.inventory_2_outlined, color: Colors.blueGrey.shade600,
                  label: 'Origen (consumir)', title: sug.nombreOrigen,
                  badge: 'Stock: ${sug.stockOrigen.toStringAsFixed(0)}'),
                const SizedBox(height: 12),
                _label('Cantidad a consumir'),
                _numField(origenCtrl, hint: '0', suffix: 'uds', onChanged: (_) => ss(() {})),
                const SizedBox(height: 16),
                Center(child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(color: Colors.grey.shade100, shape: BoxShape.circle),
                  child: Icon(Icons.arrow_downward_rounded, color: Colors.grey.shade500, size: 18),
                )),
                const SizedBox(height: 16),
                _infoCard(icon: Icons.shopping_bag_outlined, color: const Color(0xFF00695C),
                  label: 'Destino (producir)', title: item.nombre,
                  badge: 'Pedido: ${item.cantidad.toStringAsFixed(0)}'),
                const SizedBox(height: 12),
                _label('Unidades que produce'),
                _numField(destinoCtrl, hint: '0', suffix: 'uds', onChanged: (_) => ss(() {})),
                if ((double.tryParse(origenCtrl.text) ?? 0) > 0 && (double.tryParse(destinoCtrl.text) ?? 0) > 0) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Row(children: [
                      Icon(Icons.swap_horiz_rounded, size: 16, color: Colors.grey.shade500),
                      const SizedBox(width: 8),
                      Expanded(child: Text(
                        '-${origenCtrl.text} ${sug.nombreOrigen}  →  +${destinoCtrl.text} ${item.nombre}',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                      )),
                    ]),
                  ),
                ],
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: confirmar,
                    icon: const Icon(Icons.transform_rounded),
                    label: const Text('Confirmar producción', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00695C),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }

  // ── Build ────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section header
        Row(children: [
          const Icon(Icons.inventory_2_outlined, size: 16, color: Color(0xFF455A64)),
          const SizedBox(width: 8),
          const Expanded(
            child: Text('Disponibilidad de stock',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF37474F))),
          ),
          if (!_loading)
            GestureDetector(
              onTap: _cargarPlan,
              child: Icon(Icons.refresh_rounded, size: 17, color: Colors.grey.shade400),
            ),
        ]),
        const SizedBox(height: 12),

        if (_loading)
          const Center(child: Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: CircularProgressIndicator(strokeWidth: 2),
          ))
        else if (_plan == null)
          _buildVerificarButton()
        else if (_error != null)
          _errorCard()
        else if (_plan!.plan.isEmpty)
          _emptyCard()
        else ...[
          _buildSummaryBadge(),
          const SizedBox(height: 10),
          ..._plan!.plan.map(_buildProductoCard),
        ],
      ],
    );
  }

  // ── Summary ──────────────────────────────────────────────────

  Widget _buildSummaryBadge() {
    final plan = _plan!;
    if (plan.todoCubierto) {
      return _summaryRow(
        icon: Icons.check_circle_outline_rounded,
        color: _colorOk,
        text: 'Stock completo para atender el pedido',
      );
    }
    final faltantes = plan.plan.where((p) => !p.cubierto).length;
    final cubiertos  = plan.plan.length - faltantes;
    return _summaryRow(
      icon: Icons.info_outline_rounded,
      color: _colorPending,
      text: cubiertos > 0
          ? '$cubiertos de ${plan.plan.length} productos cubiertos — $faltantes pendiente${faltantes > 1 ? 's' : ''}'
          : '$faltantes producto${faltantes > 1 ? 's' : ''} pendiente${faltantes > 1 ? 's' : ''} de preparación',
    );
  }

  Widget _summaryRow({required IconData icon, required Color color, required String text}) =>
    Row(children: [
      Icon(icon, size: 15, color: color),
      const SizedBox(width: 6),
      Expanded(child: Text(text,
        style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600))),
    ]);

  // ── Product card ─────────────────────────────────────────────

  Widget _buildProductoCard(PlanItem item) {
    final isExpanded = _expanded.contains(item.codigo);

    Color stripColor;
    Color pillBg;
    Color pillText;
    IconData statusIcon;
    String statusLabel;

    if (item.cubierto) {
      stripColor  = const Color(0xFFA5D6A7); // green.200
      pillBg      = const Color(0xFFE8F5E9);
      pillText    = _colorOk;
      statusIcon  = Icons.check_rounded;
      statusLabel = 'Cubierto';
    } else if (item.parcial) {
      stripColor  = const Color(0xFFFFCC80); // orange.200
      pillBg      = const Color(0xFFFFF3E0);
      pillText    = _colorPartial;
      statusIcon  = Icons.remove_circle_outline_rounded;
      statusLabel = 'Parcial';
    } else {
      stripColor  = const Color(0xFFB0BEC5); // blueGrey.200 — calm, not red
      pillBg      = const Color(0xFFECEFF1);
      pillText    = _colorPending;
      statusIcon  = Icons.build_outlined;
      statusLabel = 'Preparar';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6, offset: const Offset(0, 2))],
      ),
      clipBehavior: Clip.hardEdge,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Left accent strip
            Container(width: 4, color: stripColor),

            // Card body
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Main row
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
                    child: Row(children: [
                      // Product info
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(item.nombre,
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                          overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 4),
                        Row(children: [
                          _metaChip('Pedido ${item.cantidad.toStringAsFixed(0)}'),
                          const SizedBox(width: 6),
                          _metaChip('Stock ${item.stockActual.toStringAsFixed(0)}'),
                          if (!item.cubierto) ...[
                            const SizedBox(width: 6),
                            _metaChip('Faltan ${item.deficit.toStringAsFixed(0)}', color: pillText),
                          ],
                        ]),
                      ])),
                      const SizedBox(width: 10),

                      // Right side: status pill + expand button
                      Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                        // Status pill
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(color: pillBg, borderRadius: BorderRadius.circular(20)),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(statusIcon, size: 11, color: pillText),
                            const SizedBox(width: 3),
                            Text(statusLabel, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: pillText)),
                          ]),
                        ),

                        // Expand button (if recipes exist)
                        if (item.sugerencias.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          GestureDetector(
                            onTap: () => setState(() {
                              if (isExpanded) _expanded.remove(item.codigo);
                              else _expanded.add(item.codigo);
                            }),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: const Color(0xFFE0F2F1),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Row(mainAxisSize: MainAxisSize.min, children: [
                                Icon(
                                  isExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                                  size: 13, color: _colorRecipe,
                                ),
                                const SizedBox(width: 2),
                                Text(
                                  item.cubierto ? 'Transformar' : '${item.sugerencias.length} receta${item.sugerencias.length > 1 ? 's' : ''}',
                                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: _colorRecipe),
                                ),
                              ]),
                            ),
                          ),
                        ],
                      ]),
                    ]),
                  ),

                  // Suggestions (expanded)
                  if (isExpanded && item.sugerencias.isNotEmpty) ...[
                    Divider(height: 1, color: Colors.grey.shade100),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.cubierto ? 'Transformar desde otro producto' : 'Opciones de producción',
                            style: TextStyle(fontSize: 11, color: Colors.grey.shade500, fontWeight: FontWeight.w600, letterSpacing: 0.3),
                          ),
                          const SizedBox(height: 8),
                          ...item.sugerencias.map((sug) => _buildSugerenciaCard(sug, item)),
                        ],
                      ),
                    ),
                  ],

                  // No recipes hint — only when not covered
                  if (!item.cubierto && item.sugerencias.isEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                      child: Text(
                        'Sin recetas configuradas. Agrégalas en el detalle del producto.',
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Suggestion card ──────────────────────────────────────────

  Widget _buildSugerenciaCard(RecetaSugerencia sug, PlanItem item) {
    final canProduce = sug.maxProducible > 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Origin product name + capacity
        Row(children: [
          Expanded(child: Text(sug.nombreOrigen,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            overflow: TextOverflow.ellipsis)),
          if (canProduce)
            Text('produce ${sug.maxProducible.toStringAsFixed(0)} uds',
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: _colorRecipe)),
        ]),
        const SizedBox(height: 4),

        // Conversion ratio
        Text(
          '${_fmt(sug.cantidadOrigen)} uds  →  ${_fmt(sug.cantidadDestino)} uds de ${item.nombre}',
          style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
        ),

        // Stock available
        const SizedBox(height: 2),
        Row(children: [
          Text('Disponible: ${sug.stockOrigen.toStringAsFixed(0)} uds',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
          if (!sug.posible && item.deficit > 0) ...[
            const SizedBox(width: 8),
            Text('· faltan ${sug.stockOrigenInsuficiente.toStringAsFixed(0)} uds de origen',
              style: TextStyle(fontSize: 11, color: Colors.amber.shade700)),
          ],
        ]),

        if (sug.descripcion.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(sug.descripcion, style: TextStyle(fontSize: 11, color: Colors.grey.shade400, fontStyle: FontStyle.italic)),
        ],

        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: FilledButton.tonal(
            onPressed: () => _mostrarConvertirDesdeReceta(sug, item),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFE0F2F1),
              foregroundColor: _colorRecipe,
              padding: const EdgeInsets.symmetric(vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Icon(Icons.transform_rounded, size: 15),
              const SizedBox(width: 6),
              Text(sug.posible ? 'Producir' : 'Producir con lo disponible'),
            ]),
          ),
        ),
      ]),
    );
  }

  // ── State cards ──────────────────────────────────────────────

  Widget _buildVerificarButton() => GestureDetector(
    onTap: _cargarPlan,
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
      decoration: BoxDecoration(
        color: const Color(0xFFE0F2F1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF80CBC4)),
      ),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.inventory_2_outlined, size: 18, color: Color(0xFF00695C)),
          SizedBox(width: 10),
          Text('Verificar disponibilidad de stock',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: Color(0xFF00695C),
                fontSize: 14,
              )),
        ],
      ),
    ),
  );

  Widget _errorCard() => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.grey.shade50,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: Colors.grey.shade200),
    ),
    child: Row(children: [
      Icon(Icons.cloud_off_outlined, color: Colors.grey.shade400, size: 18),
      const SizedBox(width: 8),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('No se pudo cargar la disponibilidad',
          style: TextStyle(color: Colors.grey.shade700, fontWeight: FontWeight.w600, fontSize: 13)),
        if (_error != null)
          Text(_error!, style: TextStyle(color: Colors.grey.shade400, fontSize: 11)),
        const SizedBox(height: 6),
        GestureDetector(
          onTap: _cargarPlan,
          child: Text('Intentar de nuevo',
            style: TextStyle(color: Colors.blueGrey.shade600, fontSize: 12, decoration: TextDecoration.underline)),
        ),
      ])),
    ]),
  );

  Widget _emptyCard() => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(10)),
    child: Row(children: [
      Icon(Icons.info_outline, color: Colors.grey.shade400, size: 18),
      const SizedBox(width: 8),
      Expanded(child: Text(
        'Los productos de este pedido no tienen códigos vinculados al inventario.',
        style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
      )),
    ]),
  );

  // ── Helpers ──────────────────────────────────────────────────

  String _fmt(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

  Widget _metaChip(String label, {Color? color}) => Text(
    label,
    style: TextStyle(fontSize: 11, color: color ?? Colors.grey.shade500),
  );

  Widget _infoCard({required IconData icon, required Color color, required String label, required String title, required String badge}) =>
    Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.15)),
      ),
      child: Row(children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 8),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w600)),
          Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        ])),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
          child: Text(badge, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
        ),
      ]),
    );

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(text, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
  );

  Widget _numField(TextEditingController ctrl, {String? hint, String? suffix, required Function(String) onChanged}) =>
    TextField(
      controller: ctrl,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      onChanged: onChanged,
      decoration: InputDecoration(
        hintText: hint,
        suffixText: suffix,
        filled: true,
        fillColor: Colors.grey.shade50,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      ),
    );
}
