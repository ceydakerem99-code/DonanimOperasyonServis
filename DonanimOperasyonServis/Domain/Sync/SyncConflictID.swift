import Foundation

/// Typed identifier for a `SyncConflict`.
struct SyncConflictID: Hashable, Sendable, Codable {
    let rawValue: String

    init(_ rawValue: String) {
        self.rawValue = rawValue
    }
}

extension SyncConflictID: CustomStringConvertible {
    var description: String { rawValue }
}
