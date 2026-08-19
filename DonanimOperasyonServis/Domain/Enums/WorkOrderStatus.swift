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
        case .enRoute:    return "Yola Çıkıldı"
        case .arrived:    return "Müşteriye Varıldı"
        case .inProgress: return "İşlemde"
        case .paused:     return "Beklemede"
        case .completed:  return "Tamamlandı"
        }
    }

    /// A completed work order is locked from any further normal
    /// state-machine transitions. Only approved edit requests can
    /// modify specific fields.
    var isTerminal: Bool { self == .completed }
}
