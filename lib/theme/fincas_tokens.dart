import 'package:flutter/material.dart';

/// Fincas design tokens. The single source of truth for colors, type, spacing and radii.
/// Values come from the FI logo (assets/splash/splash.png: ink #252117 on white) and were
/// checked for contrast; see docs/DESIGN_SYSTEM.md. Never use raw hex values in screens.
class FincasColors {
  FincasColors._();

  // Brand
  static const ink = Color(0xFF252117); // the logo's real background
  static const inkPressed = Color(0xFF3A3528);
  static const espresso = Color(0xFF5A3A36); // warm accent: emphasis, links, selected
  static const sand = Color(0xFFE8E1D7); // secondary background, tonal fills
  static const sandStrong = Color(0xFFDDD5C8); // decorative borders and dividers

  // Backgrounds and surfaces
  static const background = Color(0xFFF8F6F1); // warm ivory page
  static const backgroundAlt = Color(0xFFF1EDE5); // secondary background
  static const surface = Color(0xFFFFFFFF); // cards, fields, sheets
  static const surfaceElevated = Color(0xFFFFFFFF); // dialogs: separated by border, not shadow

  // Text (all >= 4.5:1 on background and surface)
  static const textPrimary = ink;
  static const textSecondary = Color(0xFF5C574B);
  static const textMuted = Color(0xFF6F695C);
  static const textOnInk = Color(0xFFFFFFFF);

  // Actions and lines
  static const actionPrimary = ink;
  static const actionPrimaryText = textOnInk;
  static const actionSecondary = surface;
  static const border = sandStrong;
  static const borderStrong = Color(0xFF8F8878); // input outlines: 3:1 against surfaces
  static const divider = sand;
  static const focus = espresso;

  // Status (foreground / tonal background pairs, each >= 4.5:1)
  static const success = Color(0xFF2F6B3F);
  static const successBg = Color(0xFFE4EFE6);
  static const warning = Color(0xFF7A4F00);
  static const warningBg = Color(0xFFF6EAD0);
  static const error = Color(0xFFA63A2B);
  static const errorBg = Color(0xFFF6E1DD);

  // Disabled (exempt from contrast rules, but still legible)
  static const disabledBg = Color(0xFFECE8E0);
  static const disabledText = Color(0xFF9A9486);
}

/// 4-point spacing scale.
class FincasSpacing {
  FincasSpacing._();
  static const double xs = 4;
  static const double s = 8;
  static const double m = 12;
  static const double l = 16;
  static const double xl = 24;
  static const double xxl = 32;
  static const double xxxl = 48;

  static const double screenH = 24; // horizontal screen padding
  static const double section = 32; // between sections
  static const double cardPadding = 16;
  static const double field = 12; // between form fields
  static const double buttonHeight = 52;
  static const double minTouch = 48; // iOS asks for 44; we keep 48
}

class FincasRadii {
  FincasRadii._();
  static const double small = 8; // badges
  static const double medium = 12; // buttons, fields
  static const double large = 16; // cards, dialogs
  static const double logo = 24; // the FI app icon square
}

class FincasIcons {
  FincasIcons._();
  static const double small = 20;
  static const double regular = 24;
}

/// Type roles. Serif (Fraunces) is for brand moments only; everything operational is sans.
/// Sizes scale with the system text size (no fixed heights).
class FincasText {
  FincasText._();

  static const String serif = 'Fraunces';

  // Editorial / display (brand moments)
  static const displayLarge = TextStyle(
    fontFamily: serif, fontSize: 36, height: 1.15, fontWeight: FontWeight.w600, letterSpacing: -0.5, color: FincasColors.textPrimary,
    // Fraunces is a variable font: set its axes explicitly (weight, optical size) instead of relying on a weight mapping.
    fontVariations: [FontVariation('wght', 600), FontVariation('opsz', 36)]);
  static const screenTitle = TextStyle(
    fontFamily: serif, fontSize: 28, height: 1.2, fontWeight: FontWeight.w600, letterSpacing: -0.3, color: FincasColors.textPrimary,
    fontVariations: [FontVariation('wght', 600), FontVariation('opsz', 28)]);

  // Interface (Roboto)
  static const sectionTitle = TextStyle(
    fontSize: 18, height: 1.3, fontWeight: FontWeight.w600, color: FincasColors.textPrimary);
  static const body = TextStyle(
    fontSize: 16, height: 1.5, fontWeight: FontWeight.w400, color: FincasColors.textPrimary);
  static const bodySecondary = TextStyle(
    fontSize: 14, height: 1.45, fontWeight: FontWeight.w400, color: FincasColors.textSecondary);
  static const label = TextStyle(
    fontSize: 14, height: 1.3, fontWeight: FontWeight.w500, letterSpacing: 0.1, color: FincasColors.textPrimary);
  static const button = TextStyle(
    fontSize: 16, height: 1.25, fontWeight: FontWeight.w600, letterSpacing: 0.2);
  static const caption = TextStyle(
    fontSize: 12, height: 1.35, fontWeight: FontWeight.w400, color: FincasColors.textMuted);
  static const metadata = TextStyle(
    fontSize: 13, height: 1.35, fontWeight: FontWeight.w400, color: FincasColors.textSecondary);
}
