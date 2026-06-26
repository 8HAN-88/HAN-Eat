import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    super.scene(scene, willConnectTo: session, options: connectionOptions)
    guard let windowScene = scene as? UIWindowScene else { return }
    let canvas = UIColor(red: 0.97, green: 0.97, blue: 0.98, alpha: 1)
    for window in windowScene.windows {
      window.backgroundColor = canvas
      window.rootViewController?.view.backgroundColor = canvas
    }
  }
}
