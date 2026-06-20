# ApartaLo App

Aplicación móvil con asistente de voz para gestión de inventario y clientes.

## 🎯 Características

- 🎤 **Asistente de voz**: Registra productos y clientes hablando
- 🤖 **IA híbrida**: Regex local + Google Gemini para entender comandos
- 📦 **Gestión de inventario**: CRUD de productos por voz
- 👥 **Gestión de clientes**: Registro y consulta por voz
- 📸 **Cámara integrada**: Toma fotos de productos (próximamente)

## 🗣️ Comandos de Voz Soportados

### Productos
```
"Registrar producto café premium a 85 soles"
"Registrar café a 50 soles, tengo 100 unidades"
"Agregar 20 de café orgánico"
"Quitar 5 de café premium"
"¿Cuánto stock tengo de café?"
"¿Cuánto cuesta el café?"
"Mostrar productos"
```

### Clientes
```
"Registrar cliente Juan Pérez número 999888777"
"Registrar cliente Cafetería Don José, número 987654321"
"Mostrar clientes"
```

### General
```
"Ayuda"
"¿Qué puedes hacer?"
```

## 🛠️ Instalación

### Prerrequisitos
- Flutter 3.0 o superior
- Cuenta de Google Cloud (para Gemini API)
- Backend ApartaLo Core corriendo

### Pasos

1. **Clonar y entrar al proyecto**
```bash
cd apartalo-app
```

2. **Configurar variables de entorno**
```bash
cp .env.example .env
```

Editar `.env`:
```env
GEMINI_API_KEY=tu_api_key_de_gemini
API_BASE_URL=https://tu-apartalo-core.herokuapp.com
BUSINESS_ID=tu-negocio-id
```

3. **Obtener API Key de Gemini (GRATIS)**
- Ir a https://makersuite.google.com/app/apikey
- Crear nueva API key
- Copiar y pegar en `.env`

4. **Instalar dependencias**
```bash
flutter pub get
```

5. **Ejecutar la app**
```bash
flutter run
```

## 📁 Estructura del Proyecto

```
lib/
├── main.dart                    # Entry point
├── config/
│   └── app_config.dart          # Configuración
├── models/
│   └── models.dart              # Producto, Cliente, Pedido
├── services/
│   ├── ai_assistant_service.dart  # IA (Regex + Gemini)
│   ├── speech_service.dart        # Reconocimiento de voz
│   ├── tts_service.dart           # Text-to-Speech
│   └── api_service.dart           # Comunicación con backend
├── screens/
│   └── home_screen.dart         # Pantalla principal
└── widgets/
    └── voice_widgets.dart       # Botón de voz, indicadores
```

## 🔧 Arquitectura de IA

```
┌─────────────────────────────────────────┐
│         Comando de Voz                  │
│    "registrar café a 85 soles"          │
└─────────────────┬───────────────────────┘
                  │
                  ▼
┌─────────────────────────────────────────┐
│     PASO 1: Procesamiento Local         │
│         (Regex - Instantáneo)           │
│                                         │
│  ✓ Patrones conocidos → Ejecutar        │
│  ✗ No reconocido → Paso 2               │
└─────────────────┬───────────────────────┘
                  │
                  ▼
┌─────────────────────────────────────────┐
│     PASO 2: Google Gemini               │
│       (IA - 1-2 segundos)               │
│                                         │
│  Entiende comandos complejos y          │
│  variaciones del lenguaje natural       │
└─────────────────────────────────────────┘
```

### ¿Por qué híbrido?

| Enfoque | Velocidad | Costo | Cobertura |
|---------|-----------|-------|-----------|
| Solo Regex | ⚡ Instantáneo | 🆓 Gratis | 😐 Limitado |
| Solo IA | 🐢 1-2 seg | 💰 API calls | 😀 Amplio |
| **Híbrido** | ⚡ Mayormente instantáneo | 🆓 ~80% gratis | 😀 Amplio |

## 📱 Plataformas

- ✅ Android
- ✅ iOS
- ⬜ Web (parcial - sin micrófono)

## 🔐 Permisos Requeridos

### Android (`android/app/src/main/AndroidManifest.xml`)
```xml
<uses-permission android:name="android.permission.RECORD_AUDIO"/>
<uses-permission android:name="android.permission.INTERNET"/>
<uses-permission android:name="android.permission.CAMERA"/>
```

### iOS (`ios/Runner/Info.plist`)
```xml
<key>NSMicrophoneUsageDescription</key>
<string>Necesitamos acceso al micrófono para comandos de voz</string>
<key>NSSpeechRecognitionUsageDescription</key>
<string>Necesitamos reconocimiento de voz para el asistente</string>
<key>NSCameraUsageDescription</key>
<string>Necesitamos la cámara para fotos de productos</string>
```

## 🚀 Próximas Funcionalidades

- [ ] Pantalla de productos con lista
- [ ] Pantalla de clientes
- [ ] Tomar foto al registrar producto
- [ ] Escaneo de código de barras
- [ ] Modo offline con sincronización
- [ ] Widget flotante siempre disponible
- [ ] Notificaciones push

## 📄 Licencia

MIT - Keyla Cusi / RosalCafe
