import Foundation

enum WorkOrderBulkMutationPolicy {
    /// Non-terminal work orders may receive operator bulk planning mutations.
    static func supportsBulkPlanningMutation(_ order: WorkOrder) -> Bool {
        !order.status.isTerminal
    }

    /// Admin bulk delete matches single-delete policy: completed orders are locked.
    static func supportsBulkDelete(_ order: WorkOrder) -> Bool {
        order.status != .completed
    }

    static func eligibleOrders(from orders: [WorkOrder]) -> [WorkOrder] {
        orders.filter(supportsBulkPlanningMutation)
    }

    static func eligibleOrdersForDelete(from orders: [WorkOrder]) -> [WorkOrder] {
        orders.filter(supportsBulkDelete)
    }
}

struct BulkWorkOrderMutationFailure: Equatable, Sendable {
    let orderId: WorkOrderID
    let workOrderNumber: String
    let reason: String
}

struct BulkWorkOrderMutationResult: Equatable, Sendable {
    var succeeded: [WorkOrderID] = []
    var failures: [BulkWorkOrderMutationFailure] = []

    var successCount: Int { succeeded.count }
    var failureCount: Int { failures.count }
    var isCompleteSuccess: Bool { failures.isEmpty && !succeeded.isEmpty }
    var isCompleteFailure: Bool { succeeded.isEmpty && !failures.isEmpty }
}
