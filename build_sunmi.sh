#!/bin/bash

# =====================================================
# Script para generar APK de ApartaLo para Sunmi
# =====================================================

echo "🚀 Generando APK de ApartaLo para tablets Sunmi..."
echo ""

# Ir al directorio del proyecto
cd "$(dirname "$0")"

# Limpiar builds anteriores
echo "🧹 Limpiando builds anteriores..."
flutter clean

# Obtener dependencias
echo "📦 Obteniendo dependencias..."
flutter pub get

# Generar APK release
echo "🔨 Compilando APK release..."
flutter build apk --release --target-platform android-arm,android-arm64

# Verificar si se generó
APK_PATH="build/app/outputs/flutter-apk/app-release.apk"

if [ -f "$APK_PATH" ]; then
    echo ""
    echo "✅ APK generado exitosamente!"
    echo ""
    echo "📍 Ubicación: $APK_PATH"
    echo "📊 Tamaño: $(du -h "$APK_PATH" | cut -f1)"
    echo ""
    
    # Copiar a una ubicación más accesible
    mkdir -p releases
    cp "$APK_PATH" "releases/apartalo-sunmi-$(date +%Y%m%d).apk"
    echo "📁 Copiado a: releases/apartalo-sunmi-$(date +%Y%m%d).apk"
    echo ""
    echo "📲 Para instalar en tu tablet Sunmi:"
    echo "   1. Copia el APK a la tablet via USB o descarga"
    echo "   2. Abre el archivo APK en la tablet"
    echo "   3. Permite la instalación de fuentes desconocidas"
    echo "   4. Instala y listo!"
else
    echo ""
    echo "❌ Error: No se pudo generar el APK"
    echo "   Revisa los errores arriba"
fi
