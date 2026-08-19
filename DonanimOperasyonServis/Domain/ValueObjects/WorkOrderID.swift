import Foundation

/// Typed identifier for a `WorkOrder`.
struct WorkOrderID: Hashable, Sendable, Codable {
    let rawValue: String

    init(_ rawValue: String) {
        self.rawValue = rawValue
    }
}

extension WorkOrderID: CustomStringConvertible {
    var description: String { rawValue }
}
