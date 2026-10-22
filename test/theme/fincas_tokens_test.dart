import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:apartalo_app/theme/fincas_tokens.dart';
import 'package:apartalo_app/theme/fincas_theme.dart';

double _lum(Color c) {
  double f(double v) => v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * f(c.r) + 0.7152 * f(c.g) + 0.0722 * f(c.b);
}

double contrast(Color a, Color b) {
  final la = _lum(a), lb = _lum(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

void main() {
  group('text contrast (WCAG AA, 4.5:1)', () {
    final backgrounds = {'background': FincasColors.background, 'surface': FincasColors.surface};
    final texts = {
      'textPrimary': FincasColors.textPrimary,
      'textSecondary': FincasColors.textSecondary,
      'textMuted': FincasColors.textMuted,
      'espresso': FincasColors.espresso,
      'error': FincasColors.error,
      'success': FincasColors.success,
    };
    for (final b in backgrounds.entries) {
      for (final t in texts.entries) {
        test('${t.key} on ${b.key}', () => expect(contrast(t.value, b.value), greaterThanOrEqualTo(4.5)));
      }
    }
    test('white on primary action', () => expect(contrast(FincasColors.actionPrimaryText, FincasColors.actionPrimary), greaterThanOrEqualTo(4.5)));
    test('status colors on their tonal backgrounds', () {
      expect(contrast(FincasColors.success, FincasColors.successBg), greaterThanOrEqualTo(4.5));
      expect(contrast(FincasColors.warning, FincasColors.warningBg), greaterThanOrEqualTo(4.5));
      expect(contrast(FincasColors.error, FincasColors.errorBg), greaterThanOrEqualTo(4.5));
    });
    test('accents: white on caramel and sage fills, accent text on its tint', () {
      expect(contrast(FincasColors.textOnInk, FincasColors.caramel), greaterThanOrEqualTo(4.5));
      expect(contrast(FincasColors.textOnInk, FincasColors.sage), greaterThanOrEqualTo(4.5));
      expect(contrast(FincasColors.caramel, FincasColors.caramelBg), greaterThanOrEqualTo(4.5));
      expect(contrast(FincasColors.sage, FincasColors.sageBg), greaterThanOrEqualTo(4.5));
      expect(contrast(FincasColors.textPrimary, FincasColors.caramelBg), greaterThanOrEqualTo(4.5));
    });
    test('the accent (espresso) reads on its soft tint and with white text', () {
      expect(contrast(FincasColors.accent, FincasColors.accentBg), greaterThanOrEqualTo(4.5));
      expect(contrast(FincasColors.textOnInk, FincasColors.accent), greaterThanOrEqualTo(4.5));
    });
    test('muted accent: white text on it and its text on the soft tint', () {
      expect(contrast(FincasColors.textOnInk, FincasColors.accentMuted), greaterThanOrEqualTo(4.5));
      expect(contrast(FincasColors.accentMuted, FincasColors.accentBg), greaterThanOrEqualTo(4.5));
    });
    test('espresso on sand (badges, links on tonal fills)', () => expect(contrast(FincasColors.espresso, FincasColors.sand), greaterThanOrEqualTo(4.5)));
  });

  group('non-text contrast (3:1)', () {
    test('input outline against the surface', () => expect(contrast(FincasColors.borderStrong, FincasColors.surface), greaterThanOrEqualTo(3)));
    test('focus ring against the background', () => expect(contrast(FincasColors.focus, FincasColors.background), greaterThanOrEqualTo(3)));
  });

  test('the primary color is the logo background', () => expect(FincasColors.ink, const Color(0xFF252117)));

  test('the theme has no blue seed: primary is ink and the page is ivory', () {
    final t = FincasTheme.light();
    expect(t.colorScheme.primary, FincasColors.ink);
    expect(t.scaffoldBackgroundColor, FincasColors.background);
    expect(t.colorScheme.surfaceTint, Colors.transparent);
  });
}
