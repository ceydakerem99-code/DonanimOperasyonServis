import Foundation

/// Classifies local queue rows for badge / cleanup without talking to Firebase.
///
/// A `.failed` row is stale only when a **newer** `.succeeded` row exists
/// for the same `(entityType, entityId)`. Permanent `unauthorized` rows
/// without a later success are kept — they may never have reached Firestore.
enum SyncQueueIssueClassifier {

    enum FailedKind: Equatable, Sendable {
        case retryable
        case permanent
    }

    static func isNewerSucceeded(
        _ succeeded: SyncOperation,
        thanFailed failed: SyncOperation
    ) -> Bool {
        guard succeeded.status == .succeeded,
              failed.status == .failed,
              succeeded.entityType == failed.entityType,
              succeeded.entityId == failed.entityId
        else {
            return false
        }
        if succeeded.localVersion != failed.localVersion {
            return succeeded.localVersion > failed.localVersion
        }
        return succeeded.createdAt > failed.createdAt
    }

    static func staleFailedIDs(
        failed: [SyncOperation],
        succeeded: [SyncOperation]
    ) -> [SyncOperationID] {
        let successes = succeeded.filter { $0.status == .succeeded }
        let succeededWorkOrderIDs = Set(
            successes
                .filter { $0.entityType == .workOrder }
                .map(\.entityId)
        )
        var ids: [SyncOperationID] = []
        var seen = Set<SyncOperationID>()
        for row in failed where row.status == .failed {
            let superseded = successes.contains { isNewerSucceeded($0, thanFailed: row) }
            let parentSynced = SyncPolicy.requiresWorkOrderPayloadReference(row.entityType)
                && row.payloadReference.map { succeededWorkOrderIDs.contains($0) } == true
            if superseded || parentSynced, seen.insert(row.id).inserted {
                ids.append(row.id)
            }
        }
        return ids
    }

    static func snapshot(
        failed: [SyncOperation],
        pending: [SyncOperation],
        succeeded: [SyncOperation],
        conflicts: [SyncOperation],
        irrelevantFailedIDs: Set<SyncOperationID> = [],
        at date: Date = Date()
    ) -> SyncIssueSnapshot {
        let staleIDs = Set(staleFailedIDs(failed: failed, succeeded: succeeded))
        let activeFailed = failed.filter { operation in
            operation.status == .failed
                && !staleIDs.contains(operation.id)
                && !irrelevantFailedIDs.contains(operation.id)
        }
        return SyncIssueSnapshot(
            activeFailedCount: activeFailedCount(activeFailed),
            retryableFailedCount: retryableFailedCount(failed),
            pendingCount: pending.filter { $0.status == .pending }.count,
            succeededCount: succeeded.filter { $0.status == .succeeded }.count,
            conflictCount: conflicts.filter { $0.status == .conflict }.count,
            updatedAt: date
        )
    }

    static func kind(ofFailed operation: SyncOperation) -> FailedKind? {
        guard operation.status == .failed else { return nil }
        if operation.nextRetryAt != nil {
            return .retryable
        }
        return .permanent
    }

    static func activeFailedCount(_ operations: [SyncOperation]) -> Int {
        operations.reduce(into: 0) { count, operation in
            if kind(ofFailed: operation) == .permanent {
                count += 1
            }
        }
    }

    static func retryableFailedCount(_ operations: [SyncOperation]) -> Int {
        operations.reduce(into: 0) { count, operation in
            if kind(ofFailed: operation) == .retryable {
                count += 1
            }
        }
    }
}

/// Marks queue failures that no longer affect technician-facing UX after
/// the parent work order is durably completed locally.
enum SyncQueueOperationalStaleness {

    /// Failed rows safe to prune from the device queue and exclude from badge counts.
    static func irrelevantFailedIDs(
        failed: [SyncOperation],
        queue: any SyncOperationRepository,
        local: SyncEntityRepositories
    ) async throws -> [SyncOperationID] {
        var ids: [SyncOperationID] = []
        var seen = Set<SyncOperationID>()
        for operation in failed where operation.status == .failed {
            if try await isIrrelevantFailed(operation, queue: queue, local: local),
               seen.insert(operation.id).inserted {
                ids.append(operation.id)
            }
        }
        return ids
    }

    /// Whether a queue row should block the technician work-order detail sync banner.
    static func isDetailBlocking(
        _ operation: SyncOperation,
        workOrderStatus: WorkOrderStatus
    ) -> Bool {
        switch operation.status {
        case .pending, .inProgress:
            return true
        case .failed:
            return workOrderStatus != .completed
        case .succeeded, .conflict:
            return false
        }
    }

