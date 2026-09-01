import Foundation

/// Completion work-order updates must wait for `.completed` GPS creates.
/// Intermediate pre-completion status writes must not participate in GPS
/// hold accounting and are acknowledged locally once completion is done.
enum SyncCompletionGPSOrdering {

    static func isSupersededPreCompletionWorkOrderUpdate(
        _ operation: SyncOperation,
        queue: any SyncOperationRepository,
        local: SyncEntityRepositories
    ) async throws -> Bool {
        guard operation.entityType == .workOrder,
              operation.operationType == .update,
              operation.dependsOnOperationId == nil else {
            return false
        }
        let orderId = WorkOrderID(operation.entityId)
        guard let order = try? await local.workOrders.fetch(id: orderId),
              order.status == .completed else {
            return false
        }
        return try await !isCompletionWorkOrderUpdate(
            operation,
            queue: queue,
            local: local
        )
    }

    static func shouldHoldForCompletedGPS(
        operation: SyncOperation,
        queue: any SyncOperationRepository,
        local: SyncEntityRepositories,
        now: Date
    ) async throws -> Bool {
        guard operation.entityType == .workOrder,
              operation.operationType == .update else {
            return false
        }
        guard try await isCompletionWorkOrderUpdate(
            operation,
            queue: queue,
            local: local
        ) else {
            return false
        }

        let orderId = WorkOrderID(operation.entityId)
        guard let order = try? await local.workOrders.fetch(id: orderId),
              order.status == .completed else {
            return false
        }

        if let dependencyId = operation.dependsOnOperationId,
           let dependency = try? await queue.fetch(id: dependencyId),
           dependency.status == .succeeded {
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

            if createOps.isEmpty {
                continue
            }
            if createOps.allSatisfy({ $0.status == .succeeded }) {
                continue
            }
            if createOps.contains(where: { $0.status == .pending || $0.status == .inProgress || $0.status == .conflict }) {
                return true
            }
            if createOps.contains(where: { $0.status == .failed && !isPermanentlyFailed($0, now: now) }) {
                return true
            }
        }
        return false
    }

    /// A completion push is either explicitly linked to GPS or the highest
    /// `localVersion` work-order update while the local order is completed.
    static func isCompletionWorkOrderUpdate(
        _ operation: SyncOperation,
        queue: any SyncOperationRepository,
        local: SyncEntityRepositories
    ) async throws -> Bool {
        if operation.dependsOnOperationId != nil { return true }

        let orderId = WorkOrderID(operation.entityId)
        guard let order = try? await local.workOrders.fetch(id: orderId) else {
            return false
        }
        return try await isCompletionWorkOrderUpdate(operation, queue: queue, workOrder: order)
    }

    static func isCompletionWorkOrderUpdate(
        _ operation: SyncOperation,
        queue: any SyncOperationRepository,
        workOrder: WorkOrder
    ) async throws -> Bool {
        if operation.dependsOnOperationId != nil { return true }
        guard workOrder.status == .completed else {
            return false
        }

        let activeUpdates = try await queue.list(
            entityType: .workOrder,
            entityId: operation.entityId
        ).filter {
            $0.operationType == .update
                && ($0.status == .pending || $0.status == .inProgress || $0.status == .failed)
        }
        let maxVersion = activeUpdates.map(\.localVersion).max() ?? operation.localVersion
        return operation.localVersion >= maxVersion
    }

    private static func isPermanentlyFailed(_ operation: SyncOperation, now: Date) -> Bool {
        guard operation.status == .failed else { return false }
        if let nextRetryAt = operation.nextRetryAt, nextRetryAt <= now {
            return false
        }
        if let nextRetryAt = operation.nextRetryAt, nextRetryAt > now {
            return false
        }
        return true
    }

    /// When Firestore already reflects `.completed`, outstanding completion
    /// GPS creates and work-order updates are idempotent and can be
    /// acknowledged locally without another remote write.
    static func shouldAcknowledgeWithoutRemoteWriteWhenBothOrdersCompleted(
        _ operation: SyncOperation,
        queue: any SyncOperationRepository,
        local: SyncEntityRepositories,
        remote: SyncEntityRepositories
    ) async throws -> Bool {
        guard try await bothLocalAndRemoteWorkOrderCompleted(
            operation,
            local: local,
            remote: remote
        ) else {
            return false
        }
        switch operation.entityType {
        case .workOrder:
            guard operation.operationType == .update else { return false }
            return try await isCompletionWorkOrderUpdate(
                operation,
                queue: queue,
                local: local
            )
        case .workOrderLocation:
            guard operation.operationType == .create else { return false }
            guard let workOrderId = SyncRemoteWorkOrderGuard.parentWorkOrderId(for: operation) else {
                return false
            }
            let locations = try await local.locations.list(for: WorkOrderID(workOrderId))
            return locations.first(where: { $0.id == operation.entityId })?.event == .completed
        default:
            return false
        }
    }

    static func bothLocalAndRemoteWorkOrderCompleted(
        _ operation: SyncOperation,
        local: SyncEntityRepositories,
        remote: SyncEntityRepositories
    ) async throws -> Bool {
        guard let workOrderId = SyncRemoteWorkOrderGuard.parentWorkOrderId(for: operation) else {
            return false
        }
        let orderId = WorkOrderID(workOrderId)
        guard let localOrder = try? await local.workOrders.fetch(id: orderId),
              localOrder.status == .completed else {
            return false
        }
        guard let remoteOrder = try? await remote.workOrders.fetch(id: orderId),
              remoteOrder.status == .completed else {
            return false
        }
        return true
    }

    static func isSupersededPreCompletionWorkOrderUpdate(
        _ operation: SyncOperation,
        workOrder: WorkOrder,
        queue: any SyncOperationRepository
    ) async throws -> Bool {
        guard operation.entityType == .workOrder,
              operation.operationType == .update,
              operation.dependsOnOperationId == nil,
              workOrder.status == .completed,
              WorkOrderID(operation.entityId) == workOrder.id else {
            return false
        }
        return try await !isCompletionWorkOrderUpdate(
            operation,
            queue: queue,
            workOrder: workOrder
        )
    }
}
