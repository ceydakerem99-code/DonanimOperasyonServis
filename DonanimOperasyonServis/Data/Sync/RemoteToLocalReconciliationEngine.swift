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
        let localRecord = try await load(request, from: local)
        let remoteRecord = try await load(request, from: remote)

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
        switch record {
        case .user(let value):
            try await local.users.save(value)
        case .customer(let value):
            try await local.customers.save(value)
        case .workOrder(let value):
            try await local.workOrders.save(value)
        case .workOrderNote(let value):
            try await local.notes.save(value)
        case .workOrderPhoto(let value):
            try await local.photos.save(value)
        case .workOrderLocation(let value):
            try await local.locations.save(value)
        case .workOrderStatusHistory(let value):
            try await local.statusHistory.append(value)
        case .signature(let value):
            try await local.signatures.save(value)
        case .editRequest(let value):
            try await local.editRequests.save(value)
        case .notification(let value):
            try await local.notifications.save(value)
        }
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

    // MARK: - Load

    private func load(
        _ request: ReconciliationRequest,
        from repos: SyncEntityRepositories
    ) async throws -> ReconciledRecord? {
        do {
            return try await loadPresent(request, from: repos)
        } catch let error as DomainError {
            if case .notFound = error { return nil }
            throw error
        }
    }

    private func loadPresent(
        _ request: ReconciliationRequest,
        from repos: SyncEntityRepositories
    ) async throws -> ReconciledRecord {
        switch request.entityType {
        case .user:
            return .user(try await repos.users.fetch(id: UserID(request.entityId)))
        case .customer:
            return .customer(try await repos.customers.fetch(id: CustomerID(request.entityId)))
        case .workOrder:
            return .workOrder(try await repos.workOrders.fetch(id: WorkOrderID(request.entityId)))
        case .editRequest:
            return .editRequest(try await repos.editRequests.fetch(id: EditRequestID(request.entityId)))
        case .workOrderNote:
            return .workOrderNote(
                try await requireChild(
                    try await repos.notes.list(for: parentWorkOrderId(request)),
                    id: request.entityId,
                    entity: "WorkOrderNote",
                    key: \.id
                )
            )
        case .workOrderPhoto:
            return .workOrderPhoto(
                try await requireChild(
                    try await repos.photos.list(for: parentWorkOrderId(request)),
                    id: request.entityId,
                    entity: "WorkOrderPhoto",
                    key: \.id
                )
            )
        case .workOrderLocation:
            return .workOrderLocation(
                try await requireChild(
                    try await repos.locations.list(for: parentWorkOrderId(request)),
                    id: request.entityId,
                    entity: "WorkOrderLocation",
                    key: \.id
                )
            )
        case .workOrderStatusHistory:
            return .workOrderStatusHistory(
                try await requireChild(
                    try await repos.statusHistory.list(for: parentWorkOrderId(request)),
                    id: request.entityId,
                    entity: "WorkOrderStatusHistory",
                    key: \.id
                )
            )
        case .signature:
            return .signature(
                try await requireChild(
                    try await repos.signatures.list(for: parentWorkOrderId(request)),
                    id: request.entityId,
                    entity: "Signature",
                    key: \.id
                )
            )
        case .notification:
            let parent = try parentId(request, reason: "reconciliation.payloadReferenceMissing")
            let items = try await repos.notifications.list(for: UserID(parent), unreadOnly: false)
            guard let found = items.first(where: { $0.id.rawValue == request.entityId }) else {
                throw DomainError.notFound(entity: "AppNotification", id: request.entityId)
            }
            return .notification(found)
        }
    }

    private func parentWorkOrderId(_ request: ReconciliationRequest) throws -> WorkOrderID {
        WorkOrderID(try parentId(request, reason: "reconciliation.payloadReferenceMissing"))
    }

    private func parentId(_ request: ReconciliationRequest, reason: String) throws -> String {
        let raw = request.parentId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !raw.isEmpty else { throw DomainError.invalidData(reason: reason) }
        return raw
    }

    private func requireChild<T>(
        _ items: [T],
        id: String,
        entity: String,
        key: KeyPath<T, String>
    ) throws -> T {
        guard let found = items.first(where: { $0[keyPath: key] == id }) else {
            throw DomainError.notFound(entity: entity, id: id)
        }
        return found
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