    /// Work-order queue row blocking the detail banner after completion-aware filtering.
    static func isWorkOrderOperationDetailBlocking(
        _ operation: SyncOperation,
        workOrder: WorkOrder,
        queue: any SyncOperationRepository
    ) async throws -> Bool {
        guard isDetailBlocking(operation, workOrderStatus: workOrder.status) else {
            return false
        }
        if try await SyncCompletionGPSOrdering.isSupersededPreCompletionWorkOrderUpdate(
            operation,
            workOrder: workOrder,
            queue: queue
        ) {
            return false
        }
        return true
    }

    /// `pending://` blocks only while an open photo/signature create is still queued.
    static func isMediaUploadDetailBlocking(
        hasPendingStoragePath: Bool,
        entityType: SyncEntityType,
        entityId: String,
        workOrder: WorkOrder,
        queue: any SyncOperationRepository
    ) async throws -> Bool {
        guard hasPendingStoragePath else { return false }
        let ops = try await queue.list(entityType: entityType, entityId: entityId)
        let hasOpenCreate = ops.contains {
            $0.operationType == .create
                && ($0.status == .pending || $0.status == .inProgress)
        }
        if workOrder.status == .completed, !hasOpenCreate {
            return false
        }
        return true
    }

    /// Note/location queue row blocking the detail banner after completion-aware filtering.
    static func isChildEvidenceOperationDetailBlocking(
        _ operation: SyncOperation,
        workOrder: WorkOrder,
        queue: any SyncOperationRepository
    ) async throws -> Bool {
        guard isDetailBlocking(operation, workOrderStatus: workOrder.status) else {
            return false
        }
        guard workOrder.status == .completed else { return true }
        let workOrderOps = try await queue.list(
            entityType: .workOrder,
            entityId: workOrder.id.rawValue
        )
        return workOrderOps.contains { $0.status == .pending || $0.status == .inProgress }
    }

    private static func isIrrelevantFailed(
        _ operation: SyncOperation,
        queue: any SyncOperationRepository,
        local: SyncEntityRepositories
    ) async throws -> Bool {
        switch operation.entityType {
        case .workOrder:
            return try await isIrrelevantCompletedWorkOrderUpdate(operation, queue: queue, local: local)
        case .customerSatisfaction:
            return try await isIrrelevantCustomerSatisfactionFailure(operation, queue: queue, local: local)
        case .workOrderNote, .workOrderPhoto, .workOrderLocation,
             .workOrderStatusHistory, .signature:
            return try await isIrrelevantChildEvidenceFailure(operation, queue: queue, local: local)
        case .user, .customer, .editRequest, .notification:
            return false
        }
    }

    private static func isIrrelevantCompletedWorkOrderUpdate(
        _ operation: SyncOperation,
        queue: any SyncOperationRepository,
        local: SyncEntityRepositories
    ) async throws -> Bool {
        guard operation.operationType == .update else { return false }
        if operation.errorMessage?.hasPrefix("dependencyBlocked:") == true {
            return false
        }
        let orderId = WorkOrderID(operation.entityId)
        guard let localOrder = try? await local.workOrders.fetch(id: orderId),
              localOrder.status == .completed else {
            return false
        }
        let workOrderOps = try await queue.list(
            entityType: .workOrder,
            entityId: orderId.rawValue
        )
        return !workOrderOps.contains { $0.status == .pending || $0.status == .inProgress }
    }

    private static func isIrrelevantCustomerSatisfactionFailure(
        _ operation: SyncOperation,
        queue: any SyncOperationRepository,
        local: SyncEntityRepositories
    ) async throws -> Bool {
        guard operation.operationType == .create || operation.operationType == .update else {
            return false
        }
        let satisfactionId = CustomerSatisfactionID(operation.entityId)
        guard let satisfaction = try? await local.customerSatisfactions.fetch(id: satisfactionId) else {
            return false
        }
        guard let localOrder = try? await local.workOrders.fetch(id: satisfaction.workOrderId),
              localOrder.status == .completed else {
            return false
        }
        let workOrderOps = try await queue.list(
            entityType: .workOrder,
            entityId: satisfaction.workOrderId.rawValue
        )
        let openWorkOrderUpdates = workOrderOps.filter {
            $0.operationType == .update
                && ($0.status == .pending || $0.status == .inProgress)
        }
        return openWorkOrderUpdates.isEmpty
    }

    private static func isIrrelevantChildEvidenceFailure(
        _ operation: SyncOperation,
        queue: any SyncOperationRepository,
        local: SyncEntityRepositories
    ) async throws -> Bool {
        guard SyncPolicy.requiresWorkOrderPayloadReference(operation.entityType) else {
            return false
        }
        let parentRaw = operation.payloadReference?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !parentRaw.isEmpty else { return false }
        let parentId = WorkOrderID(parentRaw)
        guard let localOrder = try? await local.workOrders.fetch(id: parentId),
              localOrder.status == .completed else {
            return false
        }
        let workOrderOps = try await queue.list(
            entityType: .workOrder,
            entityId: parentId.rawValue
        )
        return !workOrderOps.contains { $0.status == .pending || $0.status == .inProgress }
    }
}
