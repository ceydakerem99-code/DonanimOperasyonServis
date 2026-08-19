import Foundation

/// Applies an explicit `ConflictResolutionDecision` to a persisted
/// `SyncConflict`.
///
/// Never infers a winner. Completed work-order and `EditRequest`
/// conflicts stay open. Does not import Firebase, does not open a
/// `ModelContext`, and does not start a network monitor.
actor LocalConflictResolver: ConflictResolving {

    private let queue: any SyncOperationRepository
    private let conflicts: any SyncConflictRepository
    private let local: SyncEntityRepositories
    private let remote: SyncEntityRepositories
    private var inFlightIDs: Set<String> = []

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

    func resolve(
        conflictID: SyncConflictID,
        decision: ConflictResolutionDecision,
        actor: User,
        now: Date
    ) async throws -> ConflictResolutionOutcome {
        let rawID = conflictID.rawValue
        guard !inFlightIDs.contains(rawID) else {
            throw DomainError.invalidData(reason: "conflict.resolveInFlight")
        }
        inFlightIDs.insert(rawID)
        defer { inFlightIDs.remove(rawID) }

        let conflict = try await conflicts.fetch(id: conflictID)

        guard RoleAccessPolicy.can(.resolveSyncConflict, as: actor.role) else {
            throw DomainError.unauthorized(action: .resolveSyncConflict)
        }

        if let stored = conflict.resolution {
            return try replayResolved(conflict, stored: stored, requested: decision)
        }

        if decision == .unresolved {
            return ConflictResolutionOutcome(
                conflict: conflict,
                decision: .unresolved,
                enqueueOutcome: nil,
                didApplyRemote: false
            )
        }

        let linked = try await linkedOperation(for: conflict)
        let parentId = linked?.payloadReference
        let localRecord = try await SyncEntityRecordBridge.load(
            entityType: conflict.entityType,
            entityId: conflict.entityId,
            parentId: parentId,
            from: local
        )
        let remoteRecord = try await SyncEntityRecordBridge.load(
            entityType: conflict.entityType,
            entityId: conflict.entityId,
            parentId: parentId,
            from: remote
        )

        let facts = ConflictResolutionFacts(
            entityType: conflict.entityType,
            localWorkOrderStatus: localRecord?.workOrderStatus,
            remoteWorkOrderStatus: remoteRecord?.workOrderStatus
        )
        guard ConflictResolutionPolicy.allows(decision, facts: facts) else {
            throw DomainError.invalidData(
                reason: ConflictResolutionPolicy.rejectionReason(for: facts)
            )
        }

        var enqueueOutcome: SyncEnqueueOutcome?
        var didApplyRemote = false

        switch decision {
        case .unresolved:
            break
        case .useLocal:
            enqueueOutcome = try await enqueueUseLocalIfNeeded(
                conflict: conflict,
                linked: linked,
                localRecord: localRecord,
                now: now
            )
        case .useRemote:
            guard let remoteRecord else {
                throw DomainError.notFound(
                    entity: conflict.entityType.rawValue,
                    id: conflict.entityId
                )
            }
            try await SyncEntityRecordBridge.apply(remoteRecord, to: local)
            didApplyRemote = true
        }

        guard let choice = decision.storedResolution else {
            throw DomainError.invalidData(reason: "conflict.missingStoredResolution")
        }
        let resolved = conflict.markingResolved(choice: choice, at: now, by: actor.id)
        try await conflicts.save(resolved)

        return ConflictResolutionOutcome(
            conflict: resolved,
            decision: decision,
            enqueueOutcome: enqueueOutcome,
            didApplyRemote: didApplyRemote
        )
    }

    // MARK: - Already resolved

    private func replayResolved(
        _ conflict: SyncConflict,
        stored: SyncConflictResolutionChoice,
        requested: ConflictResolutionDecision
    ) throws -> ConflictResolutionOutcome {
        if requested == .unresolved || requested.storedResolution == stored {
            return ConflictResolutionOutcome(
                conflict: conflict,
                decision: stored.asDecision,
                enqueueOutcome: nil,
                didApplyRemote: false
            )
        }
        throw DomainError.invalidData(reason: "conflict.alreadyResolved")
    }

    // MARK: - useLocal enqueue

    /// Reuses a still-runnable linked operation. When the linked row
    /// is terminal (`.conflict`) or missing, inserts a new pending
    /// row through `SyncPolicy` + idempotency keys.
    private func enqueueUseLocalIfNeeded(
        conflict: SyncConflict,
        linked: SyncOperation?,
        localRecord: ReconciledRecord?,
        now: Date
    ) async throws -> SyncEnqueueOutcome? {
        guard localRecord != nil else { return nil }

        if let linked {
            switch linked.status {
            case .pending, .failed:
                return .duplicate(existing: linked)
            case .inProgress, .succeeded, .conflict:
                break
            }
        }

        let operationType = outboundType(for: linked)
        let workOrderStatus = conflict.entityType == .workOrder
            ? localRecord?.workOrderStatus
            : nil
        guard SyncPolicy.canEnqueue(
            entityType: conflict.entityType,
            operationType: operationType,
            workOrderStatus: workOrderStatus
        ) else {
            return nil
        }

        var version = max(conflict.localVersion, linked?.localVersion ?? 0)
        for _ in 0..<64 {
            let candidate = try SyncOperation.pending(
                entityType: conflict.entityType,
                entityId: conflict.entityId,
                operationType: operationType,
                payloadReference: linked?.payloadReference ?? conflict.localReference,
                createdAt: now,
                localVersion: version,
                remoteVersion: conflict.remoteVersion,
                workOrderStatus: workOrderStatus
            )
            let outcome = try await queue.enqueue(candidate)
            switch outcome {
            case .inserted:
                return outcome
            case .duplicate(let existing):
                switch existing.status {
                case .pending, .failed:
                    return outcome
                case .inProgress, .succeeded, .conflict:
                    version += 1
                }
            }
        }
        throw DomainError.invalidData(reason: "conflict.enqueueExhausted")
    }

    private func outboundType(for linked: SyncOperation?) -> SyncOperationType {
        switch linked?.operationType {
        case .create, .update:
            return linked?.operationType ?? .update
        case .delete, nil:
            return .update
        }
    }

    private func linkedOperation(for conflict: SyncConflict) async throws -> SyncOperation? {
        do {
            return try await queue.fetch(id: conflict.syncOperationId)
        } catch let error as DomainError {
            if case .notFound = error { return nil }
            throw error
        }
    }
}
