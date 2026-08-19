import Foundation

/// Restores `SyncOperation` rows left `.inProgress` after a process
/// death. Does **not** talk to remote, does **not** invent a new
/// queue row, and does **not** mark the operation `.succeeded`.
protocol SyncRecoveryHandling: Sendable {
    func recoverInterruptedOperations(now: Date) async throws -> SyncRecoveryOutcome
}

extension SyncRecoveryHandling {
    func recoverInterruptedOperations() async throws -> SyncRecoveryOutcome {
        try await recoverInterruptedOperations(now: Date())
    }
}

struct SyncRecoveryOutcome: Hashable, Sendable {
    /// Operations that were moved `inProgress → failed` in place.
    var recoveredOperationIDs: [SyncOperationID]
}
