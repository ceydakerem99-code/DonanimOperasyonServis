import Foundation

/// State machine for `CustomerSatisfaction`. Kept separate from
/// `WorkOrderStateMachine` and `EditRequestStateMachine` because the
/// survey lifecycle is independent.
///
/// Valid transitions:
///
///     pending → submitted
///     pending → expired
///
/// `submitted` and `expired` are terminal.
enum CustomerSatisfactionStateMachine {

    static let transitionTable: [CustomerSatisfactionStatus: Set<CustomerSatisfactionStatus>] = [
        .pending:   [.submitted, .expired],
        .submitted: [],
        .expired:   []
    ]

    static func allowedTransitions(from status: CustomerSatisfactionStatus) -> Set<CustomerSatisfactionStatus> {
        transitionTable[status] ?? []
    }

    static func canTransition(from source: CustomerSatisfactionStatus, to destination: CustomerSatisfactionStatus) -> Bool {
        allowedTransitions(from: source).contains(destination)
    }

    @discardableResult
    static func transition(
        from source: CustomerSatisfactionStatus,
        to destination: CustomerSatisfactionStatus
    ) throws -> CustomerSatisfactionStatus {
        guard canTransition(from: source, to: destination) else {
            throw DomainError.invalidCustomerSatisfactionTransition(from: source, to: destination)
        }
        return destination
    }
}
