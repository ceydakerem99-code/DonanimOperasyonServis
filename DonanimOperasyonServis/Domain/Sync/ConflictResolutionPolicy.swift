import Foundation

/// Observable facts for one conflict-resolution decision. The policy
/// is pure: it does not load repositories or write SwiftData.
struct ConflictResolutionFacts: Hashable, Sendable {
    var entityType: SyncEntityType
    var localWorkOrderStatus: WorkOrderStatus?
    var remoteWorkOrderStatus: WorkOrderStatus?
}

/// Whether `useLocal` / `useRemote` may be applied to a conflict.
///
/// `unresolved` is always allowed: it is the explicit "leave open"
/// decision, not an automatic winner.
enum ConflictResolutionPolicy {

    enum Restriction: Hashable, Sendable {
        case none
        /// Completed work orders stay locked. Field changes go
        /// through `EditRequest`; the resolver must not reopen or
        /// overwrite a completed order.
        case completedWorkOrder
        /// Edit-request status/content changes go through
        /// `ApproveEditRequestUseCase` / `RejectEditRequestUseCase`.
        case editRequestWorkflow
    }

    static func restriction(for facts: ConflictResolutionFacts) -> Restriction {
        if facts.entityType == .editRequest {
            return .editRequestWorkflow
        }
        if facts.entityType == .workOrder,
           facts.localWorkOrderStatus == .completed
            || facts.remoteWorkOrderStatus == .completed {
            return .completedWorkOrder
        }
        return .none
    }

    static func allows(
        _ decision: ConflictResolutionDecision,
        facts: ConflictResolutionFacts
    ) -> Bool {
        if decision == .unresolved { return true }
        return restriction(for: facts) == .none
    }

    static func rejectionReason(for facts: ConflictResolutionFacts) -> String {
        switch restriction(for: facts) {
        case .none:
            return "conflict.decisionNotRestricted"
        case .completedWorkOrder:
            return "conflict.completedWorkOrderMustStayUnresolved"
        case .editRequestWorkflow:
            return "conflict.editRequestWorkflowRequired"
        }
    }
}
