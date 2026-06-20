#!/bin/bash

echo "🔍 Verificando configuración de Firebase iOS..."
echo ""

# Verificar GoogleService-Info.plist
if [ -f "ios/Runner/GoogleService-Info.plist" ]; then
    echo "✅ GoogleService-Info.plist existe en ios/Runner/"
    
    # Extraer PROJECT_ID
    PROJECT_ID=$(grep -A 1 "PROJECT_ID" ios/Runner/GoogleService-Info.plist | grep string | sed 's/.*<string>\(.*\)<\/string>/\1/')
    echo "   Project ID: $PROJECT_ID"
    
    # Extraer GOOGLE_APP_ID
    GOOGLE_APP_ID=$(grep -A 1 "GOOGLE_APP_ID" ios/Runner/GoogleService-Info.plist | grep string | sed 's/.*<string>\(.*\)<\/string>/\1/')
    echo "   Google App ID: $GOOGLE_APP_ID"
else
    echo "❌ GoogleService-Info.plist NO existe en ios/Runner/"
    echo "   Descárgalo de Firebase Console y cópialo a ios/Runner/"
    exit 1
fi

echo ""
echo "🔍 Verificando Info.plist..."

# Verificar UIBackgroundModes
if grep -q "remote-notification" ios/Runner/Info.plist; then
    echo "✅ remote-notification configurado en Info.plist"
else
    echo "❌ remote-notification NO está en Info.plist"
    echo "   Agrega UIBackgroundModes con remote-notification"
fi

echo ""
echo "🔍 Verificando firebase_options.dart..."

# Verificar firebase_options.dart
if grep -q "apartalo-10146" lib/firebase_options.dart; then
    echo "✅ firebase_options.dart tiene el projectId correcto"
else
    echo "⚠️  firebase_options.dart puede tener configuración incorrecta"
fi

echo ""
echo "📋 Siguiente paso:"
echo "   1. Si todo está ✅, haz: flutter run"
echo "   2. Si hay ❌, corrige los archivos indicados"
echo ""
