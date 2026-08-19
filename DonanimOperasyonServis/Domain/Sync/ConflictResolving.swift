import Foundation

/// Manual conflict resolution. No UI, no network monitor, no
/// background scheduler — callers invoke `resolve` explicitly.
protocol ConflictResolving: Sendable {
    func resolve(
        conflictID: SyncConflictID,
        decision: ConflictResolutionDecision,
        actor: User,
        now: Date
    ) async throws -> ConflictResolutionOutcome
}

extension ConflictResolving {
    func resolve(
        conflictID: SyncConflictID,
        decision: ConflictResolutionDecision,
        actor: User
    ) async throws -> ConflictResolutionOutcome {
        try await resolve(
            conflictID: conflictID,
            decision: decision,
            actor: actor,
            now: Date()
        )
    }
}

/// Result of one `resolve` call. The `conflict` snapshot versions
/// and references are the values captured at detection time.
struct ConflictResolutionOutcome: Hashable, Sendable {
    var conflict: SyncConflict
    var decision: ConflictResolutionDecision
    /// Set when this call inserted or reused a queue row. `nil` when
    /// no outbound operation was required (unresolved, useRemote, or
    /// an already-resolved replay).
    var enqueueOutcome: SyncEnqueueOutcome?
    /// `true` when this call (not a replay) wrote the remote Domain
    /// entity into the local repository.
    var didApplyRemote: Bool
}
