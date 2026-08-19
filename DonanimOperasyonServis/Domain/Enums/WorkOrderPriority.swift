import Foundation

/// Priority tiers assigned to a work order at creation time. There is
/// intentionally no `low` tier — the operations team decided a
/// three-level scale is easier to triage in the field.
enum WorkOrderPriority: String, CaseIterable, Hashable, Sendable, Codable {
    case normal
    case high
    case urgent
}

extension WorkOrderPriority {
    var displayName: String {
        switch self {
        case .normal: return "Normal"
        case .high:   return "Yüksek"
        case .urgent: return "Acil"
        }
    }

    /// A stable integer ordering for sorting lists. Higher = more urgent.
    var sortOrder: Int {
        switch self {
        case .normal: return 0
        case .high:   return 1
        case .urgent: return 2
        }
    }
}
