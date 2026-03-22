#if canImport(UIKit)
import UIKit
import SwiftUI

class MainSceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: windowScene)
        let rootView = ContentView()
            .environment(GlassdeckEnvironment.sessionManager)
            .environment(GlassdeckEnvironment.connectionStore)
            .environment(GlassdeckEnvironment.appSettings)
            .environment(GlassdeckEnvironment.lifecycleCoordinator)
        window.rootViewController = UIHostingController(rootView: rootView)
        self.window = window
        window.makeKeyAndVisible()
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        GlassdeckEnvironment.lifecycleCoordinator.handleAppDidBecomeActive()
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        GlassdeckEnvironment.lifecycleCoordinator.handleAppDidEnterBackground()
    }
}
#endif
