import SwiftUI

@main
struct DonanimOperasyonServisApp: App {

    init() {
        if ProcessInfo.processInfo.arguments.contains("--legacy-dry-run") {
            Task {
                try? await Task.sleep(for: .milliseconds(1500))
                // DI container app delegate hazır olduğunda çalıştırılacak.
            }
        }
    }
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
                    switch phase {
                    case .active:
                        Task {
                            await appDelegate.container.syncCoordinator.handleBecomeActive()
                            appDelegate.container.realtimeCoordinator.handleForeground()
                        }
                    case .background, .inactive:
                        appDelegate.container.realtimeCoordinator.handleBackground()
                    @unknown default:
                        break
                    }
                }
        }
    }
}
