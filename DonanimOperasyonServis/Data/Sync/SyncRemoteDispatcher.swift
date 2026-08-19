import Foundation

/// Central `(entityType, operationType)` → remote repository switch.
///
/// One table, one file. Child entities (notes, photos, locations,
/// status history, signatures) are loaded from the **local**
/// repository by listing the parent identified in
/// `payloadReference` (the work-order id). Notifications use
/// `payloadReference` as the recipient user id. Parent entities
/// (user, customer, workOrder, editRequest) load by `entityId`.
///
/// Does not write back to local business repositories.
enum SyncRemoteDispatcher {

    static func apply(
        operation: SyncOperation,
        local: SyncEntityRepositories,
        remote: SyncEntityRepositories
    ) async throws {
        switch operation.entityType {
        case .user:
            try await dispatchUser(operation, local: local, remote: remote)
        case .customer:
            try await dispatchCustomer(operation, local: local, remote: remote)
        case .workOrder:
            try await dispatchWorkOrder(operation, local: local, remote: remote)
        case .workOrderNote:
            try await dispatchNote(operation, local: local, remote: remote)
        case .workOrderPhoto:
            try await dispatchPhoto(operation, local: local, remote: remote)
        case .workOrderLocation:
            try await dispatchLocation(operation, local: local, remote: remote)
        case .workOrderStatusHistory:
            try await dispatchStatusHistory(operation, local: local, remote: remote)
        case .signature:
            try await dispatchSignature(operation, local: local, remote: remote)
        case .editRequest:
            try await dispatchEditRequest(operation, local: local, remote: remote)
        case .notification:
            try await dispatchNotification(operation, local: local, remote: remote)
        }
    }

    // MARK: - User / Customer / WorkOrder / EditRequest / Notification

    private static func dispatchUser(
        _ operation: SyncOperation,
        local: SyncEntityRepositories,
        remote: SyncEntityRepositories
    ) async throws {
        let id = UserID(operation.entityId)
        switch operation.operationType {
        case .create, .update:
            let user = try await local.users.fetch(id: id)
            try await remote.users.save(user)
        case .delete:
            try await deleteIgnoringRemoteNotFound {
                try await remote.users.delete(id: id)
            }
        }
    }

    private static func dispatchCustomer(
        _ operation: SyncOperation,
        local: SyncEntityRepositories,
        remote: SyncEntityRepositories
    ) async throws {
        let id = CustomerID(operation.entityId)
        switch operation.operationType {
        case .create, .update:
            let customer = try await local.customers.fetch(id: id)
            try await remote.customers.save(customer)
        case .delete:
            try await deleteIgnoringRemoteNotFound {
                try await remote.customers.delete(id: id)
            }
        }
    }

    private static func dispatchWorkOrder(
        _ operation: SyncOperation,
        local: SyncEntityRepositories,
        remote: SyncEntityRepositories
    ) async throws {
        let id = WorkOrderID(operation.entityId)
        switch operation.operationType {
        case .create:
            let order = try await local.workOrders.fetch(id: id)
            try await remote.workOrders.save(order)
        case .update:
            let localOrder = try await local.workOrders.fetch(id: id)
            try await rejectCompletedWorkOrderConflict(
                local: localOrder,
                remote: try await fetchRemoteWorkOrderIfPresent(id: id, remote: remote),
                operation: operation
            )
            try await remote.workOrders.save(localOrder)
        case .delete:
            if let localOrder = try await fetchLocalWorkOrderIfPresent(id: id, local: local) {
                try await rejectCompletedWorkOrderConflict(
                    local: localOrder,
                    remote: try await fetchRemoteWorkOrderIfPresent(id: id, remote: remote),
                    operation: operation
                )
            }
            try await deleteIgnoringRemoteNotFound {
                try await remote.workOrders.delete(id: id)
            }
        }
    }

    private static func dispatchEditRequest(
        _ operation: SyncOperation,
        local: SyncEntityRepositories,
        remote: SyncEntityRepositories
    ) async throws {
        let id = EditRequestID(operation.entityId)
        switch operation.operationType {
        case .create, .update:
            let request = try await local.editRequests.fetch(id: id)
            try await remote.editRequests.save(request)
        case .delete:
            throw DomainError.invalidData(reason: "sync.unsupportedOperation.editRequest.delete")
        }
    }

    private static func dispatchNotification(
        _ operation: SyncOperation,
        local: SyncEntityRepositories,
        remote: SyncEntityRepositories
    ) async throws {
        switch operation.operationType {
        case .create, .update:
            let notification = try await requireNotification(operation, local: local)
            try await remote.notifications.save(notification)
        case .delete:
            throw DomainError.invalidData(reason: "sync.unsupportedOperation.notification.delete")
        }
    }

    // MARK: - Work-order children

    private static func dispatchNote(
        _ operation: SyncOperation,
        local: SyncEntityRepositories,
        remote: SyncEntityRepositories
    ) async throws {
        let workOrderId = try requireParentWorkOrderId(operation)
        switch operation.operationType {
        case .create, .update:
            let note = try await requireChild(
                try await local.notes.list(for: workOrderId),
                entityId: operation.entityId,
                entity: "WorkOrderNote",
                id: \.id
            )
            try await remote.notes.save(note)
        case .delete:
            try await deleteIgnoringRemoteNotFound {
                try await remote.notes.delete(id: operation.entityId, for: workOrderId)
            }
        }
    }

