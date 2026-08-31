import Foundation

/// Sorting for technician-assigned work order lists.
enum WorkOrderListSorting {
    /// Non-terminal first (priority urgent → high → normal, older `scheduledDate` first).
    /// Terminal orders stay at the bottom; completed is last within terminals.
    static func sortAssignedWorkOrders(_ orders: [WorkOrder]) -> [WorkOrder] {
        orders.sorted(by: compareAssignedWorkOrders)
    }

    static func compareAssignedWorkOrders(_ lhs: WorkOrder, _ rhs: WorkOrder) -> Bool {
        let lhsTerminal = lhs.status.isTerminal
        let rhsTerminal = rhs.status.isTerminal
        if lhsTerminal != rhsTerminal {
            return !lhsTerminal
        }
        if lhsTerminal && rhsTerminal {
            if lhs.status == .completed && rhs.status != .completed { return false }
            if rhs.status == .completed && lhs.status != .completed { return true }
            return lhs.scheduledDate > rhs.scheduledDate
        }
        if lhs.priority.sortOrder != rhs.priority.sortOrder {
            return lhs.priority.sortOrder > rhs.priority.sortOrder
        }
        return lhs.scheduledDate < rhs.scheduledDate
    }
}
