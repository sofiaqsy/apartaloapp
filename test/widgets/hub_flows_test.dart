import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:apartalo_app/screens/businesses_screen.dart';
import 'package:apartalo_app/services/auth_service.dart';
import 'package:apartalo_app/theme/fincas_theme.dart';

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
}
