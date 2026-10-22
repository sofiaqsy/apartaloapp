import 'package:flutter/material.dart';
import '../../../../theme/fincas_tokens.dart';
import '../../../../widgets/fincas_widgets.dart';

/// Hoja de "Nuevo producto": se abre directo en la entrada manual (solo el nombre).
/// Escanear un código y tomar una foto siguen disponibles como acciones secundarias debajo.
///
/// [onCrear] recibe el nombre y devuelve null si se creó o un mensaje de error si falló.
/// Devuelve true cuando el producto se creó (la hoja se cierra sola).
Future<bool?> showNuevoProductoSheet(
  BuildContext context, {
  required Future<String?> Function(String nombre) onCrear,
  required VoidCallback onEscanear,
  required VoidCallback onFoto,
  Duration pausa = const Duration(milliseconds: 150),
}) {
  return showModalBottomSheet<bool>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) => _NuevoProductoForm(onCrear: onCrear, onEscanear: onEscanear, onFoto: onFoto, pausa: pausa),
  );
}

class _NuevoProductoForm extends StatefulWidget {
  const _NuevoProductoForm({required this.onCrear, required this.onEscanear, required this.onFoto, required this.pausa});
  final Future<String?> Function(String nombre) onCrear;
  final VoidCallback onEscanear;
  final VoidCallback onFoto;
  final Duration pausa;

  @override
  State<_NuevoProductoForm> createState() => _NuevoProductoFormState();
}

class _NuevoProductoFormState extends State<_NuevoProductoForm> {
  // El estado de la hoja es dueño del controlador: se libera cuando la hoja desaparece de verdad.
  final _nombre = TextEditingController();
  bool _creando = false;
  String? _eligiendo; // 'scan' o 'foto': muestra un indicador al instante, antes de abrir la cámara
  String? _error;

  bool get _ocupado => _creando || _eligiendo != null;

  @override
  void dispose() {
    _nombre.dispose();
    super.dispose();
  }

  Future<void> _crear() async {
    if (_ocupado) return;
    final nombre = _nombre.text.trim();
    if (nombre.isEmpty) {
      setState(() => _error = 'Ingresa el nombre del producto');
      return;
    }
    setState(() { _creando = true; _error = null; });
    final error = await widget.onCrear(nombre);
    if (!mounted) return;
    if (error == null) {
      Navigator.pop(context, true);
    } else {
      setState(() { _creando = false; _error = error; });
    }
  }

  Future<void> _elegir(String id, VoidCallback accion) async {
    if (_ocupado) return;
    setState(() => _eligiendo = id);
    await Future.delayed(widget.pausa); // deja pintar el indicador antes de cerrar
    if (!mounted) return;
    Navigator.pop(context, false);
    accion();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        // Sube con el teclado
        padding: EdgeInsets.fromLTRB(FincasSpacing.screenH, 0, FincasSpacing.screenH, FincasSpacing.l + MediaQuery.of(context).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Nuevo producto', style: FincasText.screenTitle),
            const SizedBox(height: FincasSpacing.xs),
            const Text('Luego podrás agregar presentaciones con precio y stock.', style: FincasText.bodySecondary),
            const SizedBox(height: FincasSpacing.l),
            TextField(
              controller: _nombre,
              autofocus: true,
              enabled: !_ocupado,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _crear(),
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
              decoration: InputDecoration(labelText: 'Nombre del producto', hintText: 'Ej: Café Blend', errorText: _error),
            ),
            const SizedBox(height: FincasSpacing.l),
            FincasPrimaryButton(label: 'Crear y configurar', onPressed: _ocupado ? null : _crear, loading: _creando),
            const SizedBox(height: FincasSpacing.l),
            const Text('O agrégalo con', textAlign: TextAlign.center, style: FincasText.caption),
            const SizedBox(height: FincasSpacing.s),
            Row(
              children: [
                Expanded(child: _Secundaria(label: 'Escanear código', cargando: _eligiendo == 'scan', deshabilitada: _ocupado, onTap: () => _elegir('scan', widget.onEscanear))),
                const SizedBox(width: FincasSpacing.s),
                Expanded(child: _Secundaria(label: 'Tomar foto', cargando: _eligiendo == 'foto', deshabilitada: _ocupado, onTap: () => _elegir('foto', widget.onFoto))),
              ],
            ),
            FincasTextButton(label: 'Cancelar', onPressed: _ocupado ? null : () => Navigator.pop(context, false)),
          ],
        ),
      ),
    );
  }
}

class _Secundaria extends StatelessWidget {
  const _Secundaria({required this.label, required this.cargando, required this.deshabilitada, required this.onTap});
  final String label;
  final bool cargando;
  final bool deshabilitada;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: !deshabilitada,
      label: cargando ? '$label, cargando' : label,
      excludeSemantics: true,
      child: SizedBox(
        height: FincasSpacing.minTouch,
        child: OutlinedButton(
          onPressed: deshabilitada ? null : onTap,
          style: OutlinedButton.styleFrom(
            disabledForegroundColor: cargando ? FincasColors.ink : FincasColors.disabledText,
            padding: const EdgeInsets.symmetric(horizontal: FincasSpacing.s),
          ),
          child: cargando
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5))
              : Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: FincasText.button.copyWith(fontSize: 14)),
        ),
      ),
    );
  }
}
