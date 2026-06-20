import 'package:flutter/material.dart';
import '../services/api_service.dart';

/// Bottom sheet to request more stock from a provider business (B2B)
class SolicitarMasSheet extends StatefulWidget {
  final Map<String, dynamic> producto;
  final String proveedorId;
  final String proveedorNombre;

  const SolicitarMasSheet({
    super.key,
    required this.producto,
    required this.proveedorId,
    required this.proveedorNombre,
  });

  @override
  State<SolicitarMasSheet> createState() => _SolicitarMasSheetState();
}

class _SolicitarMasSheetState extends State<SolicitarMasSheet> {
  final _cantidadController = TextEditingController(text: '1');
  final _observacionesController = TextEditingController();
  bool _isLoading = false;

  double get _precio => (widget.producto['precio'] ?? 0).toDouble();
  int get _cantidad => int.tryParse(_cantidadController.text.trim()) ?? 1;
  double get _total => _precio * _cantidad;

  Future<void> _enviarSolicitud() async {
    final cantidad = _cantidad;
    if (cantidad <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ingresa una cantidad válida'), backgroundColor: Colors.red),
      );
      return;
    }

    setState(() => _isLoading = true);

    final result = await ApiService.crearPedidoB2B(
      proveedorId: widget.proveedorId,
      productos: [
        {
          'codigo': widget.producto['codigo'],
          'nombre': widget.producto['nombre'],
          'cantidad': cantidad,
          'precio': _precio,
        }
      ],
      total: _total,
      observaciones: _observacionesController.text.trim().isNotEmpty
          ? _observacionesController.text.trim()
          : null,
    );

    setState(() => _isLoading = false);

    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.isSuccess
              ? '✅ Solicitud enviada a ${widget.proveedorNombre}'
              : 'Error: ${result.error}'),
          backgroundColor: result.isSuccess ? Colors.green : Colors.red,
        ),
      );
    }
  }

  @override
  void dispose() {
    _cantidadController.dispose();
    _observacionesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottomInset),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle
          Center(
            child: Container(
              width: 40, height: 4,
              decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(height: 16),

          // Header
          Row(
            children: [
              const Icon(Icons.shopping_cart_outlined, color: Colors.deepPurple),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Solicitar más', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    Text('Proveedor: ${widget.proveedorNombre}', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 12),

          // Product info
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.deepPurple.shade50,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                const Icon(Icons.inventory_2_outlined, color: Colors.deepPurple, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    widget.producto['nombre'] ?? '',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                Text('S/ ${_precio.toStringAsFixed(2)}', style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Cantidad
          const Text('Cantidad a solicitar', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          const SizedBox(height: 8),
          Row(
            children: [
              IconButton(
                onPressed: () {
                  final v = _cantidad - 1;
                  if (v >= 1) setState(() => _cantidadController.text = v.toString());
                },
                icon: const Icon(Icons.remove_circle_outline),
                color: Colors.deepPurple,
              ),
              Expanded(
                child: TextField(
                  controller: _cantidadController,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
              IconButton(
                onPressed: () => setState(() => _cantidadController.text = (_cantidad + 1).toString()),
                icon: const Icon(Icons.add_circle_outline),
                color: Colors.deepPurple,
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Observaciones
          TextField(
            controller: _observacionesController,
            maxLines: 2,
            decoration: InputDecoration(
              labelText: 'Observaciones (opcional)',
              hintText: 'Ej: urgente, presentación especial...',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
          const SizedBox(height: 20),

          // Total + button
          Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Total estimado', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  Text('S/ ${_total.toStringAsFixed(2)}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.deepPurple)),
                ],
              ),
              const SizedBox(width: 16),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _isLoading ? null : _enviarSolicitud,
                  icon: _isLoading
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.send),
                  label: Text(_isLoading ? 'Enviando...' : 'Enviar solicitud'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepPurple,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
