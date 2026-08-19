import Foundation

/// Sequential remote → local reconciler. Loads Domain entities
/// through repository protocols, asks `ReconciliationPolicy` for a
/// decision, then:
///
/// - `applyRemote` → `local.save(remoteDomainEntity)`
/// - `conflict` → persist `SyncConflict` (`unresolved`)
/// - `noChange` / `keepLocal` → no local business write
///
/// Never opens a `ModelContext`, never imports Firebase, never
/// deletes a `SyncOperation`, never approves an `EditRequest`.
actor RemoteToLocalReconciliationEngine: Reconciling {

    private let queue: any SyncOperationRepository
    private let conflicts: any SyncConflictRepository
    private let local: SyncEntityRepositories
    private let remote: SyncEntityRepositories
    private var inFlightKeys: Set<String> = []

    init(
        queue: any SyncOperationRepository,
        conflicts: any SyncConflictRepository,
        local: SyncEntityRepositories,
        remote: SyncEntityRepositories
    ) {
        self.queue = queue
        self.conflicts = conflicts
        self.local = local
        self.remote = remote
    }

    func reconcile(
        _ request: ReconciliationRequest,
        now: Date
    ) async throws -> ReconciliationOutcome {
        let key = "\(request.entityType.rawValue):\(request.entityId)"
        guard !inFlightKeys.contains(key) else {
            throw DomainError.invalidData(reason: "reconciliation.inFlight")
        }
        inFlightKeys.insert(key)
        defer { inFlightKeys.remove(key) }

        let operations = try await queue.list(
            entityType: request.entityType,
            entityId: request.entityId
        )
        let active = operations.filter { $0.status != .succeeded }
        let localRecord = try await SyncEntityRecordBridge.load(
            entityType: request.entityType,
            entityId: request.entityId,
            parentId: request.parentId,
            from: local,
            missingParentReason: "reconciliation.payloadReferenceMissing"
        )
        let remoteRecord = try await SyncEntityRecordBridge.load(
            entityType: request.entityType,
            entityId: request.entityId,
            parentId: request.parentId,
            from: remote,
            missingParentReason: "reconciliation.payloadReferenceMissing"
        )

        var versions = request.versions
        if versions.localVersion == nil {
            versions.localVersion = operations.map(\.localVersion).max()
        }
        if versions.lastSyncedRemoteVersion == nil {
            versions.lastSyncedRemoteVersion = operations
                .sorted { $0.createdAt > $1.createdAt }
                .first?
                .remoteVersion
        }

        let facts = ReconciliationFacts(
            entityType: request.entityType,
            entityId: request.entityId,
            localExists: localRecord != nil,
            remoteExists: remoteRecord != nil,
            contentsEqual: equals(localRecord, remoteRecord),
            versions: versions,
            hasPendingLocalMutation: !active.isEmpty,
            pendingOperationId: active.first?.id,
            localWorkOrderStatus: localRecord?.workOrderStatus,
            remoteWorkOrderStatus: remoteRecord?.workOrderStatus
        )

        let result = ReconciliationPolicy.decide(facts)
        var persisted: SyncConflict?

        switch result {
        case .noChange, .keepLocal:
            break
        case .applyRemote:
            guard let remoteRecord else {
                throw DomainError.invalidData(reason: "reconciliation.applyRemoteWithoutRemote")
            }
            try await applyRemote(remoteRecord)
        case .conflict:
            persisted = try await persistConflict(request: request, facts: facts, now: now)
        }

        return ReconciliationOutcome(
            result: result,
            facts: facts,
            persistedConflict: persisted
        )
    }

    // MARK: - Apply

    private func applyRemote(_ record: ReconciledRecord) async throws {
        try await SyncEntityRecordBridge.apply(record, to: local)
    }

    private func persistConflict(
        request: ReconciliationRequest,
        facts: ReconciliationFacts,
        now: Date
    ) async throws -> SyncConflict {
        let operationId = facts.pendingOperationId
            ?? SyncOperationID("reconcile:\(request.entityType.rawValue):\(request.entityId)")
        let conflict = SyncConflict.unresolved(
            syncOperationId: operationId,
            entityType: request.entityType,
            entityId: request.entityId,
            localVersion: facts.versions.localVersion ?? 0,
            remoteVersion: facts.versions.remoteVersion ?? 0,
            localReference: request.entityId,
            remoteReference: request.entityId,
            detectedAt: now
        )
        try await conflicts.save(conflict)
        return conflict
    }

    private func equals(_ lhs: ReconciledRecord?, _ rhs: ReconciledRecord?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil):
            return true
        case (let a?, let b?):
            return a == b
        default:
            return false
        }
    }
}
