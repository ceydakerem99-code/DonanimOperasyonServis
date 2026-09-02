import Foundation

/// Observable facts for one entity reconciliation. The policy is
/// pure: it does not load repositories or write SwiftData.
struct ReconciliationFacts: Hashable, Sendable {
    var entityType: SyncEntityType
    var entityId: String
    var localExists: Bool
    var remoteExists: Bool
    var contentsEqual: Bool
    var versions: ReconciliationVersionState
    /// `pending`, `inProgress`, `failed`, or `conflict` operations.
    /// Succeeded operations are acknowledgements of a 5C push and
    /// must **not** count — otherwise a successful local→remote
    /// apply would be misread as a remote→local mutation.
    var hasPendingLocalMutation: Bool
    var pendingOperationId: SyncOperationID?
    var localWorkOrderStatus: WorkOrderStatus?
    var remoteWorkOrderStatus: WorkOrderStatus?
}

/// Central decision table for remote → local reconciliation.
///
/// | local | remote | pending | versions        | result      |
/// |-------|--------|---------|-----------------|-------------|
/// | =     | =      | —       | —               | noChange    |
/// | exists| newer  | no      | valid           | applyRemote |
/// | exists| same   | yes     | remote unchanged| keepLocal   |
/// | exists| newer  | yes     | remote newer    | conflict    |
/// | exists| missing| yes     | —               | keepLocal   |
/// | exists| missing| no      | —               | conflict    |
/// | WO completed divergence | — | —      | conflict    |
enum ReconciliationPolicy {

    static func decide(_ facts: ReconciliationFacts) -> ReconciliationResult {
        if let completed = completedWorkOrderOverride(facts) {
            return completed
        }
        if let editRequest = editRequestOverride(facts) {
            return editRequest
        }

        switch (facts.localExists, facts.remoteExists) {
        case (false, false):
            return .noChange
        case (true, false):
            return facts.hasPendingLocalMutation ? .keepLocal : .conflict
        case (false, true):
            return decideLocalMissing(facts)
        case (true, true):
            return decideBothPresent(facts)
        }
    }

    // MARK: - Completed work order

    /// Any completed ↔ non-completed pair is a conflict. Matching
    /// `.completed` on both sides falls through to content/version
    /// comparison (no automatic reopen).
    private static func completedWorkOrderOverride(
        _ facts: ReconciliationFacts
    ) -> ReconciliationResult? {
        guard facts.entityType == .workOrder,
              let local = facts.localWorkOrderStatus,
              let remote = facts.remoteWorkOrderStatus
        else { return nil }
        if CompletedWorkOrderSyncRule.isConflict(local: local, remote: remote) {
            return .conflict
        }
        return nil
    }

    /// Edit-request rows are not merged by reconciliation. Status
    /// changes go through `ApproveEditRequestUseCase` /
    /// `RejectEditRequestUseCase`. Differing local/remote requests
    /// are a conflict; they are never applied onto a `WorkOrder`.
    private static func editRequestOverride(
        _ facts: ReconciliationFacts
    ) -> ReconciliationResult? {
        guard facts.entityType == .editRequest,
              facts.localExists,
              facts.remoteExists
        else { return nil }
        if facts.contentsEqual { return .noChange }
        return .conflict
    }

    // MARK: - Presence

    private static func decideLocalMissing(_ facts: ReconciliationFacts) -> ReconciliationResult {
        if facts.hasPendingLocalMutation {
            return .keepLocal
        }
        // First pull onto a device that has no row. Require a valid
        // remote version so missing metadata cannot silently win.
        if EntityVersionPolicy.isValid(facts.versions.remoteVersion) {
            return .applyRemote
        }
        return .conflict
    }

    private static func decideBothPresent(_ facts: ReconciliationFacts) -> ReconciliationResult {
        if facts.contentsEqual {
            return .noChange
        }

        let progress = EntityVersionPolicy.remoteProgress(
            current: facts.versions.remoteVersion,
            lastSynced: facts.versions.lastSyncedRemoteVersion
        )

        if facts.hasPendingLocalMutation {
            switch progress {
            case .unchanged, .unknown:
                return .keepLocal
            case .newer, .older:
                return .conflict
            }
        }

        switch progress {
        case .newer:
            guard EntityVersionPolicy.isValid(facts.versions.localVersion) else {
                return .conflict
            }
            return .applyRemote
        case .unchanged:
            return .keepLocal
        case .older, .unknown:
            return .conflict
        }
    }
}
