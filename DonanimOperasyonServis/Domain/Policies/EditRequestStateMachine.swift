import Foundation

/// State machine for `EditRequest`. Deliberately kept separate from
/// `WorkOrderStateMachine` because the two lifecycles are unrelated.
///
/// Valid transitions:
///
///     pending → approved
///     pending → rejected
///
/// `approved` and `rejected` are terminal. A decided edit request
/// cannot be re-decided; the requester must create a new one.
enum EditRequestStateMachine {

    static let transitionTable: [EditRequestStatus: Set<EditRequestStatus>] = [
        .pending:  [.approved, .rejected],
        .approved: [],
        .rejected: []
    ]

    static func allowedTransitions(from status: EditRequestStatus) -> Set<EditRequestStatus> {
        transitionTable[status] ?? []
    }

    static func canTransition(from source: EditRequestStatus, to destination: EditRequestStatus) -> Bool {
        allowedTransitions(from: source).contains(destination)
    }

    @discardableResult
    static func transition(
        from source: EditRequestStatus,
        to destination: EditRequestStatus
    ) throws -> EditRequestStatus {
        guard canTransition(from: source, to: destination) else {
            throw DomainError.invalidEditRequestTransition(from: source, to: destination)
        }
        return destination
    }
}
