import Foundation

/// Typed identifier for a `Customer`.
struct CustomerID: Hashable, Sendable, Codable {
    let rawValue: String

    init(_ rawValue: String) {
        self.rawValue = rawValue
    }
}

extension CustomerID: CustomStringConvertible {
    var description: String { rawValue }
}
