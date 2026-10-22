import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:apartalo_app/services/api_service.dart';
import 'package:apartalo_app/theme/fincas_theme.dart';
import 'package:apartalo_app/widgets/presentacion_fotos.dart';

const _f1 = FotoPresentacion(id: 'f1', url: 'https://example.com/1.jpg');
const _f2 = FotoPresentacion(id: 'f2', url: 'https://example.com/2.jpg');
const _f3 = FotoPresentacion(id: 'f3', url: 'https://example.com/3.jpg');

class _H {
  final subidos = <File>[];
  final quitados = <String>[];
  final origenes = <ImageSource>[];
  Future<String?> Function(File)? subir;
  Future<String?> Function(FotoPresentacion)? quitar;
  Future<File?> Function(ImageSource)? elegir;
}

Future<_H> _pump(WidgetTester t, {List<FotoPresentacion> fotos = const [], double scale = 1.0, Size? size}) async {
  final h = _H();
  if (size != null) {
    t.view.physicalSize = Size(size.width * 3, size.height * 3);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
  }
  await t.pumpWidget(MaterialApp(
    theme: FincasTheme.light(),
    builder: (context, c) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)), child: c!),
    home: Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: PresentacionFotos(
          fotos: fotos,
          elegir: (o) async {
            h.origenes.add(o);
            if (h.elegir != null) return await h.elegir!(o);
            return File('/tmp/foto.jpg');
          },
          onSubir: (f) async {
            h.subidos.add(f);
            return h.subir == null ? null : h.subir!(f);
          },
          onQuitar: (f) async {
            h.quitados.add(f.id);
            return h.quitar == null ? null : h.quitar!(f);
          },
        ),
      ),
    ),
  ));
  await t.pumpAndSettle();
  return h;
}

void main() {
  testWidgets('without photos: title, limit hint and the add button, no thumbnails', (t) async {
    await _pump(t);
    expect(find.text('Fotos'), findsOneWidget);
    expect(find.text('Hasta 3 fotos de esta presentación'), findsOneWidget);
    expect(find.text('Agregar foto'), findsOneWidget);
    expect(find.text('Quitar'), findsNothing);
  });

  testWidgets('with photos: one thumbnail and one Quitar button each', (t) async {
    await _pump(t, fotos: [_f1, _f2]);
    expect(find.text('Quitar'), findsNWidgets(2));
    expect(find.text('Agregar foto'), findsOneWidget);
  });

  testWidgets('at the maximum the add button is replaced by a message', (t) async {
    await _pump(t, fotos: [_f1, _f2, _f3]);
    expect(find.text('Agregar foto'), findsNothing);
    expect(find.textContaining('máximo de fotos'), findsOneWidget);
    expect(find.text('Quitar'), findsNWidgets(3));
  });

  group('adding', () {
    Future<void> abrirYElegir(WidgetTester t, String opcion) async {
      await t.ensureVisible(find.text('Agregar foto'));
      await t.tap(find.text('Agregar foto'));
      await t.pumpAndSettle();
      await t.tap(find.text(opcion));
      await t.pump();
    }

    testWidgets('the source sheet offers camera, gallery and cancel', (t) async {
      await _pump(t);
      await t.tap(find.text('Agregar foto'));
      await t.pumpAndSettle();
      expect(find.text('Tomar foto'), findsOneWidget);
      expect(find.text('Elegir de la galería'), findsOneWidget);
      expect(find.text('Cancelar'), findsOneWidget);
    });

    testWidgets('camera: picks, uploads the file once and shows no error', (t) async {
      final h = await _pump(t);
      await abrirYElegir(t, 'Tomar foto');
      await t.pumpAndSettle();
      expect(h.origenes, [ImageSource.camera]);
      expect(h.subidos.map((f) => f.path), ['/tmp/foto.jpg']);
      expect(find.byType(Text).evaluate().where((e) => (e.widget as Text).style?.color != null && (e.widget as Text).data!.contains('Error')), isEmpty);
    });

    testWidgets('gallery uses the gallery source', (t) async {
      final h = await _pump(t);
      await abrirYElegir(t, 'Elegir de la galería');
      await t.pumpAndSettle();
      expect(h.origenes, [ImageSource.gallery]);
    });

    testWidgets('while uploading there is a loader and the button cannot be used again', (t) async {
      final done = Completer<String?>();
      final h = await _pump(t);
      h.subir = (_) => done.future;
      await abrirYElegir(t, 'Tomar foto');
      await t.pump();
      expect(find.text('Subiendo...'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsWidgets);
      await t.tap(find.descendant(of: find.byType(PresentacionFotos), matching: find.byType(OutlinedButton)), warnIfMissed: false);
      await t.pump();
      expect(h.subidos, hasLength(1));
      done.complete(null);
      await t.pumpAndSettle();
      expect(find.text('Subiendo...'), findsNothing);
    });

    testWidgets('an upload error is shown to the person', (t) async {
      final h = await _pump(t);
      h.subir = (_) async => 'Máximo 3 fotos por presentación';
      await abrirYElegir(t, 'Tomar foto');
      await t.pumpAndSettle();
      expect(find.text('Máximo 3 fotos por presentación'), findsOneWidget);
    });

    testWidgets('cancelling the camera uploads nothing and shows no error', (t) async {
      final h = await _pump(t);
      h.elegir = (_) async => null;
      await abrirYElegir(t, 'Tomar foto');
      await t.pumpAndSettle();
      expect(h.subidos, isEmpty);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('if the camera cannot open, a message explains it', (t) async {
      final h = await _pump(t);
      h.elegir = (_) async => throw Exception('permiso denegado');
      await abrirYElegir(t, 'Tomar foto');
      await t.pumpAndSettle();
      expect(find.text('No se pudo abrir la cámara o la galería.'), findsOneWidget);
      expect(h.subidos, isEmpty);
    });

    testWidgets('Cancelar in the source sheet does nothing', (t) async {
      final h = await _pump(t);
      await t.tap(find.text('Agregar foto'));
      await t.pumpAndSettle();
      await t.tap(find.text('Cancelar'));
      await t.pumpAndSettle();
      expect(h.origenes, isEmpty);
    });
  });

  group('removing', () {
    testWidgets('asks for confirmation and then removes that photo', (t) async {
      final h = await _pump(t, fotos: [_f1, _f2]);
      await t.tap(find.text('Quitar').last);
      await t.pumpAndSettle();
      expect(find.text('Quitar foto'), findsOneWidget);
      expect(h.quitados, isEmpty);
      await t.tap(find.widgetWithText(TextButton, 'Quitar').last);
      await t.pumpAndSettle();
      expect(h.quitados, ['f2']);
    });

    testWidgets('Cancelar in the confirmation removes nothing', (t) async {
      final h = await _pump(t, fotos: [_f1]);
      await t.tap(find.text('Quitar'));
      await t.pumpAndSettle();
      await t.tap(find.text('Cancelar'));
      await t.pumpAndSettle();
      expect(h.quitados, isEmpty);
    });

    testWidgets('a removal error is shown', (t) async {
      final h = await _pump(t, fotos: [_f1]);
      h.quitar = (_) async => 'No se pudo quitar la foto';
      await t.tap(find.text('Quitar'));
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(TextButton, 'Quitar').last);
      await t.pumpAndSettle();
      expect(find.text('No se pudo quitar la foto'), findsOneWidget);
    });
  });

  testWidgets('fits a 320x568 phone at 2x text with three photos', (t) async {
    await _pump(t, fotos: [_f1, _f2, _f3], scale: 2.0, size: const Size(320, 568));
    expect(t.takeException(), isNull);
  });
}
