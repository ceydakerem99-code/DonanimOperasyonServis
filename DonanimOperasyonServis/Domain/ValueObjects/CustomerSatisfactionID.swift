import Foundation

/// Typed identifier for a `CustomerSatisfaction` record.
struct CustomerSatisfactionID: Hashable, Sendable, Codable {
    let rawValue: String

    init(_ rawValue: String) {
        self.rawValue = rawValue
    }
}

extension CustomerSatisfactionID: CustomStringConvertible {
    var description: String { rawValue }
}
