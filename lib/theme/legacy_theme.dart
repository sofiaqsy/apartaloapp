import 'package:flutter/material.dart';

/// Look anterior de las pestañas Pedidos y Productos (barra azul, fondo gris, botones de colores).
/// Solo envuelve la pantalla principal; login, Tus negocios y el detalle del producto siguen el tema Fincas.
ThemeData legacyTabsTheme() => ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2563EB), brightness: Brightness.light),
      useMaterial3: true,
      fontFamily: 'Roboto',
      appBarTheme: const AppBarTheme(centerTitle: true, elevation: 0),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      cardTheme: CardThemeData(elevation: 2, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
    );
