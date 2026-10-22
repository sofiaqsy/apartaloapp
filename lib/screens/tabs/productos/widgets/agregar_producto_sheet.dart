import 'package:flutter/material.dart';
import '../../../../theme/fincas_tokens.dart';
import '../../../../widgets/fincas_widgets.dart';

/// Hoja "Agregar producto". Al tocar una opción se muestra un indicador al instante (la cámara o el
/// formulario tardan en abrir), las otras opciones se desactivan y un segundo toque se ignora.
/// Cierra la hoja y luego llama a la acción elegida.
Future<void> showAgregarProductoSheet(
  BuildContext context, {
  required VoidCallback onEscanear,
  required VoidCallback onFoto,
  required VoidCallback onManual,
  Duration pausa = const Duration(milliseconds: 150),
}) {
  String? cargando;
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true, // sin tope de 9/16 de la pantalla; el contenido hace scroll si no cabe
    useSafeArea: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSheet) {
        Future<void> elegir(String id, VoidCallback accion) async {
          if (cargando != null) return;
          setSheet(() => cargando = id);
          await Future.delayed(pausa); // deja pintar el indicador antes de cerrar
          if (ctx.mounted) Navigator.pop(ctx);
          accion();
        }

        Widget opcion(String id, IconData icono, String titulo, String subtitulo, VoidCallback accion) => Padding(
              padding: const EdgeInsets.only(bottom: FincasSpacing.s),
              child: _Opcion(
                icon: icono,
                titulo: titulo,
                subtitulo: subtitulo,
                cargando: cargando == id,
                deshabilitada: cargando != null && cargando != id,
                onTap: () => elegir(id, accion),
              ),
            );

        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(FincasSpacing.screenH, 0, FincasSpacing.screenH, FincasSpacing.l),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Agregar producto', style: FincasText.screenTitle),
                const SizedBox(height: FincasSpacing.xs),
                const Text('Elige cómo quieres agregar el producto', style: FincasText.bodySecondary),
                const SizedBox(height: FincasSpacing.l),
                opcion('scan', Icons.qr_code_scanner, 'Escanear código de barras', 'Busca info automáticamente', onEscanear),
                opcion('foto', Icons.camera_alt, 'Tomar foto del producto', 'Guarda imagen del producto', onFoto),
                opcion('manual', Icons.edit, 'Ingresar manualmente', 'Escribe nombre y precio', onManual),
                FincasTextButton(label: 'Cancelar', onPressed: cargando != null ? null : () => Navigator.pop(ctx)),
              ],
            ),
          ),
        );
      },
    ),
  );
}

class _Opcion extends StatelessWidget {
  const _Opcion({
    required this.icon,
    required this.titulo,
    required this.subtitulo,
    required this.onTap,
    required this.cargando,
    required this.deshabilitada,
  });
  final IconData icon;
  final String titulo;
  final String subtitulo;
  final VoidCallback onTap;
  final bool cargando;
  final bool deshabilitada;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: !deshabilitada,
      label: cargando ? '$titulo, cargando' : '$titulo. $subtitulo',
      excludeSemantics: true,
      child: Opacity(
        opacity: deshabilitada ? 0.5 : 1,
        child: FincasCard(
          onTap: (cargando || deshabilitada) ? null : onTap,
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: FincasColors.sand, borderRadius: BorderRadius.circular(FincasRadii.medium)),
                child: Icon(icon, color: FincasColors.espresso, size: 24),
              ),
              const SizedBox(width: FincasSpacing.m),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(titulo, style: FincasText.sectionTitle.copyWith(fontSize: 16)),
                    Text(cargando ? 'Abriendo...' : subtitulo, style: FincasText.metadata),
                  ],
                ),
              ),
              cargando
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                  : const Icon(Icons.chevron_right, color: FincasColors.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}
