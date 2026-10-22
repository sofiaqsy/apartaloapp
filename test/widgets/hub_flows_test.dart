import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:apartalo_app/screens/businesses_screen.dart';
import 'package:apartalo_app/services/auth_service.dart';
import 'package:apartalo_app/theme/fincas_theme.dart';
import 'package:apartalo_app/widgets/fincas_widgets.dart';

AuthSession _session() => AuthSession(status: 'active', fullName: 'Keyla', businesses: [
      {'businessId': 'BIZ-1', 'name': 'keyla', 'city': 'lima', 'role': 'owner'},
    ]);

void main() {
  testWidgets('join dialog: open, type, cancel, no framework errors', (t) async {
    await t.pumpWidget(MaterialApp(theme: FincasTheme.light(), home: BusinessesScreen(session: _session(), onSelect: (c, b, s) async {})));
    await t.tap(find.text('Unirme a otro negocio'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), 'abcd');
    await t.tap(find.text('Cancelar'));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
  });

  testWidgets('register dialog: open, type, cancel, no framework errors', (t) async {
    await t.pumpWidget(MaterialApp(theme: FincasTheme.light(), home: BusinessesScreen(session: _session(), onSelect: (c, b, s) async {})));
    await t.tap(find.text('Registrar un negocio nuevo'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField).first, 'Mi negocio');
    await t.tap(find.text('Cancelar'));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
  });

  testWidgets('entering a business after sign-in navigates even though the login page was replaced', (t) async {
    // Mirrors the real flow: page A is replaced by the hub; choosing a business must open the next page.
    final navKey = GlobalKey<NavigatorState>();
    await t.pumpWidget(MaterialApp(
      navigatorKey: navKey,
      theme: FincasTheme.light(),
      home: const Scaffold(body: Text('login')),
    ));
    navKey.currentState!.pushReplacement(MaterialPageRoute(
      builder: (_) => BusinessesScreen(
        session: _session(),
        onSelect: (context, business, s) async {
          Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const Scaffold(body: Text('main'))));
        },
      ),
    ));
    await t.pumpAndSettle();
    await t.tap(find.text('Entrar'));
    await t.pumpAndSettle();
    expect(find.text('main'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('tapping Entrar shows a blocking loader until the business is ready', (t) async {
    final done = Completer<void>();
    await t.pumpWidget(MaterialApp(theme: FincasTheme.light(), home: BusinessesScreen(session: _session(), onSelect: (c, b, s) => done.future)));
    expect(find.text('Entrando a keyla...'), findsNothing);
    await t.tap(find.byType(FincasBusinessCard));
    await t.pump();
    expect(find.text('Entrando a keyla...'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    // a second tap while loading is ignored by the barrier
    await t.tap(find.byType(FincasBusinessCard), warnIfMissed: false);
    done.complete();
    await t.pumpAndSettle();
    expect(find.text('Entrando a keyla...'), findsNothing);
    expect(t.takeException(), isNull);
  });

  testWidgets('when entering fails the loader clears and a message explains it', (t) async {
    await t.pumpWidget(MaterialApp(theme: FincasTheme.light(), home: BusinessesScreen(session: _session(), onSelect: (c, b, s) async => throw Exception('x'))));
    await t.tap(find.byType(FincasBusinessCard));
    await t.pumpAndSettle();
    expect(find.text('Entrando a keyla...'), findsNothing);
    expect(find.text('No se pudo entrar al negocio. Revisa tu internet e intenta de nuevo.'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('status bar icons are dark on the ivory page (not white on white)', (t) async {
    await t.pumpWidget(MaterialApp(theme: FincasTheme.light(), home: BusinessesScreen(session: _session(), onSelect: (c, b, s) async {})));
    final bar = t.widget<AppBar>(find.byType(AppBar));
    expect(bar.systemOverlayStyle, FincasTheme.statusBarOnLight);
    expect(FincasTheme.statusBarOnLight.statusBarIconBrightness, Brightness.dark);
    expect(FincasTheme.statusBarOnLight.statusBarBrightness, Brightness.light);
  });

  testWidgets('runWithFincasLoader shows the loader during the task and closes it after', (t) async {
    final done = Completer<int>();
    int? result;
    await t.pumpWidget(MaterialApp(theme: FincasTheme.light(), home: Builder(builder: (context) => Scaffold(
          body: TextButton(onPressed: () async => result = await runWithFincasLoader(context, 'Cargando tus negocios...', () => done.future), child: const Text('go'))))));
    await t.tap(find.text('go'));
    await t.pump();
    expect(find.text('Cargando tus negocios...'), findsOneWidget);
    done.complete(7);
    await t.pumpAndSettle();
    expect(find.text('Cargando tus negocios...'), findsNothing);
    expect(result, 7);
  });
}
