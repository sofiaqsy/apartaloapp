import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:apartalo_app/screens/login_screen.dart';
import 'package:apartalo_app/theme/fincas_theme.dart';

Widget _app({double scale = 1.0}) => MaterialApp(
      theme: FincasTheme.light(),
      builder: (context, c) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)), child: c!),
      home: const LoginScreen(),
    );

Future<void> _size(WidgetTester t, double w, double h) async {
  t.view.physicalSize = Size(w * 3, h * 3);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final size in [const Size(320, 568), const Size(390, 844), const Size(430, 932)]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('sign-in screen fits ${size.width.toInt()}x${size.height.toInt()} at ${scale}x text', (t) async {
        await _size(t, size.width, size.height);
        await t.pumpWidget(_app(scale: scale));
        await t.pumpAndSettle(const Duration(milliseconds: 200)); // the saved-session check ends (no Firebase in tests)
        expect(t.takeException(), isNull);
        expect(find.text('Continuar con Google'), findsOneWidget);
        expect(find.text('Continuar con Apple'), findsOneWidget);
        expect(find.text('Fincas'), findsOneWidget);
      });
    }
  }

  testWidgets('while checking the saved session the brand and a single loader are shown, no buttons', (t) async {
    await _size(t, 390, 844);
    await t.pumpWidget(_app()); // first frame only: the check has not finished yet
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Verificando tu sesión...'), findsOneWidget);
    expect(find.text('Continuar con Google'), findsNothing);
    await t.pumpAndSettle(const Duration(milliseconds: 200));
  });

  testWidgets('the sign-in screen asks for dark status bar icons (the page is ivory)', (t) async {
    await _size(t, 390, 844);
    await t.pumpWidget(_app());
    await t.pumpAndSettle(const Duration(milliseconds: 200));
    final region = t.widget<AnnotatedRegion<SystemUiOverlayStyle>>(find.byType(AnnotatedRegion<SystemUiOverlayStyle>).first);
    expect(region.value.statusBarIconBrightness, Brightness.dark);
  });
}
