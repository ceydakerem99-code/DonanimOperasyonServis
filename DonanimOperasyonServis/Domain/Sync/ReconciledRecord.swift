import Foundation

/// Domain-typed local or remote record used by reconciliation.
/// DTOs never enter this type — callers convert remote payloads to
/// Domain before the engine sees them.
enum ReconciledRecord: Hashable, Sendable {
    case user(User)
    case customer(Customer)
    case workOrder(WorkOrder)
    case workOrderNote(WorkOrderNote)
    case workOrderPhoto(WorkOrderPhoto)
    case workOrderLocation(WorkOrderLocation)
    case workOrderStatusHistory(WorkOrderStatusHistory)
    case signature(Signature)
    case editRequest(EditRequest)
    case notification(AppNotification)
    case customerSatisfaction(CustomerSatisfaction)

    var workOrderStatus: WorkOrderStatus? {
        if case .workOrder(let order) = self { return order.status }
        return nil
    }
}
