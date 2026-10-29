import 'package:flutter/material.dart';

/// Botón flotante "Nuevo" (naranja, como antes). Mientras se abre el formulario muestra un indicador y el texto
/// "Abriendo..." para que el toque se note al instante; un segundo toque se ignora.
class NuevoProductoFab extends StatelessWidget {
  const NuevoProductoFab({super.key, required this.abriendo, required this.onPressed});
  final bool abriendo;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: abriendo ? 'Nuevo producto, abriendo' : 'Nuevo producto',
      excludeSemantics: true,
      child: FloatingActionButton.extended(
        heroTag: 'fab_nuevo_producto',
        onPressed: abriendo ? () {} : onPressed, // sigue con su color; el toque repetido no hace nada
        backgroundColor: Colors.orange.shade600,
        icon: abriendo
            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
            : const Icon(Icons.add, color: Colors.white),
        label: Text(abriendo ? 'Abriendo...' : 'Nuevo', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
      ),
    );
  }
}
