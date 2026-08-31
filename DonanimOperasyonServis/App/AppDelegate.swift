import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    private(set) var container = DIContainer.bootstrap()

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        AppLogger.app.info("Application did finish launching")
        #if DEBUG
        Task { await DemoDataSeeder.seedIfNeeded(container: container) }
        #endif
        let coordinator = container.syncCoordinator
        container.backgroundSyncScheduler.register { handle in
            await coordinator.handleBackgroundTask(handle)
        }
        container.backgroundSyncScheduler.scheduleNext()
        return true
    }
}
