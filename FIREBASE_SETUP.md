# 🔥 Configuración Firebase para ApartaLo

## ✅ Archivos ya modificados:
- `pubspec.yaml` - Agregadas dependencias Firebase
- `ios/Runner/Info.plist` - Agregados permisos de notificaciones
- `ios/Runner/AppDelegate.swift` - Configurado Firebase y FCM
- `lib/main.dart` - Inicialización de Firebase
- `lib/firebase_options.dart` - Opciones de Firebase (necesita actualizar)
- `lib/services/notification_service.dart` - Servicio de notificaciones
- `lib/services/api_service.dart` - Métodos para registrar token

## 📋 Pasos que DEBES hacer manualmente:

### 1. Copia el archivo GoogleService-Info.plist
```bash
cp ~/Downloads/GoogleService-Info.plist ~/Desktop/OPEN\ IA/apartalo-app/ios/Runner/
```

### 2. Actualiza firebase_options.dart
Abre `GoogleService-Info.plist` y copia estos valores a `lib/firebase_options.dart`:

```
API_KEY → apiKey
GOOGLE_APP_ID → appId  
GCM_SENDER_ID → messagingSenderId
PROJECT_ID → projectId
STORAGE_BUCKET → storageBucket
```

### 3. Instala dependencias
```bash
cd ~/Desktop/OPEN\ IA/apartalo-app
flutter pub get
```

### 4. Actualiza pods de iOS
```bash
cd ios
pod install --repo-update
cd ..
```

### 5. Compila y prueba
```bash
flutter run
```

## 🔔 Para probar notificaciones:

### Desde Firebase Console:
1. Ve a Firebase Console → Cloud Messaging
2. Click "Send your first message"
3. Agrega título y texto
4. Selecciona tu app iOS
5. Enviar

### Desde tu backend (apartalo-core):
El endpoint esperado sería:
```javascript
POST /api/push-token/{businessId}
Body: { token, platform, appVersion }

// Para enviar notificación
POST /api/notify/{businessId}
Body: { 
  title: "Nuevo pedido",
  body: "Juan García - S/ 150.00",
  data: { type: "nuevo_pedido", pedidoId: "123" }
}
```

## 📱 Tipos de notificación soportados:
- `nuevo_pedido` - Cuando llega un nuevo pedido
- `stock_bajo` - Cuando un producto tiene stock bajo
- `pago_recibido` - Cuando se confirma un pago

## ⚠️ Notas importantes:
- Las notificaciones NO funcionan en simulador iOS (solo en dispositivo real)
- Necesitas un Apple Developer Account para habilitar Push Notifications
- En Firebase Console, sube tu APNs key (.p8) en Project Settings → Cloud Messaging
