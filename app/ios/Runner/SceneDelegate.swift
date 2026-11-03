import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
    /// The channel goes with the view controller: the window is there only
    /// after the scene has connected.
    override func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        super.scene(scene, willConnectTo: session, options: connectionOptions)
        if let controller = window?.rootViewController as? FlutterViewController {
            IosChannel.attach(controller.binaryMessenger)
        }
    }
}
