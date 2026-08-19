import Foundation

/// Typed identifier for an `EditRequest`.
struct EditRequestID: Hashable, Sendable, Codable {
    let rawValue: String

    init(_ rawValue: String) {
        self.rawValue = rawValue
    }
}

extension EditRequestID: CustomStringConvertible {
    var description: String { rawValue }
}
