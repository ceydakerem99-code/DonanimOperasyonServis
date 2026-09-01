import Foundation

/// Sequential local-queue → remote-repository executor.
///
/// An `actor` so two `sync(operation:)` calls on the same instance
/// cannot interleave: the second caller observes `inProgress` /
/// `succeeded` / `conflict` and does not hit remote again.
///
/// Reachability is injected (`NetworkReachabilityProviding`). Offline
/// drains return `.deferredOffline` without touching retry metadata
/// and without calling remote. A remote `networkUnavailable` after
/// an attempt still goes through `SyncRetryPolicy`.
///
/// Photo / signature deferred Storage uploads run inside
/// `SyncRemoteDispatcher` via the injected `storage` data source.
///
/// Local business entities are never overwritten with a remote
/// response (Phase 5D reconciliation). Only the `SyncOperation`
/// row (and an optional `SyncConflict` row) is updated — except
/// when clearing a local `pending://` storage path after a
/// successful Storage upload.
actor LocalToRemoteSyncManager: SyncManaging {

    private let queue: any SyncOperationRepository
    private let conflicts: any SyncConflictRepository
    private let local: SyncEntityRepositories
    private let remote: SyncEntityRepositories
    private let reachability: any NetworkReachabilityProviding
    private let storage: (any FirebaseStorageDataSource)?
    private let authService: (any FirebaseAuthServing)?
    /// Optional progress hook (index, total) — used by DEBUG UI.
    private let onProgress: (@Sendable (Int, Int) async -> Void)?
    /// Guards re-entrant `await` points so the same `id` cannot be
    /// dispatched twice on this instance.
    private var inFlightIDs: Set<String> = []
    private var lastReport: SyncDrainReport?

    init(
        queue: any SyncOperationRepository,
        conflicts: any SyncConflictRepository,
        local: SyncEntityRepositories,
        remote: SyncEntityRepositories,
        reachability: any NetworkReachabilityProviding,
        storage: (any FirebaseStorageDataSource)? = nil,
        authService: (any FirebaseAuthServing)? = nil,
        onProgress: (@Sendable (Int, Int) async -> Void)? = nil
    ) {
        self.queue = queue
        self.conflicts = conflicts
        self.local = local
        self.remote = remote
        self.reachability = reachability
        self.storage = storage
        self.authService = authService
        self.onProgress = onProgress
    }

    func lastDrainReport() async -> SyncDrainReport? {
        lastReport
    }

    func issueSnapshot() async throws -> SyncIssueSnapshot {
        try await currentIssueSnapshot()
    }

    private func currentIssueSnapshot(at date: Date = Date()) async throws -> SyncIssueSnapshot {
        let failed = try await operationsForCurrentSession(try await queue.fetch(status: .failed))
        let pending = try await operationsForCurrentSession(try await queue.fetch(status: .pending))
        let succeeded = try await operationsForCurrentSession(try await queue.fetch(status: .succeeded))
        let conflicts = try await operationsForCurrentSession(try await queue.fetch(status: .conflict))
        let irrelevantFailed = try await SyncQueueOperationalStaleness.irrelevantFailedIDs(
            failed: failed,
            queue: queue,
            local: local
        )
        return SyncQueueIssueClassifier.snapshot(
            failed: failed,
            pending: pending,
            succeeded: succeeded,
            conflicts: conflicts,
            irrelevantFailedIDs: Set(irrelevantFailed),
            at: date
        )
    }

    func syncPending(now: Date) async throws -> SyncDrainOutcome {
        let startedAt = Date()
        guard await reachability.isReachable else {
            let snapshot = (try? await currentIssueSnapshot(at: Date())) ?? .empty()
            let report = SyncDrainReport(
                startedAt: startedAt,
                finishedAt: Date(),
                pendingAtStart: 0,
                succeeded: 0,
                failed: 0,
                retried: 0,
                held: 0,
                conflicts: 0,
                operations: [],
                deferredOffline: true,
                activeFailedCount: snapshot.activeFailedCount,
                retryableFailedCount: snapshot.retryableFailedCount
            )
            lastReport = report
            AppLogger.sync.info(
                "SYNC AUTO-DRAIN SKIP reason=deferredOffline pending=\(snapshot.pendingCount) retryableFailed=\(snapshot.retryableFailedCount)"
            )
            return .deferredOffline
        }

        AppLogger.sync.info("SYNC AUTO-DRAIN START pendingQuery")

        try await requeueActorMatchedFailedOperations(now: now)
        try await acknowledgeIdempotentCompletedWorkOrderChain(now: now)
        try await requeueResolvedDependencyBlockedOperations(now: now)
        try await requeueUnauthorizedChildrenIfRemoteParentReady(now: now)
        try await backfillMissingActorUserIdOnPendingOperations(now: now)

        let allPending = sortForDrain(try await queue.fetchPending(now: now))
        let foreignSkipped = try await SyncOperationUserScope.foreignOperationCount(
            in: allPending,
            authUID: authService?.currentUID,
            local: local
        )
        if foreignSkipped > 0, authService?.currentUID != nil {
            AppLogger.sync.info(
                "SYNC ACTOR MISMATCH skipped foreignOps=\(foreignSkipped, privacy: .public) sessionScopedPending=\(allPending.count - foreignSkipped, privacy: .public)"
            )
        }
        let pending = try await operationsForCurrentSession(allPending)
        let pendingAtStart = pending.count
        AppLogger.sync.info("SYNC AUTO-DRAIN START pendingCount=\(pendingAtStart)")
        await onProgress?(0, pendingAtStart)

        var timings: [SyncDrainReport.OperationTiming] = []
        var succeeded = 0
        var failed = 0
        var retried = 0
        var held = 0
        var conflicts = 0

        var pendingBatch = pending
        var passNumber = 0
        var heldOperationIDs: Set<String> = []
        while !pendingBatch.isEmpty && passNumber < 4 {
            passNumber += 1
            let pass = try await drainPass(
                operations: pendingBatch,
                passNumber: passNumber,
                heldOperationIDs: &heldOperationIDs,
                now: now
            )
            timings.append(contentsOf: pass.timings)
            succeeded += pass.succeeded
            failed += pass.failed
            retried += pass.retried
            held += pass.held
            conflicts += pass.conflicts

            guard pass.succeeded > 0 else { break }

            let nextAllPending = sortForDrain(try await queue.fetchPending(now: now))
            pendingBatch = try await operationsForCurrentSession(nextAllPending)
        }

        try await pruneStaleFailedAndCompletedOperations()
        let snapshot = try await currentIssueSnapshot(at: Date())

        let finishedAt = Date()
        let report = SyncDrainReport(
            startedAt: startedAt,
            finishedAt: finishedAt,
            pendingAtStart: pendingAtStart,
            succeeded: succeeded,
            failed: failed,
            retried: retried,
            held: held,
            conflicts: conflicts,
            operations: timings,
            deferredOffline: false,
            activeFailedCount: snapshot.activeFailedCount,
            retryableFailedCount: snapshot.retryableFailedCount
        )
        lastReport = report
        AppLogger.sync.info(
            "SYNC AUTO-DRAIN SUCCESS duration=\(String(format: "%.2f", report.totalDuration), privacy: .public)s succeeded=\(succeeded) retried=\(retried) failed=\(failed) held=\(held) conflict=\(conflicts)"
        )
        await logQueueDiagnostics(now: now)
        return .completed
    }

    private struct DrainPassStats: Sendable {
        var timings: [SyncDrainReport.OperationTiming]
        var succeeded: Int
        var failed: Int
        var retried: Int
        var held: Int
        var conflicts: Int
    }

    private func drainPass(
        operations: [SyncOperation],
        passNumber: Int,
        heldOperationIDs: inout Set<String>,
        now: Date
    ) async throws -> DrainPassStats {
        var timings: [SyncDrainReport.OperationTiming] = []
        var succeeded = 0
        var failed = 0
        var retried = 0
        var held = 0
        var conflicts = 0
        let batchCount = max(operations.count, 1)

        for (passIndex, operation) in operations.enumerated() {
            await onProgress?(passIndex + 1, batchCount)
            let t0 = Date()
            let before = (try? await queue.fetch(id: operation.id)) ?? operation
            try await sync(operation: operation, now: now)
            let after = (try? await queue.fetch(id: operation.id)) ?? before
            let result = Self.classify(before: before, after: after)
            let duration = Date().timeIntervalSince(t0)
            timings.append(
                SyncDrainReport.OperationTiming(
                    index: passIndex + 1,
                    total: batchCount,
                    entityType: operation.entityType,
                    operationType: operation.operationType,
                    duration: duration,
                    result: result
                )
            )
            AppLogger.sync.info(
                "SYNC AUTO-DRAIN OP pass=\(passNumber, privacy: .public) \(passIndex + 1)/\(operations.count, privacy: .public) entity=\(operation.entityType.rawValue, privacy: .public) type=\(operation.operationType.rawValue, privacy: .public) id=\(operation.id.rawValue, privacy: .public) duration=\(String(format: "%.2f", duration), privacy: .public)s result=\(result.rawValue, privacy: .public) statusBefore=\(before.status.rawValue, privacy: .public) statusAfter=\(after.status.rawValue, privacy: .public)"
            )
            switch result {
            case .success: succeeded += 1
            case .failed: failed += 1
            case .retry: retried += 1
            case .held:
                if heldOperationIDs.insert(operation.id.rawValue).inserted {
                    held += 1
                }
            case .conflict: conflicts += 1
            case .skipped: break
            }
        }

        return DrainPassStats(
            timings: timings,
            succeeded: succeeded,
            failed: failed,
            retried: retried,
            held: held,
            conflicts: conflicts
        )
    }

    private static func classify(
        before: SyncOperation,
        after: SyncOperation
    ) -> SyncDrainReport.OperationResult {
        switch after.status {
        case .succeeded:
            return .success
        case .conflict:
            return .conflict
        case .failed:
            return after.retryCount > before.retryCount ? .retry : .failed
        case .pending, .inProgress:
            // Still pending after attempt → dependency / conflict hold.
            return .held
        }
    }

    func sync(operation: SyncOperation, now: Date) async throws {
        guard await reachability.isReachable else { return }

        let rawID = operation.id.rawValue
        guard !inFlightIDs.contains(rawID) else { return }
        inFlightIDs.insert(rawID)
        defer { inFlightIDs.remove(rawID) }

        let latest = try await queue.fetch(id: operation.id)

        if try await shouldAcknowledgeSupersededWorkOrderUpdate(latest, now: now) {
            return
        }
        if try await shouldAcknowledgeIdempotentCompletedWorkOrderOperation(latest, now: now) {
            return
        }
        if try await shouldHoldForActorMismatch(latest) {
            #if DEBUG
            AppLogger.sync.info(
                "SYNC ACTOR MISMATCH skipped id=\(operation.id.rawValue, privacy: .public) entity=\(operation.entityType.rawValue, privacy: .public)"
            )
            #endif
            return
        }
        if try await shouldHoldForOutstandingWorkOrderCreate(latest, now: now) {
            return
        }
        if try await shouldHoldForRemoteWorkOrderParent(latest, now: now) {
            return
        }
        if try await shouldHoldForUnresolvedOrAbandonedConflict(latest) {
            return
        }
        if try await shouldHoldForUnsatisfiedDependency(latest, now: now) {
            return
        }
        if try await shouldHoldForAssignmentNotificationRemoteReady(latest) {
            return
        }
        if try await shouldHoldWorkOrderCompletionForCompletedGPS(latest, now: now) {
            return
        }

        switch latest.status {
        case .inProgress, .succeeded, .conflict:
            return
        case .failed:
            try await queue.prepareRetry(id: latest.id)
        case .pending:
            break
        }

        var running = try await queue.fetch(id: operation.id)
        running.status = .inProgress
        running.lastAttemptAt = now
        running.updatedAt = now
        try await queue.update(running)
        running = try await queue.fetch(id: operation.id)

        do {
            try await SyncRemoteDispatcher.apply(
                operation: running,
                local: local,
                remote: remote,
                storage: storage
            )
            try await markSucceeded(running, now: now)
        } catch let signal as SyncConflictDetected {
            try await markConflict(running, signal: signal, now: now)
        } catch {
            let syncError = SyncErrorMapping.from(error)
            if syncError == .conflict {
                try await markConflict(
                    running,
                    signal: SyncConflictDetected(
                        localVersion: running.localVersion,
                        remoteVersion: running.remoteVersion,
                        localReference: running.payloadReference,
                        remoteReference: nil
                    ),
                    now: now
                )
            } else {
                try await markFailed(running, error: syncError, now: now)
            }
        }
    }

    // MARK: - Outcomes

    /// Drops stale `.failed` rows superseded by a newer `.succeeded`
    /// mutation of the same entity, then removes `.succeeded` rows so
    /// they do not accumulate in SwiftData.
    private func pruneStaleFailedAndCompletedOperations() async throws {
        let failed = try await queue.fetch(status: .failed)
        let succeeded = try await queue.fetch(status: .succeeded)
        let staleIDs = SyncQueueIssueClassifier.staleFailedIDs(
            failed: failed,
            succeeded: succeeded
        )
        let irrelevantIDs = try await SyncQueueOperationalStaleness.irrelevantFailedIDs(
            failed: failed,
            queue: queue,
            local: local
        )
        let pruneIDs = Array(Set(staleIDs + irrelevantIDs))
        if !pruneIDs.isEmpty {
            try await queue.deleteFailed(ids: pruneIDs)
        }
        let remoteDuplicateIDs = await remoteSupersededCreateFailedIDs(failed)
        if !remoteDuplicateIDs.isEmpty {
            try await queue.deleteFailed(ids: remoteDuplicateIDs)
        }
        // Do not prune permanent failed rows merely because the local
        // entity is missing — that erases real `notFound` / `unauthorized`
        // outcomes and turns them into silent queue disappearance.
        try await queue.deleteCompleted()
    }

    /// Pending rows enqueued before `actorUserId` was persisted infer
    /// the true owner from local entity data — never stamp the active
    /// session UID onto another user's mutation.
    private func backfillMissingActorUserIdOnPendingOperations(now: Date) async throws {
        let pending = try await queue.fetch(status: .pending)
        for operation in pending {
            let stored = operation.actorUserId?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard stored.isEmpty else { continue }
            guard let resolved = try await SyncOperationActorResolver.resolve(
                operation: operation,
                local: local
            ), !resolved.isEmpty else {
                continue
            }
            var updated = operation
            updated.actorUserId = resolved
            updated.updatedAt = now
            try await queue.update(updated)
        }
    }

    /// Failed `.create` rows whose entity already exists remotely are
    /// duplicate queue noise — safe to drop without touching Firestore.
    private func remoteSupersededCreateFailedIDs(_ failed: [SyncOperation]) async -> [SyncOperationID] {
        var ids: [SyncOperationID] = []
        for operation in failed where operation.status == .failed && operation.operationType == .create {
            if await remoteEntityExists(operation) {
                ids.append(operation.id)
            }
        }
        return ids
    }

    private func remoteEntityExists(_ operation: SyncOperation) async -> Bool {
        do {
            switch operation.entityType {
            case .user:
                _ = try await remote.users.fetch(id: UserID(operation.entityId))
                return true
            case .customer:
                _ = try await remote.customers.fetch(id: CustomerID(operation.entityId))
                return true
            case .workOrder:
                _ = try await remote.workOrders.fetch(id: WorkOrderID(operation.entityId))
                return true
            case .workOrderNote, .workOrderPhoto, .workOrderLocation,
                 .workOrderStatusHistory, .signature, .editRequest, .notification:
                return false
            case .customerSatisfaction:
                _ = try await remote.customerSatisfactions.fetch(id: CustomerSatisfactionID(operation.entityId))
                return true
            }
        } catch let error as DomainError {
            if case .notFound = error { return false }
            return false
        } catch {
            return false
        }
    }

    private func logQueueDiagnostics(now: Date) async {
        do {
            let failed = try await queue.fetch(status: .failed)
            let pending = try await queue.fetch(status: .pending)
            let authUID = authService?.currentUID
            var holdReasons: [SyncOperationID: SyncQueueDiagnostics.HoldReason] = [:]
            for operation in pending {
                let reason = try await SyncQueueHoldEvaluator.classify(
                    operation: operation,
                    queue: queue,
                    local: local,
                    remote: remote,
                    authUID: authUID,
                    now: now
                )
                holdReasons[operation.id] = reason
                AppLogger.sync.info(
                    "SYNC HELD \(SyncQueueDiagnostics.operationDetailLine(operation, holdReason: reason), privacy: .public) authUID=\(authUID ?? "-", privacy: .public)"
                )
            }
            let report = SyncQueueDiagnostics.makeReport(
                failed: failed,
                pending: pending,
                holdReasons: holdReasons
            )
            SyncQueueDiagnostics.logSummary(report)
            for operation in failed {
                AppLogger.sync.info(
                    "SYNC FAILED \(SyncQueueDiagnostics.operationDetailLine(operation), privacy: .public)"
                )
            }
        } catch {
            AppLogger.sync.error("SYNC QUEUE DIAG failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func operationsForCurrentSession(_ operations: [SyncOperation]) async throws -> [SyncOperation] {
        if authService == nil {
            return operations
        }
        guard let uid = authService?.currentUID?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !uid.isEmpty else {
            return []
        }
        return try await SyncOperationUserScope.filter(
            operations,
            authUID: uid,
            local: local
        )
    }

    /// Acknowledge completion GPS + work-order rows when Firestore already
    /// reflects `.completed` so dependency chains (e.g. customer satisfaction)
    /// are not blocked by stale `unauthorized` or `remoteParentCompleted` holds.
    private func acknowledgeIdempotentCompletedWorkOrderChain(now: Date) async throws {
        let pending = try await operationsForCurrentSession(
            try await queue.fetchPending(now: now)
        )
        let failed = try await operationsForCurrentSession(
            try await queue.fetch(status: .failed)
        )
        let candidates = (pending + failed).sorted { lhs, rhs in
            if lhs.entityType == .workOrderLocation, rhs.entityType == .workOrder {
                return true
            }
            if lhs.entityType == .workOrder, rhs.entityType == .workOrderLocation {
                return false
            }
            return lhs.createdAt < rhs.createdAt
        }
        for operation in candidates where operation.status != .succeeded {
            guard try await SyncCompletionGPSOrdering
                .shouldAcknowledgeWithoutRemoteWriteWhenBothOrdersCompleted(
                    operation,
                    queue: queue,
                    local: local,
                    remote: remote
                ) else {
                continue
            }
            try await acknowledgeWithoutRemoteWrite(operation, now: now)
        }
    }

    /// Legacy unauthorized child rows (from before remote-parent hold)
    /// are retried once the parent is actually on Firestore. Customer /
    /// user unauthorized failures stay permanent.
    private func requeueUnauthorizedChildrenIfRemoteParentReady(now: Date) async throws {
        let failed = try await operationsForCurrentSession(try await queue.fetch(status: .failed))
        for operation in failed {
            guard operation.nextRetryAt == nil else { continue }
            guard isUnauthorizedFailure(operation) else { continue }
            guard SyncPolicy.requiresWorkOrderPayloadReference(operation.entityType) else {
                continue
            }
            if try await shouldHoldForActorMismatch(operation) {
                continue
            }
            if try await SyncRemoteWorkOrderGuard.evaluate(
                operation: operation,
                remote: remote,
                local: local,
                authUID: authService?.currentUID
            ) != nil {
                continue
            }
            try await queue.prepareRetry(id: operation.id)
        }
    }

    private func isUnauthorizedFailure(_ operation: SyncOperation) -> Bool {
        guard operation.status == .failed else { return false }
        let message = operation.errorMessage ?? ""
        return message == SyncError.unauthorized.diagnosticMessage
            || message.hasPrefix("unauthorized")
    }

    /// Re-queue rows blocked by a dependency once that dependency has succeeded.
    private func requeueResolvedDependencyBlockedOperations(now: Date) async throws {
        let failed = try await operationsForCurrentSession(try await queue.fetch(status: .failed))
        for operation in failed {
            guard operation.errorMessage?.hasPrefix("dependencyBlocked:") == true else {
                continue
            }
            if try await isDependencySatisfied(for: operation, now: now) {
                try await queue.prepareRetry(id: operation.id)
            }
        }
    }

    private func isDependencySatisfied(
        for operation: SyncOperation,
        now: Date
    ) async throws -> Bool {
        if let dependencyId = operation.dependsOnOperationId {
            return try await SyncExplicitDependencyEvaluator.isSatisfied(
                dependencyId: dependencyId,
                dependent: operation,
                queue: queue,
                local: local
            )
        }
        if operation.entityType == .workOrder, operation.operationType == .update {
            return try await allCompletedGPSCreatesSucceeded(for: operation)
        }
        return false
    }

    private func allCompletedGPSCreatesSucceeded(for operation: SyncOperation) async throws -> Bool {
        guard operation.entityType == .workOrder, operation.operationType == .update else {
            return false
        }
        let orderId = WorkOrderID(operation.entityId)
        guard let order = try? await local.workOrders.fetch(id: orderId),
              order.status == .completed else {
            return false
        }
        let completedLocations = try await local.locations.list(for: orderId)
            .filter { $0.event == .completed }
        guard !completedLocations.isEmpty else { return false }

        for location in completedLocations {
            let createOps = try await queue.list(
                entityType: .workOrderLocation,
                entityId: location.id
            ).filter { $0.operationType == .create }
            guard !createOps.isEmpty else { return false }
            guard createOps.allSatisfy({ $0.status == .succeeded }) else { return false }
        }
        return true
    }

    /// Child / WO mutations wait until an enqueued parent `workOrder.create`
    /// succeeds so Firestore rules see the remote parent document.
    private func shouldHoldForOutstandingWorkOrderCreate(
        _ operation: SyncOperation,
        now: Date
    ) async throws -> Bool {
        let workOrderId: String
        if operation.entityType == .workOrder {
            guard operation.operationType != .create else { return false }
            workOrderId = operation.entityId
        } else if SyncPolicy.requiresWorkOrderPayloadReference(operation.entityType),
                  let parentId = operation.payloadReference,
                  !parentId.isEmpty {
            workOrderId = parentId
        } else {
            return false
        }

        let woOps = try await queue.list(entityType: .workOrder, entityId: workOrderId)
        guard let createOp = woOps.first(where: { $0.operationType == .create }) else {
            return false
        }
        switch createOp.status {
        case .succeeded:
            return false
        case .pending, .inProgress, .conflict:
            return true
        case .failed:
            return true
        }
    }

    /// Remote parent must exist and satisfy Firestore technician rules
    /// before child rows or technician work-order updates hit Firebase.
    private func shouldHoldForRemoteWorkOrderParent(
        _ operation: SyncOperation,
        now: Date
    ) async throws -> Bool {
        guard let workOrderId = SyncRemoteWorkOrderGuard.parentWorkOrderId(for: operation) else {
            return false
        }

        let woOps = try await queue.list(entityType: .workOrder, entityId: workOrderId)
        if let createOp = woOps.first(where: { $0.operationType == .create }),
           createOp.status == .failed,
           isPermanentlyFailed(createOp, now: now) {
            try await markDependencyBlocked(operation, blockedBy: createOp, now: now)
            return true
        }

        if let reason = try await SyncRemoteWorkOrderGuard.evaluate(
            operation: operation,
            remote: remote,
            local: local,
            authUID: authService?.currentUID
        ) {
            switch reason {
            case .remoteParentMissing, .remoteParentCompleted, .technicianNotAssigned:
                return true
            }
        }
        return false
    }

    /// WO create → GPS/children → WO update completion ordering within a drain.
    private func sortForDrain(_ operations: [SyncOperation]) -> [SyncOperation] {
        operations.sorted { lhs, rhs in
            let leftPriority = drainPriority(lhs)
            let rightPriority = drainPriority(rhs)
            if leftPriority != rightPriority { return leftPriority < rightPriority }
            if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
            return lhs.id.rawValue < rhs.id.rawValue
        }
    }

    private func drainPriority(_ operation: SyncOperation) -> Int {
        switch operation.entityType {
        case .workOrder:
            switch operation.operationType {
            case .create: return 0
            case .update, .delete: return 30
            }
        case .workOrderLocation: return 10
        case .workOrderStatusHistory: return 20
        case .workOrderNote, .workOrderPhoto, .signature: return 20
        case .user: return 5
        case .customer: return 5
        case .editRequest, .notification, .customerSatisfaction: return 40
        }
    }

    private func requeueDependentsAfterSuccess(
        of succeeded: SyncOperation,
        now: Date
    ) async throws {
        let failed = try await queue.fetch(status: .failed)
        for operation in failed {
            guard operation.errorMessage?.hasPrefix("dependencyBlocked:") == true else {
                continue
            }
            if operation.dependsOnOperationId == succeeded.id {
                try await queue.prepareRetry(id: operation.id)
                continue
            }
            if succeeded.entityType == .workOrderLocation,
               succeeded.operationType == .create,
               operation.entityType == .workOrder,
               operation.entityId == succeeded.payloadReference,
               try await allCompletedGPSCreatesSucceeded(for: operation) {
                try await queue.prepareRetry(id: operation.id)
            }
        }
    }

    /// Re-queue `.failed` rows whose actor now matches the active Auth
    /// session (e.g. after a technician signs in). Does not override
    /// `SyncRetryPolicy` backoff for scheduled network retries.
    private func requeueActorMatchedFailedOperations(now: Date) async throws {
        guard let currentUID = authService?.currentUID else { return }
        let failed = try await operationsForCurrentSession(try await queue.fetch(status: .failed))
        for operation in failed {
            guard isEligibleForAutomaticRetry(operation, now: now) == false else { continue }
            guard operation.nextRetryAt == nil else { continue }
            let actorUID = try await SyncOperationActorResolver.resolve(
                operation: operation,
                local: local
            )
            guard actorUID == currentUID else { continue }
            guard operation.errorMessage?.hasPrefix("actorMismatch:") == true else {
                continue
            }
            try await queue.prepareRetry(id: operation.id)
        }
    }

    /// Remote writes must run under the Firebase Auth UID that enqueued
    /// the row. Mismatch is held silently until the correct user signs in.
    private func shouldAcknowledgeSupersededWorkOrderUpdate(
        _ operation: SyncOperation,
        now: Date
    ) async throws -> Bool {
        guard operation.status != .succeeded else { return false }
        guard try await SyncCompletionGPSOrdering.isSupersededPreCompletionWorkOrderUpdate(
            operation,
            queue: queue,
            local: local
        ) else {
            return false
        }
        try await acknowledgeWithoutRemoteWrite(operation, now: now)
        return true
    }

    private func shouldAcknowledgeIdempotentCompletedWorkOrderOperation(
        _ operation: SyncOperation,
        now: Date
    ) async throws -> Bool {
        guard operation.status != .succeeded else { return false }
        guard try await SyncCompletionGPSOrdering
            .shouldAcknowledgeWithoutRemoteWriteWhenBothOrdersCompleted(
                operation,
                queue: queue,
                local: local,
                remote: remote
            ) else {
            return false
        }
        try await acknowledgeWithoutRemoteWrite(operation, now: now)
        return true
    }

    private func acknowledgeWithoutRemoteWrite(_ operation: SyncOperation, now: Date) async throws {
        var running = operation
        if running.status == .pending {
            running.status = .inProgress
            running.lastAttemptAt = now
            running.updatedAt = now
            try await queue.update(running)
            running = try await queue.fetch(id: operation.id)
        }
        try await markSucceeded(running, now: now)
    }

    private func shouldHoldForActorMismatch(_ operation: SyncOperation) async throws -> Bool {
        guard let authService else { return false }
        guard let currentUID = authService.currentUID else { return true }
        guard let actorUID = try await SyncOperationActorResolver.resolve(
            operation: operation,
            local: local
        ) else {
            return false
        }
        return actorUID != currentUID
    }

    private func isEligibleForAutomaticRetry(_ operation: SyncOperation, now: Date) -> Bool {
        guard operation.status == .failed else { return false }
        if let nextRetryAt = operation.nextRetryAt {
            return nextRetryAt <= now
        }
        return false
    }

    private func isPermanentlyFailed(_ operation: SyncOperation, now: Date) -> Bool {
        guard operation.status == .failed else { return false }
        if isEligibleForAutomaticRetry(operation, now: now) { return false }
        if let nextRetryAt = operation.nextRetryAt, nextRetryAt > now { return false }
        return true
    }

    private func markDependencyBlocked(
        _ operation: SyncOperation,
        blockedBy dependency: SyncOperation,
        now: Date
    ) async throws {
        let underlying = dependency.errorMessage ?? dependency.status.rawValue
        let syncError = SyncError.dependencyBlocked(
            blockingOperationId: dependency.id.rawValue,
            underlying: underlying
        )
        let targetMessage = syncError.diagnosticMessage

        var blocked = try await queue.fetch(id: operation.id)
        if blocked.status == .failed, blocked.errorMessage == targetMessage {
            return
        }

        // State machine allows pending → inProgress → failed, not pending → failed.
        if blocked.status == .pending {
            blocked.status = .inProgress
            blocked.lastAttemptAt = now
            blocked.updatedAt = now
            try await queue.update(blocked)
            blocked = try await queue.fetch(id: operation.id)
        }

        let recorded = blocked.retryCount
        blocked.retryCount = recorded + 1
        blocked.status = .failed
        blocked.lastAttemptAt = now
        blocked.nextRetryAt = nil
        blocked.errorMessage = targetMessage
        blocked.updatedAt = now
        try await queue.update(blocked)
    }

    /// Explicit `dependsOnOperationId`: wait until that row is
    /// `.succeeded` (crash/restart safe). Pending/failed/inProgress/
    /// conflict keeps this row parked without consuming a retry.
    private func shouldHoldForUnsatisfiedDependency(
        _ operation: SyncOperation,
        now: Date
    ) async throws -> Bool {
        guard let dependencyId = operation.dependsOnOperationId else {
            return false
        }
        if let dependency = try? await queue.fetch(id: dependencyId) {
            if try await SyncCompletionGPSOrdering
                .shouldAcknowledgeWithoutRemoteWriteWhenBothOrdersCompleted(
                    dependency,
                    queue: queue,
                    local: local,
                    remote: remote
                ) {
                try await acknowledgeWithoutRemoteWrite(dependency, now: now)
                return false
            }
            switch dependency.status {
            case .succeeded:
                return false
            case .pending, .inProgress, .conflict:
                return true
            case .failed:
                if isPermanentlyFailed(dependency, now: now) {
                    try await markDependencyBlocked(operation, blockedBy: dependency, now: now)
                    return true
                }
                return true
            }
        }
        return try await SyncExplicitDependencyEvaluator.isUnsatisfied(
            dependencyId: dependencyId,
            dependent: operation,
            queue: queue,
            local: local
        )
    }

    /// Firestore notification rules require remote assignment parity.
    private func shouldHoldForAssignmentNotificationRemoteReady(
        _ operation: SyncOperation
    ) async throws -> Bool {
        try await SyncRemoteWorkOrderGuard.shouldHoldAssignmentNotification(
            operation: operation,
            local: local,
            remote: remote
        )
    }

    /// Belt-and-suspenders for completion updates that predate
    /// `dependsOnOperationId` or lost the link: do not push a local
    /// `completed` work order while a `.completed` GPS create for that
    /// order is still outstanding.
    private func shouldHoldWorkOrderCompletionForCompletedGPS(
        _ operation: SyncOperation,
        now: Date
    ) async throws -> Bool {
        try await SyncCompletionGPSOrdering.shouldHoldForCompletedGPS(
            operation: operation,
            queue: queue,
            local: local,
            now: now
        )
    }

    /// An unresolved conflict, or a `useRemote` resolution that
    /// abandoned the local mutation, must not be pushed again.
    /// `useLocal` lifts the hold so the existing state machine can
    /// continue (pending/failed rows) or a newly enqueued row can run.
    private func shouldHoldForUnresolvedOrAbandonedConflict(
        _ operation: SyncOperation
    ) async throws -> Bool {
        guard let conflict = try await conflicts.fetch(syncOperationId: operation.id) else {
            return false
        }
        switch conflict.resolution {
        case nil:
            return true
        case .useRemote:
            return true
        case .useLocal:
            return false
        }
    }

    private func markSucceeded(_ operation: SyncOperation, now: Date) async throws {
        var done = operation
        done.status = .succeeded
        done.lastAttemptAt = now
        done.nextRetryAt = nil
        done.errorMessage = nil
        done.updatedAt = now
        try await queue.update(done)
        try await requeueDependentsAfterSuccess(of: done, now: now)
    }

    private func markFailed(
        _ operation: SyncOperation,
        error: SyncError,
        now: Date
    ) async throws {
        var failed = operation
        let recorded = failed.retryCount
        failed.retryCount = recorded + 1
        failed.status = .failed
        failed.lastAttemptAt = now
        failed.nextRetryAt = SyncRetryPolicy.nextRetryDate(
            error: error,
            retryCount: recorded,
            now: now
        )
        failed.errorMessage = error.diagnosticMessage
        failed.updatedAt = now
        try await queue.update(failed)
    }

    private func markConflict(
        _ operation: SyncOperation,
        signal: SyncConflictDetected,
        now: Date
    ) async throws {
        let record = SyncConflict.unresolved(
            syncOperationId: operation.id,
            entityType: operation.entityType,
            entityId: operation.entityId,
            localVersion: signal.localVersion,
            remoteVersion: signal.remoteVersion,
            localReference: signal.localReference,
            remoteReference: signal.remoteReference,
            detectedAt: now
        )
        try await conflicts.save(record)

        var conflicted = operation
        conflicted.status = .conflict
        conflicted.lastAttemptAt = now
        conflicted.nextRetryAt = nil
        conflicted.errorMessage = SyncError.conflict.diagnosticMessage
        conflicted.updatedAt = now
        try await queue.update(conflicted)
    }
}
