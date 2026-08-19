import Foundation

/// Typed identifier for a `SyncOperation`.
struct SyncOperationID: Hashable, Sendable, Codable {
    let rawValue: String

    init(_ rawValue: String) {
        self.rawValue = rawValue
    }
}

extension SyncOperationID: CustomStringConvertible {
    var description: String { rawValue }
}
