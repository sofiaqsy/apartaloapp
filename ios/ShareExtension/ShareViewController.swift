import UIKit
import UniformTypeIdentifiers

/// Compartir → Finca Rosal (WhatsApp, Fotos, Archivos): la imagen del comprobante se guarda en el grupo de la app
/// (nunca en la galería) y se abre Finca Rosal en "Registrar pago con comprobante". Sin pantallas propias.
class ShareViewController: UIViewController {
  private let grupo = "group.com.rosal.apartaloApp"

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    guard let item = (extensionContext?.inputItems as? [NSExtensionItem])?.first,
          let proveedor = item.attachments?.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.image.identifier) }) else {
      return terminar()
    }
    proveedor.loadItem(forTypeIdentifier: UTType.image.identifier, options: nil) { [weak self] dato, _ in
      guard let self = self else { return }
      var datos: Data?
      if let url = dato as? URL { datos = try? Data(contentsOf: url) }
      else if let imagen = dato as? UIImage { datos = imagen.jpegData(compressionQuality: 0.9) }
      else if let d = dato as? Data { datos = d }
      guard let datos = datos, self.guardar(datos) else { return DispatchQueue.main.async { self.terminar() } }
      DispatchQueue.main.async {
        self.abrirApp(URL(string: "fincas://comprobante")!)
        self.terminar()
      }
    }
  }

  private func guardar(_ datos: Data) -> Bool {
    let fm = FileManager.default
    guard let base = fm.containerURL(forSecurityApplicationGroupIdentifier: grupo)?.appendingPathComponent("Comprobantes") else { return false }
    do {
      try fm.createDirectory(at: base, withIntermediateDirectories: true)
      try datos.write(to: base.appendingPathComponent("compartido_\(Int(Date().timeIntervalSince1970 * 1000)).jpg"), options: .completeFileProtection)
      return true
    } catch {
      return false
    }
  }

  /// Una extensión no puede abrir su app directamente: se pide a la aplicación por la cadena de respuesta, con
  /// openURL:options:completionHandler: llamado en tiempo de ejecución (el código de la extensión sigue siendo apto).
  private func abrirApp(_ url: URL) {
    let selector = NSSelectorFromString("openURL:options:completionHandler:")
    var r: UIResponder? = self
    while let actual = r {
      if actual.isKind(of: NSClassFromString("UIApplication") ?? NSNull.self), actual.responds(to: selector) {
        typealias Abrir = @convention(c) (NSObject, Selector, NSURL, NSDictionary, AnyObject?) -> Void
        let abrir = unsafeBitCast(actual.method(for: selector), to: Abrir.self)
        abrir(actual, selector, url as NSURL, NSDictionary(), nil)
        return
      }
      r = actual.next
    }
  }

  private func terminar() {
    extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
  }
}
