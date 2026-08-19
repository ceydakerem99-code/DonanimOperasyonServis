import SwiftUI

@main
struct DonanimOperasyonServisApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    private let container: DIContainer = Self.makeContainer()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.diContainer, container)
        }
    }

    /// Release/live: Firebase config is required; missing plist is a
    /// hard failure. DEBUG (previews already use `.mock()`; XCTest
    /// hosts this `@main` type): fall back to the in-memory container
    /// so the test host can launch without a real Firebase project.
    /// `DIContainer.live()` itself never wires Fake data sources.
    private static func makeContainer() -> DIContainer {
        do {
            return try DIContainer.live()
        } catch {
            #if DEBUG
            if error as? FirebaseError == .notConfigured {
                AppLogger.app.warning(
                    "Firebase not configured; DEBUG/test host using DIContainer.mock()."
                )
                return .mock()
            }
            #endif
            fatalError("Failed to construct DIContainer: \(error)")
        }
    }
}
