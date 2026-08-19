import Foundation

/// Typed identifier for a `Notification`.
struct NotificationID: Hashable, Sendable, Codable {
    let rawValue: String

    init(_ rawValue: String) {
        self.rawValue = rawValue
    }
}

extension NotificationID: CustomStringConvertible {
    var description: String { rawValue }
}
