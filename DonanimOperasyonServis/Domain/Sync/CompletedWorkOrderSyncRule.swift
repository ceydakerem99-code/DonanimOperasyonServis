import Foundation

/// Classifies local vs remote work-order status when they differ.
///
/// If either side is `.completed` and the other is not, the outcome
/// is always `.conflict`. Sync must **not** automatically:
///
/// - reopen a remotely completed order because local is `inProgress`
/// - overwrite remote `inProgress` with local `completed` without
///   a resolver decision
///
/// `ConflictResolver` (later phase) is the only place that may
/// choose `useLocal` or `useRemote`.
enum CompletedWorkOrderSyncRule {

    enum Divergence: Hashable, Sendable {
        case none
        case conflict
        case other
    }

    static func classify(
        local: WorkOrderStatus,
        remote: WorkOrderStatus
    ) -> Divergence {
        if local == remote { return .none }
        if local == .completed || remote == .completed {
            return .conflict
        }
        return .other
    }

    static func isConflict(local: WorkOrderStatus, remote: WorkOrderStatus) -> Bool {
        classify(local: local, remote: remote) == .conflict
    }
}
