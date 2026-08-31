import Foundation

/// Mirrors `LocalToRemoteSyncManager` hold guards for diagnostics and tests.
enum SyncQueueHoldEvaluator {

    static func classify(
        operation: SyncOperation,
        queue: any SyncOperationRepository,
        local: SyncEntityRepositories,
        remote: SyncEntityRepositories,
        authUID: String?,
        now: Date
    ) async throws -> SyncQueueDiagnostics.HoldReason {
        if try await actorMismatch(operation: operation, local: local, authUID: authUID) {
            return .actorMismatch
        }
        if try await outstandingWorkOrderCreate(operation: operation, queue: queue) {
            return .outstandingWorkOrderCreate
        }
        if let reason = try await remoteWorkOrderGuardReason(
            operation: operation,
            queue: queue,
            local: local,
            remote: remote,
            authUID: authUID,
            now: now
        ) {
            return reason
        }
        if try await unresolvedConflict(operation: operation, queue: queue) {
            return .unresolvedConflict
        }
        if try await unsatisfiedDependency(
            operation: operation,
            queue: queue,
            local: local,
            now: now
        ) {
            return .unsatisfiedDependency
        }
        if try await assignmentNotificationRemoteReady(
            operation: operation,
            local: local,
            remote: remote
        ) == false {
            return .unsatisfiedDependency
        }
        if try await completionGPSWait(operation: operation, queue: queue, local: local) {
            return .completionGPSWait
        }
        return .notApplicable
    }

    private static func actorMismatch(
        operation: SyncOperation,
        local: SyncEntityRepositories,
        authUID: String?
    ) async throws -> Bool {
        guard let authUID else { return true }
        guard let actorUID = try await SyncOperationActorResolver.resolve(
            operation: operation,
            local: local
        ) else {
            return false
        }
        return actorUID != authUID
    }

    private static func outstandingWorkOrderCreate(
        operation: SyncOperation,
        queue: any SyncOperationRepository
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
        case .pending, .inProgress, .conflict, .failed:
            return true
        }
    }

    private static func remoteWorkOrderGuardReason(
        operation: SyncOperation,
        queue: any SyncOperationRepository,
        local: SyncEntityRepositories,
        remote: SyncEntityRepositories,
        authUID: String?,
        now: Date
    ) async throws -> SyncQueueDiagnostics.HoldReason? {
        guard SyncRemoteWorkOrderGuard.parentWorkOrderId(for: operation) != nil else {
            return nil
        }

        if let reason = try await SyncRemoteWorkOrderGuard.evaluate(
            operation: operation,
            remote: remote,
            local: local,
            authUID: authUID
        ) {
            switch reason {
            case .remoteParentMissing: return .remoteParentMissing
            case .remoteParentCompleted: return .remoteParentCompleted
            case .technicianNotAssigned: return .technicianNotAssigned
            }
        }
        return nil
    }

    private static func unresolvedConflict(
        operation: SyncOperation,
        queue: any SyncOperationRepository
    ) async throws -> Bool {
        let conflicts = try await queue.fetchConflicts()
        return conflicts.contains { $0.entityType == operation.entityType && $0.entityId == operation.entityId }
    }

    private static func unsatisfiedDependency(
        operation: SyncOperation,
        queue: any SyncOperationRepository,
        local: SyncEntityRepositories,
        now: Date
    ) async throws -> Bool {
        guard let dependencyId = operation.dependsOnOperationId else { return false }
        if let dependency = try? await queue.fetch(id: dependencyId) {
            switch dependency.status {
            case .succeeded:
                return false
            case .pending, .inProgress, .conflict:
                return true
            case .failed:
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

    private static func assignmentNotificationRemoteReady(
        operation: SyncOperation,
        local: SyncEntityRepositories,
        remote: SyncEntityRepositories
    ) async throws -> Bool {
        try await !SyncRemoteWorkOrderGuard.shouldHoldAssignmentNotification(
            operation: operation,
            local: local,
            remote: remote
        )
    }

    private static func completionGPSWait(
        operation: SyncOperation,
        queue: any SyncOperationRepository,
        local: SyncEntityRepositories
    ) async throws -> Bool {
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
            guard !createOps.isEmpty else { return true }
            guard createOps.allSatisfy({ $0.status == .succeeded }) else { return true }
        }
        return false
    }
}
