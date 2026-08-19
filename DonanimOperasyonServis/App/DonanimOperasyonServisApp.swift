import SwiftUI

@main
struct DonanimOperasyonServisApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.diContainer, appDelegate.container)
                .task {
                    let coordinator = appDelegate.container.syncCoordinator
                    await coordinator.startObservingReachability()
                    await coordinator.handleLaunch()
                }
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active else { return }
                    Task {
                        await appDelegate.container.syncCoordinator.handleBecomeActive()
                    }
                }
        }
    }
}
