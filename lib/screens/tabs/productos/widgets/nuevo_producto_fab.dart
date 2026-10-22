import 'package:flutter/material.dart';
import '../../../../theme/fincas_tokens.dart';

/// Botón flotante "Nuevo producto". Mientras se abre el formulario muestra un indicador y el texto
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
        shape: const StadiumBorder(),
        label: AnimatedSwitcher(
          duration: const Duration(milliseconds: 150),
          child: abriendo
              ? const Row(
                  key: ValueKey('abriendo'),
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.5, color: FincasColors.textOnInk)),
                    SizedBox(width: FincasSpacing.s),
                    Text('Abriendo...'),
                  ],
                )
              : const Text('Nuevo producto', key: ValueKey('normal')),
        ),
      ),
    );
  }
}
