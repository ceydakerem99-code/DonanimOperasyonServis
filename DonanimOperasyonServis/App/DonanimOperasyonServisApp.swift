import SwiftUI

@main
struct DonanimOperasyonServisApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    // `DIContainer.live()` throws when the disk-backed SwiftData
    // store cannot be opened. There is no meaningful recovery for a
    // broken local store at cold-start in v3, so we crash loudly.
    // A dedicated first-run error surface can replace this in a
    // later phase.
    private let container: DIContainer = {
        do {
            return try DIContainer.live()
        } catch {
            fatalError("Failed to construct DIContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.diContainer, container)
        }
    }
}
