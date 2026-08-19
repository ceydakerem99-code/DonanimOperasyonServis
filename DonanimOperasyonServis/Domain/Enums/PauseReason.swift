import Foundation

/// Reasons a technician may pause an in-progress work order.
///
/// Stored on `WorkOrder.currentPauseReason` while the order is
/// `.paused` and copied into `WorkOrderStatusHistory` when the pause
/// transition is recorded.
enum PauseReason: String, CaseIterable, Hashable, Sendable, Codable {
    case partWaiting
    case customerWaiting
    case approvalWaiting
    case technicalSupportWaiting
    case other
}

extension PauseReason {
    var displayName: String {
        switch self {
        case .partWaiting:             return "Parça bekleniyor"
        case .customerWaiting:         return "Müşteri bekleniyor"
        case .approvalWaiting:         return "Onay bekleniyor"
        case .technicalSupportWaiting: return "Teknik destek bekleniyor"
        case .other:                   return "Diğer"
        }
    }
}
