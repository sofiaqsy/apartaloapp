import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../services/api_service.dart';
import '../theme/fincas_tokens.dart';
import 'fincas_widgets.dart';

typedef ElegirFoto = Future<File?> Function(ImageSource origen);
typedef SubirFoto = Future<String?> Function(File archivo);
typedef QuitarFoto = Future<String?> Function(FotoPresentacion foto);

/// Fotos de una presentación (hasta [ApiService.maxFotosPresentacion]): miniaturas con "Quitar" y un botón para
/// agregar desde la cámara o la galería. Muestra un indicador mientras se sube y avisa si algo falla.
class PresentacionFotos extends StatefulWidget {
  const PresentacionFotos({
    super.key,
    required this.fotos,
    required this.onSubir,
    required this.onQuitar,
    ElegirFoto? elegir,
    this.max = 3,
  }) : _elegir = elegir;

  final List<FotoPresentacion> fotos;

  /// Sube el archivo; devuelve null si salió bien o el mensaje de error. Después la pantalla recarga las fotos.
  final SubirFoto onSubir;
  final QuitarFoto onQuitar;
  final ElegirFoto? _elegir;
  final int max;

  /// Tamaño razonable para una foto de producto (1280 px): se procesa y se sube más rápido que una foto completa
  /// de 48 megapíxeles. `requestFullMetadata: false` evita pedir el permiso de la fototeca y leer los metadatos
  /// completos, trabajo extra que hace más lenta la cámara y que aquí no se necesita.
  static Future<File?> _elegirPorDefecto(ImageSource origen) async {
    final x = await ImagePicker().pickImage(
      source: origen,
      maxWidth: 1280,
      maxHeight: 1280,
      imageQuality: 80,
      requestFullMetadata: false,
      preferredCameraDevice: CameraDevice.rear,
    );
    return x == null ? null : File(x.path);
  }

  @override
  State<PresentacionFotos> createState() => _PresentacionFotosState();
}

class _PresentacionFotosState extends State<PresentacionFotos> {
  bool _subiendo = false; // hay una foto en curso (abriendo la cámara o subiendo)
  bool _abriendo = false; // todavía se está abriendo la cámara o la galería
  String? _quitandoId;
  String? _error;

  bool get _ocupado => _subiendo || _quitandoId != null;
  bool get _llena => widget.fotos.length >= widget.max;

  Future<void> _agregar() async {
    if (_ocupado || _llena) return;
    final origen = await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(FincasSpacing.screenH, 0, FincasSpacing.screenH, FincasSpacing.l),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const FincasSectionHeader('Agregar foto'),
              FincasSecondaryButton(label: 'Tomar foto', onPressed: () => Navigator.pop(ctx, ImageSource.camera)),
              const SizedBox(height: FincasSpacing.s),
              FincasSecondaryButton(label: 'Elegir de la galería', onPressed: () => Navigator.pop(ctx, ImageSource.gallery)),
              FincasTextButton(label: 'Cancelar', onPressed: () => Navigator.pop(ctx)),
            ],
          ),
        ),
      ),
    );
    if (origen == null || !mounted) return;
    setState(() { _subiendo = true; _abriendo = true; _error = null; });
    String? error;
    try {
      final archivo = await (widget._elegir ?? PresentacionFotos._elegirPorDefecto)(origen);
      if (archivo == null) {
        if (mounted) setState(() { _subiendo = false; _abriendo = false; });
        return; // canceló la cámara o la galería
      }
      if (mounted) setState(() => _abriendo = false); // ya hay foto: ahora se sube
      error = await widget.onSubir(archivo);
    } catch (_) {
      error = 'No se pudo abrir la cámara o la galería.';
    }
    if (!mounted) return;
    setState(() { _subiendo = false; _abriendo = false; _error = error; });
  }

  Future<void> _quitar(FotoPresentacion foto) async {
    if (_ocupado) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Quitar foto'),
        content: const Text('La foto se eliminará de esta presentación.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), style: TextButton.styleFrom(foregroundColor: FincasColors.error), child: const Text('Quitar')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() { _quitandoId = foto.id; _error = null; });
    final error = await widget.onQuitar(foto);
    if (!mounted) return;
    setState(() { _quitandoId = null; _error = error; });
  }

  Widget _miniatura(FotoPresentacion f) {
    final quitando = _quitandoId == f.id;
    return SizedBox(
      width: 96,
      child: Column(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(FincasRadii.medium),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Image.network(f.url, width: 96, height: 96, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(width: 96, height: 96, color: FincasColors.sand)),
                if (quitando) Container(width: 96, height: 96, color: FincasColors.background.withValues(alpha: 0.8), alignment: Alignment.center, child: const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5))),
              ],
            ),
          ),
          TextButton(
            onPressed: _ocupado ? null : () => _quitar(f),
            style: TextButton.styleFrom(foregroundColor: FincasColors.error, minimumSize: const Size(0, 44)),
            child: const Text('Quitar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Fotos', style: FincasText.label),
        Text('Hasta ${widget.max} fotos de esta presentación', style: FincasText.caption),
        const SizedBox(height: FincasSpacing.s),
        if (widget.fotos.isNotEmpty)
          Wrap(
            spacing: FincasSpacing.s,
            runSpacing: FincasSpacing.xs,
            children: [
              for (final f in widget.fotos) _miniatura(f),
            ],
          ),
        if (_subiendo)
          Padding(
            padding: const EdgeInsets.only(top: FincasSpacing.s),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: FincasSpacing.l, vertical: FincasSpacing.m),
              decoration: BoxDecoration(color: FincasColors.sand, borderRadius: BorderRadius.circular(FincasRadii.medium)),
              child: Row(
                children: [
                  const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5)),
                  const SizedBox(width: FincasSpacing.m),
                  Expanded(
                    child: Semantics(
                      liveRegion: true,
                      child: Text(_abriendo ? 'Abriendo cámara...' : 'Subiendo foto...', style: FincasText.bodySecondary.copyWith(color: FincasColors.textPrimary)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: FincasSpacing.s),
            child: Text(_error!, style: const TextStyle(color: FincasColors.error, fontSize: 14, height: 1.4)),
          ),
        const SizedBox(height: FincasSpacing.s),
        if (_llena)
          const Text('Llegaste al máximo de fotos. Quita una para agregar otra.', style: FincasText.caption)
        else
          FincasSecondaryButton(label: 'Agregar foto', onPressed: _ocupado ? null : _agregar, loading: _subiendo),
      ],
    );
  }
}
