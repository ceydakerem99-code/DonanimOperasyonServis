import Foundation

/// Manual remote → local reconciliation. No Firestore listener,
/// no polling scheduler. Callers invoke this explicitly (tests,
/// later a user/network trigger).
protocol Reconciling: Sendable {
    func reconcile(_ request: ReconciliationRequest, now: Date) async throws -> ReconciliationOutcome
}

extension Reconciling {
    func reconcile(_ request: ReconciliationRequest) async throws -> ReconciliationOutcome {
        try await reconcile(request, now: Date())
    }
}

/// Identifies one entity to compare. `parentId` is the work-order id
/// for child records and the recipient id for notifications —
/// the same convention as `SyncOperation.payloadReference`.
struct ReconciliationRequest: Hashable, Sendable {
    var entityType: SyncEntityType
    var entityId: String
    var parentId: String?
    var versions: ReconciliationVersionState

    init(
        entityType: SyncEntityType,
        entityId: String,
        parentId: String? = nil,
        versions: ReconciliationVersionState
    ) {
        self.entityType = entityType
        self.entityId = entityId
        self.parentId = parentId
        self.versions = versions
    }
}

struct ReconciliationOutcome: Hashable, Sendable {
    var result: ReconciliationResult
    var facts: ReconciliationFacts
    var persistedConflict: SyncConflict?
}
