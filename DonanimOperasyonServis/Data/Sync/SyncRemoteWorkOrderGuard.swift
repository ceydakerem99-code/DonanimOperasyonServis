import Foundation

/// Remote Firestore parent readiness for work-order sync rows.
///
/// Child technician writes and technician work-order updates require
/// the remote parent to exist, be assigned to the active Auth UID,
/// and (for most child creates) not be completed. Operator-scoped
/// rows only require the remote parent document when updating.
enum SyncRemoteWorkOrderGuard {

    enum HoldReason: Equatable, Sendable {
        case remoteParentMissing(workOrderId: String)
        case remoteParentCompleted(workOrderId: String)
        case technicianNotAssigned(workOrderId: String)
    }

    static func evaluate(
        operation: SyncOperation,
        remote: SyncEntityRepositories,
        local: SyncEntityRepositories,
        authUID: String?
    ) async throws -> HoldReason? {
        guard let workOrderId = parentWorkOrderId(for: operation) else {
            return nil
        }
        if operation.entityType == .workOrder, operation.operationType == .create {
            return nil
        }

        let technicianScoped = try await isTechnicianScoped(operation, local: local)

        let remoteOrder = try await fetchRemoteWorkOrder(
            id: WorkOrderID(workOrderId),
            remote: remote
        )
        if remoteOrder == nil {
            // Operator/admin work-order writes upsert via save(); remote parent
            // may not exist yet when assigning offline-created orders.
            guard technicianScoped else { return nil }
            return .remoteParentMissing(workOrderId: workOrderId)
        }

        guard technicianScoped else { return nil }

        guard let authUID else {
            return .technicianNotAssigned(workOrderId: workOrderId)
        }
        if remoteOrder?.assignedTechnicianId.rawValue != authUID {
            return .technicianNotAssigned(workOrderId: workOrderId)
        }

        if remoteOrder?.status == .completed, !allowsWriteOnCompletedParent(operation) {
            return .remoteParentCompleted(workOrderId: workOrderId)
        }

        return nil
    }

    /// Assignment notification create must wait until Firestore reflects
    /// `assignedTechnicianId == recipientUserId` — rules enforce that
    /// invariant and reject early writes after pruned-dependency inference.
    static func shouldHoldAssignmentNotification(
        operation: SyncOperation,
        local: SyncEntityRepositories,
        remote: SyncEntityRepositories
    ) async throws -> Bool {
        guard operation.entityType == .notification,
              operation.operationType == .create else {
            return false
        }
        guard let notification = try await fetchNotification(
            operation: operation,
            local: local
        ) else {
            return true
        }
        guard notification.type == NotificationType.workOrderAssigned,
              let workOrderId = notification.relatedWorkOrderId else {
            return false
        }
        guard let remoteOrder = try await fetchRemoteWorkOrder(
            id: workOrderId,
            remote: remote
        ) else {
            return true
        }
        return remoteOrder.assignedTechnicianId != notification.recipientUserId
    }

    static func parentWorkOrderId(for operation: SyncOperation) -> String? {
        if operation.entityType == .workOrder {
            return operation.entityId
        }
        if SyncPolicy.requiresWorkOrderPayloadReference(operation.entityType),
           let reference = operation.payloadReference?.trimmingCharacters(in: .whitespacesAndNewlines),
           !reference.isEmpty {
            return reference
        }
        return nil
    }

    private static func fetchRemoteWorkOrder(
        id: WorkOrderID,
        remote: SyncEntityRepositories
    ) async throws -> WorkOrder? {
        do {
            return try await remote.workOrders.fetch(id: id)
        } catch let error as DomainError {
            if case .notFound = error { return nil }
            throw error
        }
    }

    private static func fetchNotification(
        operation: SyncOperation,
        local: SyncEntityRepositories
    ) async throws -> AppNotification? {
        let raw = operation.payloadReference?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !raw.isEmpty else { return nil }
        let items = try await local.notifications.list(
            for: UserID(raw),
            unreadOnly: false
        )
        return items.first(where: { $0.id.rawValue == operation.entityId })
    }

    private static func isTechnicianScoped(
        _ operation: SyncOperation,
        local: SyncEntityRepositories
    ) async throws -> Bool {
        switch operation.entityType {
        case .workOrderNote, .workOrderPhoto, .workOrderLocation, .signature:
            return true
        case .workOrderStatusHistory, .workOrder:
            guard let actorUID = try await SyncOperationActorResolver.resolve(
                operation: operation,
                local: local
            ) else {
                return operation.entityType != .workOrderStatusHistory
            }
            guard let user = try? await local.users.fetch(id: UserID(actorUID)) else {
                return true
            }
            return user.role == .technician
        default:
            return false
        }
    }

    private static func allowsWriteOnCompletedParent(_ operation: SyncOperation) -> Bool {
        switch operation.entityType {
        case .workOrderStatusHistory:
            return true
        case .workOrder:
            return operation.operationType == .update
        default:
            return false
        }
    }
}
