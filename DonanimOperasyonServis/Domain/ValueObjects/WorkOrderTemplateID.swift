import Foundation

/// Typed identifier for a `WorkOrderTemplate`.
struct WorkOrderTemplateID: Hashable, Sendable, Codable {
    let rawValue: String

    init(_ rawValue: String) {
        self.rawValue = rawValue
    }
}

extension WorkOrderTemplateID: CustomStringConvertible {
    var description: String { rawValue }
}
