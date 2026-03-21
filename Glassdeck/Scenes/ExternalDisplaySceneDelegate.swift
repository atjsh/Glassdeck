#if canImport(UIKit)
import UIKit
import SwiftUI

class ExternalDisplaySceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }

        let window = UIWindow(windowScene: windowScene)
        let externalView = ExternalTerminalView()
            .environment(GlassdeckEnvironment.sessionManager)
            .environment(GlassdeckEnvironment.connectionStore)
            .environment(GlassdeckEnvironment.appSettings)
        window.rootViewController = UIHostingController(rootView: externalView)
        self.window = window
        window.makeKeyAndVisible()
        GlassdeckEnvironment.sessionManager.setExternalDisplayConnected(true)
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        GlassdeckEnvironment.sessionManager.setExternalDisplayConnected(false)
        window = nil
    }
}
#endif
