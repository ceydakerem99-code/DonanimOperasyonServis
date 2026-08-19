import Foundation
import OSLog

/// Central logging facade backed by Apple's unified logging system.
///
/// Loggers are grouped by subsystem/category so that filtering in Console
/// or `log show` is straightforward. Avoid `print` in application code —
/// use one of the loggers below (or extend this file with a new category).
enum AppLogger {

    /// Subsystem used for every `Logger` created in the app.
    ///
    /// Matches the bundle identifier configured in `project.yml`.
    static let subsystem = "com.donanimoperasyonservis.app"

    /// Application lifecycle events (launch, background, deep links).
    static let app = Logger(subsystem: subsystem, category: "app")

    /// Authentication and session events.
    static let auth = Logger(subsystem: subsystem, category: "auth")

    /// Navigation and coordinator transitions.
    static let navigation = Logger(subsystem: subsystem, category: "navigation")

    /// Local persistence (SwiftData) operations.
    static let dataLocal = Logger(subsystem: subsystem, category: "data.local")

    /// Remote data source (Firebase) operations.
    static let dataRemote = Logger(subsystem: subsystem, category: "data.remote")

    /// Sync queue, conflict detection, network transitions.
    static let sync = Logger(subsystem: subsystem, category: "sync")

    /// Location services (CoreLocation) events.
    static let location = Logger(subsystem: subsystem, category: "location")

    /// Camera and photo picker events.
    static let camera = Logger(subsystem: subsystem, category: "camera")

    /// Notifications (in-app + push).
    static let notifications = Logger(subsystem: subsystem, category: "notifications")
}
