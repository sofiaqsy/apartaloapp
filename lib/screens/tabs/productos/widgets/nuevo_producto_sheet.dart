import 'package:flutter/material.dart';
import '../../../../theme/fincas_tokens.dart';
import '../../../../widgets/fincas_widgets.dart';

/// Hoja de "Nuevo producto": se abre directo en la entrada manual (solo el nombre).
///
/// [onCrear] recibe el nombre y devuelve null si se creó o un mensaje de error si falló.
/// Devuelve true cuando el producto se creó (la hoja se cierra sola).
Future<bool?> showNuevoProductoSheet(
  BuildContext context, {
  required Future<String?> Function(String nombre) onCrear,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) => _NuevoProductoForm(onCrear: onCrear),
  );
}

class _NuevoProductoForm extends StatefulWidget {
  const _NuevoProductoForm({required this.onCrear});
  final Future<String?> Function(String nombre) onCrear;

  @override
  State<_NuevoProductoForm> createState() => _NuevoProductoFormState();
}

class _NuevoProductoFormState extends State<_NuevoProductoForm> {
  // El estado de la hoja es dueño del controlador: se libera cuando la hoja desaparece de verdad.
  final _nombre = TextEditingController();
  bool _creando = false;
  String? _error;

  bool get _ocupado => _creando;

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
            FincasTextButton(label: 'Cancelar', onPressed: _ocupado ? null : () => Navigator.pop(context, false)),
          ],
        ),
      ),
    );
  }
}
