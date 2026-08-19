import SwiftUI

@main
struct DonanimOperasyonServisApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    private let container: DIContainer = .live()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.diContainer, container)
        }
    }
}