    private static func dispatchPhoto(
        _ operation: SyncOperation,
        local: SyncEntityRepositories,
        remote: SyncEntityRepositories
    ) async throws {
        let workOrderId = try requireParentWorkOrderId(operation)
        switch operation.operationType {
        case .create, .update:
            let photo = try await requireChild(
                try await local.photos.list(for: workOrderId),
                entityId: operation.entityId,
                entity: "WorkOrderPhoto",
                id: \.id
            )
            try await remote.photos.save(photo)
        case .delete:
            try await deleteIgnoringRemoteNotFound {
                try await remote.photos.delete(id: operation.entityId, for: workOrderId)
            }
        }
    }

    private static func dispatchLocation(
        _ operation: SyncOperation,
        local: SyncEntityRepositories,
        remote: SyncEntityRepositories
    ) async throws {
        let workOrderId = try requireParentWorkOrderId(operation)
        switch operation.operationType {
        case .create:
            let location = try await requireChild(
                try await local.locations.list(for: workOrderId),
                entityId: operation.entityId,
                entity: "WorkOrderLocation",
                id: \.id
            )
            try await remote.locations.save(location)
        case .update, .delete:
            throw DomainError.invalidData(
                reason: "sync.unsupportedOperation.workOrderLocation.\(operation.operationType.rawValue)"
            )
        }
    }

    private static func dispatchStatusHistory(
        _ operation: SyncOperation,
        local: SyncEntityRepositories,
        remote: SyncEntityRepositories
    ) async throws {
        let workOrderId = try requireParentWorkOrderId(operation)
        switch operation.operationType {
        case .create:
            let entry = try await requireChild(
                try await local.statusHistory.list(for: workOrderId),
                entityId: operation.entityId,
                entity: "WorkOrderStatusHistory",
                id: \.id
            )
            try await remote.statusHistory.append(entry)
        case .update, .delete:
            throw DomainError.invalidData(
                reason: "sync.unsupportedOperation.workOrderStatusHistory.\(operation.operationType.rawValue)"
            )
        }
    }

    private static func dispatchSignature(
        _ operation: SyncOperation,
        local: SyncEntityRepositories,
        remote: SyncEntityRepositories
    ) async throws {
        let workOrderId = try requireParentWorkOrderId(operation)
        switch operation.operationType {
        case .create, .update:
            let signature = try await requireChild(
                try await local.signatures.list(for: workOrderId),
                entityId: operation.entityId,
                entity: "Signature",
                id: \.id
            )
            try await remote.signatures.save(signature)
        case .delete:
            try await deleteIgnoringRemoteNotFound {
                try await remote.signatures.delete(id: operation.entityId, for: workOrderId)
            }
        }
    }

    // MARK: - Completed work order

    private static func rejectCompletedWorkOrderConflict(
        local: WorkOrder,
        remote: WorkOrder?,
        operation: SyncOperation
    ) throws {
        if let remote,
           CompletedWorkOrderSyncRule.isConflict(local: local.status, remote: remote.status) {
            throw SyncConflictDetected(
                localVersion: operation.localVersion,
                remoteVersion: operation.remoteVersion,
                localReference: operation.payloadReference ?? local.id.rawValue,
                remoteReference: remote.id.rawValue
            )
        }
        if local.status == .completed {
            throw SyncConflictDetected(
                localVersion: operation.localVersion,
                remoteVersion: operation.remoteVersion,
                localReference: operation.payloadReference ?? local.id.rawValue,
                remoteReference: remote?.id.rawValue
            )
        }
    }

    private static func fetchRemoteWorkOrderIfPresent(
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

    private static func fetchLocalWorkOrderIfPresent(
        id: WorkOrderID,
        local: SyncEntityRepositories
    ) async throws -> WorkOrder? {
        do {
            return try await local.workOrders.fetch(id: id)
        } catch let error as DomainError {
            if case .notFound = error { return nil }
            throw error
        }
    }

    // MARK: - Lookups

    private static func requireParentWorkOrderId(_ operation: SyncOperation) throws -> WorkOrderID {
        let raw = operation.payloadReference?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !raw.isEmpty else {
            throw DomainError.invalidData(reason: "sync.payloadReferenceMissing")
        }
        return WorkOrderID(raw)
    }

    private static func requireNotification(
        _ operation: SyncOperation,
        local: SyncEntityRepositories
    ) async throws -> AppNotification {
        let raw = operation.payloadReference?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !raw.isEmpty else {
            throw DomainError.invalidData(reason: "sync.payloadReferenceMissing")
        }
        let items = try await local.notifications.list(
            for: UserID(raw),
            unreadOnly: false
        )
        guard let found = items.first(where: { $0.id.rawValue == operation.entityId }) else {
            throw DomainError.notFound(entity: "AppNotification", id: operation.entityId)
        }
        return found
    }

    private static func requireChild<T>(
        _ items: [T],
        entityId: String,
        entity: String,
        id: KeyPath<T, String>
    ) throws -> T {
        guard let found = items.first(where: { $0[keyPath: id] == entityId }) else {
            throw DomainError.notFound(entity: entity, id: entityId)
        }
        return found
    }

    /// Idempotent remote delete: a remote `notFound` means the row
    /// is already gone, which is success for a delete operation.
    private static func deleteIgnoringRemoteNotFound(
        _ body: () async throws -> Void
    ) async throws {
        do {
            try await body()
        } catch let error as DomainError {
            if case .notFound = error { return }
            throw error
        }
    }
}
