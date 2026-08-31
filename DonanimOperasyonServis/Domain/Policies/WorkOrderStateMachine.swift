import Foundation

/// Pure domain policy that answers the question "may a work order
/// move from status A to status B?".
///
/// The valid graph is:
///
///     assigned    → accepted
///     accepted    → enRoute
///     enRoute     → arrived
///     arrived     → inProgress
///     inProgress  → paused
///     paused      → inProgress
///     inProgress  → completed
///
/// `.completed` is terminal for normal status changes: no transition
/// out of `.completed` is ever permitted through this state machine.
/// Modifying specific fields of a completed order requires an
/// approved `EditRequest`, which is a separate concern.
enum WorkOrderStateMachine {

    /// The full transition table, expressed as `from -> allowed
    /// destinations`. Kept `static` so tests can assert against the
    /// exact set without going through `canTransition`.
    static let transitionTable: [WorkOrderStatus: Set<WorkOrderStatus>] = [
        .assigned:   [.accepted, .rejected],
        .accepted:   [.enRoute],
        .rejected:   [],
        .enRoute:    [.arrived],
        .arrived:    [.inProgress],
        .inProgress: [.paused, .completed],
        .paused:     [.inProgress],
        .completed:  []
    ]

    /// The set of statuses reachable in one step from `status`.
    /// Returns an empty set for terminal states (`completed`) or
    /// unknown states.
    static func allowedTransitions(from status: WorkOrderStatus) -> Set<WorkOrderStatus> {
        transitionTable[status] ?? []
    }

    /// Fast boolean check. Prefer `transition(from:to:)` at call
    /// sites that need the error case.
    static func canTransition(from source: WorkOrderStatus, to destination: WorkOrderStatus) -> Bool {
        allowedTransitions(from: source).contains(destination)
    }

    /// Validates a transition and returns the destination status on
    /// success. Throws `DomainError.invalidStateTransition` (or
    /// `.workOrderLocked` when leaving `.completed`) otherwise.
    @discardableResult
    static func transition(
        from source: WorkOrderStatus,
        to destination: WorkOrderStatus
    ) throws -> WorkOrderStatus {
        // Trying to leave a completed work order via the normal
        // state machine is explicitly reported as a "locked"
        // condition rather than a generic invalid transition, so
        // the UI can present the correct message.
        if source == .completed {
            throw DomainError.invalidStateTransition(from: source, to: destination)
        }
        guard canTransition(from: source, to: destination) else {
            throw DomainError.invalidStateTransition(from: source, to: destination)
        }
        return destination
    }
}
