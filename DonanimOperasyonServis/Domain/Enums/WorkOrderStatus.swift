import Foundation

/// Lifecycle of a work order. Transitions between statuses are
/// governed by `WorkOrderStateMachine`.
///
/// `completed` is a terminal status. It cannot be exited via normal
/// status transitions; only an approved `EditRequest` may mutate
/// specific fields of a completed work order.
enum WorkOrderStatus: String, CaseIterable, Hashable, Sendable, Codable {
    case assigned
    case accepted
    case rejected
    case enRoute
    case arrived
    case inProgress
    case paused
    case completed
}

extension WorkOrderStatus {
    var displayName: String {
        switch self {
        case .assigned:   return "Atandı"
        case .accepted:   return "Kabul Edildi"
        case .rejected:   return "Reddedildi"
        case .enRoute:    return "Yola Çıkıldı"
        case .arrived:    return "Müşteriye Varıldı"
        case .inProgress: return "İşlemde"
        case .paused:     return "Beklemede"
        case .completed:  return "Tamamlandı"
        }
    }

    /// A completed or rejected work order is locked from any further
    /// normal state-machine transitions.
    var isTerminal: Bool { self == .completed || self == .rejected }

    /// Technician is actively working a job in the field (not merely assigned).
    var isActivelyInField: Bool {
        switch self {
        case .accepted, .enRoute, .arrived, .inProgress:
            return true
        case .assigned, .rejected, .paused, .completed:
            return false
        }
    }
}
