import Foundation

/// Typed identifier for a `User`. Prevents accidental mixing with
/// other string-backed IDs in method signatures.
struct UserID: Hashable, Sendable, Codable {
    let rawValue: String

    init(_ rawValue: String) {
        self.rawValue = rawValue
    }
}

extension UserID: CustomStringConvertible {
    var description: String { rawValue }
}
