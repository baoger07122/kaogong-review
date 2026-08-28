import SwiftData
import SwiftUI
import UIKit

@MainActor
final class NativeWindowSceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    private var modelContainer: ModelContainer?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }

        do {
            let container = try ModelContainer(for: StoredRecord.self)
            let rootView = RootTabView()
                .environment(\.apiClient, .production)
                .modelContainer(container)
            let window = UIWindow(windowScene: windowScene)
            window.rootViewController = UIHostingController(rootView: rootView)
            window.makeKeyAndVisible()

            modelContainer = container
            self.window = window
        } catch {
            fatalError("无法初始化原生数据库：\(error.localizedDescription)")
        }
    }

    @available(iOS 26.0, *)
    func preferredWindowingControlStyle(
        for scene: UIWindowScene
    ) -> UIWindowScene.WindowingControlStyle {
        .unified
    }
}
