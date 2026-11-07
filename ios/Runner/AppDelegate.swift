import Flutter
import UIKit
import FirebaseCore
import FirebaseMessaging
import Vision

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Configurar Firebase
    FirebaseApp.configure()
    
    // Configurar notificaciones
    UNUserNotificationCenter.current().delegate = self
    
    let authOptions: UNAuthorizationOptions = [.alert, .badge, .sound]
    UNUserNotificationCenter.current().requestAuthorization(
      options: authOptions,
      completionHandler: { _, _ in }
    )
    
    application.registerForRemoteNotifications()
    
    // Configurar Firebase Messaging delegate
    Messaging.messaging().delegate = self
    
    GeneratedPluginRegistrant.register(with: self)
    if let registrar = self.registrar(forPlugin: "Comprobante") {
      Comprobante.registrar(registrar.messenger())
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
  
  // Manejar token de APNs
  override func application(_ application: UIApplication,
                            didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
    Messaging.messaging().apnsToken = deviceToken
    super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
  }
}

// MARK: - MessagingDelegate
extension AppDelegate: MessagingDelegate {
  func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
    print("🔔 FCM Token: \(fcmToken ?? "nil")")
    
    // Enviar token a Flutter si es necesario
    let dataDict: [String: String] = ["token": fcmToken ?? ""]
    NotificationCenter.default.post(
      name: Notification.Name("FCMToken"),
      object: nil,
      userInfo: dataDict
    )
  }
}

// MARK: - Comprobantes
/// Leer un comprobante en el teléfono (Vision, sin internet) y tomar la imagen que la extensión Compartir dejó en el
/// grupo de la app. La imagen pasa a la carpeta temporal de la app (nunca a la galería) y se borra del grupo.
enum Comprobante {
  static let grupo = "group.com.rosal.apartaloApp"

  static func registrar(_ messenger: FlutterBinaryMessenger) {
    let canal = FlutterMethodChannel(name: "com.apartalo/comprobante", binaryMessenger: messenger)
    canal.setMethodCallHandler { call, result in
      switch call.method {
      case "leerTexto":
        let ruta = (call.arguments as? [String: Any])?["ruta"] as? String ?? ""
        leerTexto(ruta) { texto in DispatchQueue.main.async { result(texto) } }
      case "pendiente":
        result(pendiente())
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  static func leerTexto(_ ruta: String, listo: @escaping (String) -> Void) {
    guard let imagen = UIImage(contentsOfFile: ruta)?.cgImage else { return listo("") }
    let pedido = VNRecognizeTextRequest { req, _ in
      let lineas = (req.results as? [VNRecognizedTextObservation] ?? []).compactMap { $0.topCandidates(1).first?.string }
      listo(lineas.joined(separator: "\n"))
    }
    pedido.recognitionLevel = .accurate
    pedido.recognitionLanguages = ["es-ES", "en-US"]
    pedido.usesLanguageCorrection = false
    DispatchQueue.global(qos: .userInitiated).async {
      do { try VNImageRequestHandler(cgImage: imagen, options: [:]).perform([pedido]) } catch { listo("") }
    }
  }

  /// La imagen compartida más nueva, movida a la carpeta temporal; nil si no hay.
  static func pendiente() -> String? {
    let fm = FileManager.default
    guard let base = fm.containerURL(forSecurityApplicationGroupIdentifier: grupo)?.appendingPathComponent("Comprobantes"),
          let archivos = try? fm.contentsOfDirectory(at: base, includingPropertiesForKeys: [.creationDateKey]),
          !archivos.isEmpty else { return nil }
    let ordenados = archivos.sorted {
      let a = (try? $0.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
      let b = (try? $1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
      return a > b
    }
    let destino = fm.temporaryDirectory.appendingPathComponent(ordenados[0].lastPathComponent)
    try? fm.removeItem(at: destino)
    defer { for f in archivos { try? fm.removeItem(at: f) } } // nada queda en el grupo
    do { try fm.copyItem(at: ordenados[0], to: destino) } catch { return nil }
    return destino.path
  }
}
