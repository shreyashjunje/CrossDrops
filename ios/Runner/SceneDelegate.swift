import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  /// `crossdrop://share?id=…` from the Share Extension (D-045). Other
  /// `crossdrop://` links (a QR code opened by the Camera app) only bring
  /// the app forward.
  override func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
    super.scene(scene, openURLContexts: URLContexts)
    if URLContexts.contains(where: { $0.url.scheme == "crossdrop" && $0.url.host == "share" }) {
      NotificationCenter.default.post(name: .crossDropShareArrived, object: nil)
    }
  }
}
