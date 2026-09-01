import Foundation

/// Resolves `dependsOnOperationId` for queue hold / retry decisions.
///
/// When the dependency row still exists, its live status is authoritative.
/// When it was pruned after `.succeeded`, infer satisfaction only from
/// safe entity evidence — never treat failed or unknown links as satisfied.
enum SyncExplicitDependencyEvaluator {

    static func isSatisfied(
        dependencyId: SyncOperationID,
        dependent: SyncOperation,
        queue: any SyncOperationRepository,
        local: SyncEntityRepositories
    ) async throws -> Bool {
        do {
            let dependency = try await queue.fetch(id: dependencyId)
            return dependency.status == .succeeded
        } catch let error as DomainError {
            guard case .notFound = error else { throw error }
            return try await inferPrunedSucceededDependency(
                dependent: dependent,
                queue: queue,
                local: local
            )
        }
    }

    /// Returns `true` when the dependent may proceed (dependency not blocking).
    static func isUnsatisfied(
        dependencyId: SyncOperationID,
        dependent: SyncOperation,
        queue: any SyncOperationRepository,
        local: SyncEntityRepositories
    ) async throws -> Bool {
        try await !isSatisfied(
            dependencyId: dependencyId,
            dependent: dependent,
            queue: queue,
            local: local
        )
    }

    // MARK: - Pruned dependency inference

    private static func inferPrunedSucceededDependency(
        dependent: SyncOperation,
        queue: any SyncOperationRepository,
        local: SyncEntityRepositories
    ) async throws -> Bool {
        switch dependent.entityType {
        case .notification:
            return try await inferPrunedNotificationDependency(
                dependent: dependent,
                queue: queue,
                local: local
            )
        case .customerSatisfaction:
            return try await inferPrunedCustomerSatisfactionDependency(
                dependent: dependent,
                queue: queue,
                local: local
            )
        default:
            return false
        }
    }

    /// Assignment notification create waits on a work-order write. When that
    /// dependency row was pruned post-success, verify there is no open WO queue
    /// work left and local assignment matches the notification recipient.
    private static func inferPrunedNotificationDependency(
        dependent: SyncOperation,
        queue: any SyncOperationRepository,
        local: SyncEntityRepositories
    ) async throws -> Bool {
        guard dependent.operationType == .create || dependent.operationType == .update else {
            return false
        }
        let recipientRaw = dependent.payloadReference?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !recipientRaw.isEmpty else { return false }

        let notifications = try await local.notifications.list(
            for: UserID(recipientRaw),
            unreadOnly: false
        )
        guard let notification = notifications.first(where: { $0.id.rawValue == dependent.entityId }) else {
            return false
        }
        guard notification.type == .workOrderAssigned,
              let workOrderId = notification.relatedWorkOrderId else {
            return false
        }

        let workOrderOps = try await queue.list(
            entityType: .workOrder,
            entityId: workOrderId.rawValue
        )
        let openWorkOrderOps = workOrderOps.filter { $0.status != .succeeded }
        guard openWorkOrderOps.isEmpty else { return false }

        guard let localOrder = try? await local.workOrders.fetch(id: workOrderId) else {
            return false
        }
        return localOrder.assignedTechnicianId == notification.recipientUserId
    }

    /// Customer-satisfaction create waits on the work-order completion
    /// update. When that dependency row was pruned post-success, verify the
    /// local survey exists, the parent order is completed locally, and no
    /// open work-order update remains in the queue.
    private static func inferPrunedCustomerSatisfactionDependency(
        dependent: SyncOperation,
        queue: any SyncOperationRepository,
        local: SyncEntityRepositories
    ) async throws -> Bool {
        guard dependent.operationType == .create || dependent.operationType == .update else {
            return false
        }
        let satisfactionId = CustomerSatisfactionID(dependent.entityId)
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
            $0.operationType == .update && $0.status != .succeeded
        }
        return openWorkOrderUpdates.isEmpty
    }
}
