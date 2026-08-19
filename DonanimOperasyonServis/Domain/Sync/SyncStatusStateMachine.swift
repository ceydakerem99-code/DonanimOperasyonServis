import Foundation

/// Pure domain policy: "may a sync operation move from status A to
/// status B?".
///
///     pending    → inProgress
///     inProgress → succeeded
///     inProgress → failed
///     inProgress → conflict
///
/// `succeeded`, `failed`, and `conflict` are terminal in 5A.
enum SyncStatusStateMachine {

    static let transitionTable: [SyncStatus: Set<SyncStatus>] = [
        .pending:    [.inProgress],
        .inProgress: [.succeeded, .failed, .conflict],
        .succeeded:  [],
        .failed:     [],
        .conflict:   []
    ]

    static func allowedTransitions(from status: SyncStatus) -> Set<SyncStatus> {
        transitionTable[status] ?? []
    }

    static func canTransition(from source: SyncStatus, to destination: SyncStatus) -> Bool {
        allowedTransitions(from: source).contains(destination)
    }

    @discardableResult
    static func transition(
        from source: SyncStatus,
        to destination: SyncStatus
    ) throws -> SyncStatus {
        guard canTransition(from: source, to: destination) else {
            throw DomainError.invalidSyncStatusTransition(from: source, to: destination)
        }
        return destination
    }
}
