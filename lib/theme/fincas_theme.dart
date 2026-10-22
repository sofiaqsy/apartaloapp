import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'fincas_tokens.dart';

/// App-wide Material theme built only from [FincasColors], [FincasText], [FincasSpacing] and
/// [FincasRadii]. This replaces the former blue seed, which produced the lavender surfaces.
class FincasTheme {
  FincasTheme._();

  /// Status bar for light pages (ivory): dark time, signal and battery. On iOS the flag is
  /// `statusBarBrightness` (brightness of the page behind it); on Android it is the icon brightness.
  static const SystemUiOverlayStyle statusBarOnLight = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    statusBarBrightness: Brightness.light,
  );

  static ThemeData light() {
    const scheme = ColorScheme(
      brightness: Brightness.light,
      primary: FincasColors.ink,
      onPrimary: FincasColors.textOnInk,
      primaryContainer: FincasColors.sand,
      onPrimaryContainer: FincasColors.ink,
      secondary: FincasColors.espresso,
      onSecondary: FincasColors.textOnInk,
      secondaryContainer: FincasColors.sand,
      onSecondaryContainer: FincasColors.espresso,
      tertiary: FincasColors.espresso,
      onTertiary: FincasColors.textOnInk,
      error: FincasColors.error,
      onError: FincasColors.textOnInk,
      errorContainer: FincasColors.errorBg,
      onErrorContainer: FincasColors.error,
      surface: FincasColors.background,
      onSurface: FincasColors.textPrimary,
      onSurfaceVariant: FincasColors.textSecondary,
      surfaceTint: Colors.transparent,
      surfaceContainerLowest: FincasColors.surface,
      surfaceContainerLow: FincasColors.backgroundAlt,
      surfaceContainer: FincasColors.backgroundAlt,
      surfaceContainerHigh: FincasColors.sand,
      surfaceContainerHighest: FincasColors.sandStrong,
      outline: FincasColors.borderStrong,
      outlineVariant: FincasColors.border,
      shadow: Colors.black,
      scrim: Colors.black,
      inverseSurface: FincasColors.ink,
      onInverseSurface: FincasColors.textOnInk,
      inversePrimary: FincasColors.sand,
    );

    final buttonShape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(FincasRadii.medium));
    const minButton = Size(0, FincasSpacing.minTouch);

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: 'Roboto',
      scaffoldBackgroundColor: FincasColors.background,
      dividerColor: FincasColors.divider,
      dividerTheme: const DividerThemeData(color: FincasColors.divider, thickness: 1, space: 1),
      textTheme: const TextTheme(
        displayLarge: FincasText.displayLarge,
        headlineMedium: FincasText.screenTitle,
        titleMedium: FincasText.sectionTitle,
        bodyLarge: FincasText.body,
        bodyMedium: FincasText.bodySecondary,
        labelLarge: FincasText.button,
        labelMedium: FincasText.label,
        bodySmall: FincasText.caption,
      ),
      appBarTheme: const AppBarTheme(
        centerTitle: true, // unchanged for existing screens; redesigned screens override
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: FincasColors.background,
        foregroundColor: FincasColors.ink,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: FincasColors.ink),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: FincasColors.actionPrimary,
          foregroundColor: FincasColors.actionPrimaryText,
          disabledBackgroundColor: FincasColors.disabledBg,
          disabledForegroundColor: FincasColors.disabledText,
          elevation: 0,
          minimumSize: minButton,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: buttonShape,
          textStyle: FincasText.button,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: FincasColors.actionPrimary,
          foregroundColor: FincasColors.actionPrimaryText,
          disabledBackgroundColor: FincasColors.disabledBg,
          disabledForegroundColor: FincasColors.disabledText,
          minimumSize: minButton,
          shape: buttonShape,
          textStyle: FincasText.button,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: FincasColors.ink,
          backgroundColor: FincasColors.actionSecondary,
          disabledForegroundColor: FincasColors.disabledText,
          minimumSize: minButton,
          side: const BorderSide(color: FincasColors.borderStrong),
          shape: buttonShape,
          textStyle: FincasText.button,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: FincasColors.espresso,
          disabledForegroundColor: FincasColors.disabledText,
          minimumSize: minButton,
          shape: buttonShape,
          textStyle: FincasText.button,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: FincasColors.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        labelStyle: FincasText.bodySecondary,
        floatingLabelStyle: const TextStyle(color: FincasColors.espresso, fontWeight: FontWeight.w500),
        hintStyle: const TextStyle(color: FincasColors.textMuted),
        helperStyle: FincasText.caption,
        errorStyle: const TextStyle(color: FincasColors.error, fontSize: 13),
        border: _inputBorder(FincasColors.borderStrong),
        enabledBorder: _inputBorder(FincasColors.borderStrong),
        focusedBorder: _inputBorder(FincasColors.focus, width: 2),
        errorBorder: _inputBorder(FincasColors.error),
        focusedErrorBorder: _inputBorder(FincasColors.error, width: 2),
        disabledBorder: _inputBorder(FincasColors.border),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: FincasColors.surface,
        surfaceTintColor: Colors.transparent,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(FincasRadii.large),
          side: const BorderSide(color: FincasColors.border),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: FincasColors.surfaceElevated,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(FincasRadii.large),
          side: const BorderSide(color: FincasColors.border),
        ),
        titleTextStyle: FincasText.sectionTitle,
        contentTextStyle: FincasText.bodySecondary,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: FincasColors.ink,
        contentTextStyle: const TextStyle(color: FincasColors.textOnInk, fontSize: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(FincasRadii.medium)),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: FincasColors.ink,
        linearTrackColor: FincasColors.sand,
        circularTrackColor: Colors.transparent,
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: FincasColors.accent,
        foregroundColor: FincasColors.textOnInk,
        elevation: 2,
        extendedTextStyle: FincasText.button,
      ),
      listTileTheme: const ListTileThemeData(iconColor: FincasColors.textSecondary),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: FincasColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(FincasRadii.large))),
      ),
    );
  }

  static OutlineInputBorder _inputBorder(Color color, {double width = 1}) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(FincasRadii.medium),
        borderSide: BorderSide(color: color, width: width),
      );
}
