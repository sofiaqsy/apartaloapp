import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:apartalo_app/screens/businesses_screen.dart';
import 'package:apartalo_app/services/auth_service.dart';
import 'package:apartalo_app/theme/fincas_theme.dart';
import 'package:apartalo_app/widgets/fincas_widgets.dart';

Widget _app(Widget child, {double scale = 1.0}) => MaterialApp(
      theme: FincasTheme.light(),
      builder: (context, c) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)), child: c!),
      home: child,
    );

Future<void> _small(WidgetTester t) async {
  t.view.physicalSize = const Size(320 * 3, 640 * 3);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
}

void main() {
  const longName = 'Cooperativa Agraria Cafetalera de Productores Orgánicos del Valle del Alto Urubamba y Anexos';

  testWidgets('business card: long name, city and role stay inside a 320pt screen at 2x text', (t) async {
    await _small(t);
    await t.pumpWidget(_app(
      Scaffold(body: Padding(padding: const EdgeInsets.all(24), child: FincasBusinessCard(name: longName, city: 'San Pedro de Cachora, Apurímac', roleLabel: 'Dueño', isCurrent: true, onTap: () {}))),
      scale: 2.0,
    ));
    expect(t.takeException(), isNull);
    expect(find.text('Entrar'), findsOneWidget);
  });

  testWidgets('business card tap keeps working and exposes one accessibility label', (t) async {
    var taps = 0;
    await t.pumpWidget(_app(Scaffold(body: FincasBusinessCard(name: 'Finca Rosal', city: 'Villa Rica', roleLabel: 'Dueño', onTap: () => taps++))));
    await t.tap(find.byType(FincasBusinessCard));
    expect(taps, 1);
    expect(find.bySemanticsLabel('Entrar a Finca Rosal, Villa Rica, Dueño'), findsOneWidget);
  });

  testWidgets('buttons are at least 48pt tall and show a spinner only while loading', (t) async {
    await t.pumpWidget(_app(Scaffold(body: Column(children: [
      FincasPrimaryButton(label: 'Entrar', onPressed: () {}),
      FincasSecondaryButton(label: 'Unirme', onPressed: () {}, loading: true),
    ]))));
    expect(t.getSize(find.byType(ElevatedButton)).height, greaterThanOrEqualTo(48));
    expect(t.getSize(find.byType(OutlinedButton)).height, greaterThanOrEqualTo(48));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Unirme'), findsNothing);
  });

  testWidgets('"Tus negocios": long names, pending requests and actions fit at 320pt, 2x text', (t) async {
    await _small(t);
    final session = AuthSession(
      status: 'active',
      fullName: 'María del Carmen Fernández de la Torre y Quispe',
      businesses: [
        {'businessId': 'BIZ-1', 'name': longName, 'city': 'San Pedro de Cachora, Apurímac', 'role': 'owner'},
        {'businessId': 'BIZ-2', 'name': 'Café Luis', 'city': 'Lima', 'role': 'staff'},
      ],
      pending: [
        {'kind': 'business', 'businessName': longName},
        {'kind': 'join', 'businessName': ''},
      ],
    );
    await t.pumpWidget(_app(BusinessesScreen(session: session, onSelect: (c, b, s) async {}), scale: 2.0));
    expect(t.takeException(), isNull);
    expect(find.text('Tus negocios'), findsOneWidget);
    // The actions are pinned below the list, so they are visible without scrolling.
    expect(find.text('Unirme a otro negocio'), findsOneWidget);
    expect(find.text('Registrar un negocio nuevo'), findsOneWidget);
  });

  testWidgets('"Tus negocios": entering a business calls onSelect with that business', (t) async {
    Map<String, dynamic>? picked;
    final session = AuthSession(status: 'active', fullName: 'Keyla', businesses: [
      {'businessId': 'BIZ-1', 'name': 'keyla', 'city': 'lima', 'role': 'owner'},
    ]);
    await t.pumpWidget(_app(BusinessesScreen(session: session, onSelect: (c, b, s) async => picked = b)));
    await t.tap(find.byType(FincasBusinessCard));
    expect(picked?['businessId'], 'BIZ-1');
  });

  testWidgets('"Tus negocios": empty account shows the empty state, not a blank screen', (t) async {
    await t.pumpWidget(_app(BusinessesScreen(session: AuthSession(status: 'active'), onSelect: (c, b, s) async {})));
    expect(find.text('Aún no tienes negocios'), findsOneWidget);
    // With nothing to enter yet, joining is the main action.
    expect(find.widgetWithText(ElevatedButton, 'Unirme a un negocio'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Registrar un negocio nuevo'), findsOneWidget);
  });

  testWidgets('"Tus negocios": many businesses scroll while the actions stay on screen', (t) async {
    await _small(t);
    final many = AuthSession(status: 'active', fullName: 'Keyla', businesses: [
      for (var i = 0; i < 12; i++) {'businessId': 'BIZ-$i', 'name': 'Negocio número $i', 'city': 'Lima', 'role': 'staff'},
    ]);
    await t.pumpWidget(_app(BusinessesScreen(session: many, onSelect: (c, b, s) async {})));
    expect(t.takeException(), isNull);
    expect(find.text('Negocio número 11'), findsNothing); // below the fold, reachable by scrolling
    expect(find.text('Unirme a otro negocio'), findsOneWidget);
    await t.scrollUntilVisible(find.text('Negocio número 11'), 300, scrollable: find.byType(Scrollable).first);
    expect(find.text('Negocio número 11'), findsOneWidget);
    expect(find.text('Unirme a otro negocio'), findsOneWidget);
  });

  testWidgets('"Tus negocios": the first business is visible with room to spare on a small phone', (t) async {
    await _small(t);
    final s = AuthSession(status: 'active', fullName: 'Keyla', businesses: [
      {'businessId': 'BIZ-1', 'name': 'keyla', 'city': 'lima', 'role': 'owner'},
    ]);
    await t.pumpWidget(_app(BusinessesScreen(session: s, onSelect: (c, b, s) async {})));
    final card = t.getRect(find.byType(FincasBusinessCard));
    final actions = t.getRect(find.text('Unirme a otro negocio'));
    expect(card.height, lessThan(130)); // compact: name, then location and role on one row
    expect(actions.bottom, greaterThan(500)); // actions sit low on a 640pt screen, near the thumb
  });
}
