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
/// Photo / signature rows with a `pending://` `storagePath` upload
/// bytes from `TechnicianLocalMediaStore` via `storage` **before**
/// remote metadata is written. Local SoT is updated to the real
/// Storage path only after a successful upload.
enum SyncRemoteDispatcher {

    static func apply(
        operation: SyncOperation,
        local: SyncEntityRepositories,
        remote: SyncEntityRepositories,
        storage: (any FirebaseStorageDataSource)? = nil
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
            try await dispatchPhoto(operation, local: local, remote: remote, storage: storage)
        case .workOrderLocation:
            try await dispatchLocation(operation, local: local, remote: remote)
        case .workOrderStatusHistory:
            try await dispatchStatusHistory(operation, local: local, remote: remote)
        case .signature:
            try await dispatchSignature(operation, local: local, remote: remote, storage: storage)
        case .editRequest:
            try await dispatchEditRequest(operation, local: local, remote: remote)
        case .notification:
            try await dispatchNotification(operation, local: local, remote: remote)
        case .customerSatisfaction:
            try await dispatchCustomerSatisfaction(operation, local: local, remote: remote)
        }
    }

    // MARK: - User / Customer / WorkOrder / EditRequest / Notification / CustomerSatisfaction

    private static func dispatchUser(
        _ operation: SyncOperation,
        local: SyncEntityRepositories,
        remote: SyncEntityRepositories
    ) async throws {
        let id = UserID(operation.entityId)
        switch operation.operationType {
        case .create:
            let user = try await local.users.fetch(id: id)
            try await remote.users.save(user)
        case .update:
            let user = try await local.users.fetch(id: id)
            if isSelfServiceUserUpdate(operation) {
                try await remote.users.updateSelfServiceProfile(user)
            } else {
                try await remote.users.save(user)
            }
        case .delete:
            try await deleteIgnoringRemoteNotFound {
                try await remote.users.delete(id: id)
            }
        }
    }

    /// Self-service profile sync (notification prefs) must patch only
    /// rule-allowed fields. Admin updates another user when
    /// `actorUserId != entityId`.
    private static func isSelfServiceUserUpdate(_ operation: SyncOperation) -> Bool {
        guard operation.operationType == .update else { return false }
        if let actor = operation.actorUserId?.trimmingCharacters(in: .whitespacesAndNewlines),
           !actor.isEmpty {
            return actor == operation.entityId
        }
        // Legacy rows: user entity id is the Auth UID for self-updates.
        return true
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

    private static func dispatchCustomerSatisfaction(
        _ operation: SyncOperation,
        local: SyncEntityRepositories,
        remote: SyncEntityRepositories
    ) async throws {
        let id = CustomerSatisfactionID(operation.entityId)
        switch operation.operationType {
        case .create, .update:
            let satisfaction = try await local.customerSatisfactions.fetch(id: id)
            try await remote.customerSatisfactions.save(satisfaction)
        case .delete:
            throw DomainError.invalidData(reason: "sync.unsupportedOperation.customerSatisfaction.delete")
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
            let note = try requireChild(
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
        remote: SyncEntityRepositories,
        storage: (any FirebaseStorageDataSource)?
    ) async throws {
        let workOrderId = try requireParentWorkOrderId(operation)
        switch operation.operationType {
        case .create, .update:
            let photo = try requireChild(
                try await local.photos.list(for: workOrderId),
                entityId: operation.entityId,
                entity: "WorkOrderPhoto",
                id: \.id
            )
            let ready = try await resolvePhotoStorage(
                photo,
                local: local,
                storage: storage
            )
            try await remote.photos.save(ready)
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
            let location = try requireChild(
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
            let entry = try requireChild(
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
        remote: SyncEntityRepositories,
        storage: (any FirebaseStorageDataSource)?
    ) async throws {
        let workOrderId = try requireParentWorkOrderId(operation)
        switch operation.operationType {
        case .create, .update:
            let signature = try requireChild(
                try await local.signatures.list(for: workOrderId),
                entityId: operation.entityId,
                entity: "Signature",
                id: \.id
            )
            let ready = try await resolveSignatureStorage(
                signature,
                local: local,
                storage: storage
            )
            try await remote.signatures.save(ready)
        case .delete:
            try await deleteIgnoringRemoteNotFound {
                try await remote.signatures.delete(id: operation.entityId, for: workOrderId)
            }
        }
    }

    // MARK: - Deferred Storage upload

    private static func resolvePhotoStorage(
        _ photo: WorkOrderPhoto,
        local: SyncEntityRepositories,
        storage: (any FirebaseStorageDataSource)?
    ) async throws -> WorkOrderPhoto {
        guard PendingStoragePath.isPending(photo.storagePath) else {
            return photo
        }
        guard let storage else {
            throw DomainError.infrastructure(underlying: "firebase.storageError.notConfigured")
        }
        guard let data = TechnicianLocalMediaStore.loadPhoto(
            workOrderId: photo.workOrderId,
            photoId: photo.id
        ), !data.isEmpty else {
            throw DomainError.infrastructure(underlying: "firebase.storageError.localMediaMissing")
        }
        let path = FirebaseStoragePath.photo(
            workOrderId: photo.workOrderId,
            photoId: photo.id
        )
        let uploadedPath = try await upload(data: data, to: path, storage: storage)
        var updated = photo
        updated.storagePath = uploadedPath
        try await local.photos.save(updated)
        #if DEBUG
        AppLogger.sync.info("SYNC PHOTO upload result=success")
        #endif
        return updated
    }

    private static func resolveSignatureStorage(
        _ signature: Signature,
        local: SyncEntityRepositories,
        storage: (any FirebaseStorageDataSource)?
    ) async throws -> Signature {
        guard PendingStoragePath.isPending(signature.storagePath) else {
            return signature
        }
        guard let storage else {
            throw DomainError.infrastructure(underlying: "firebase.storageError.notConfigured")
        }
        guard let data = TechnicianLocalMediaStore.loadSignature(
            workOrderId: signature.workOrderId,
            signatureId: signature.id
        ), !data.isEmpty else {
            throw DomainError.infrastructure(underlying: "firebase.storageError.localMediaMissing")
        }
        let path = FirebaseStoragePath.signature(
            workOrderId: signature.workOrderId,
            signatureId: signature.id
        )
        let uploadedPath = try await upload(data: data, to: path, storage: storage)
        var updated = signature
        updated.storagePath = uploadedPath
        try await local.signatures.save(updated)
        #if DEBUG
        AppLogger.sync.info("SYNC SIGNATURE upload result=success")
        #endif
        return updated
    }

    private static func upload(
        data: Data,
        to path: FirebaseStoragePath,
        storage: any FirebaseStorageDataSource
    ) async throws -> String {
        do {
            return try await storage.upload(data: data, to: path)
        } catch let error as DomainError {
            throw error
        } catch {
            throw DomainError.infrastructure(underlying: "firebase.storageError")
        }
    }

    // MARK: - Completed work order

    /// Blocks sync that would **reopen** a remotely completed order.
    /// Offline completion (local `.completed`, remote missing or still
    /// open) must be allowed to push — otherwise completed GPS ordering
    /// cannot land a consistent remote parent status.
    private static func rejectCompletedWorkOrderConflict(
        local: WorkOrder,
        remote: WorkOrder?,
        operation: SyncOperation
    ) throws {
        guard let remote else { return }
        if remote.status == .completed, local.status != .completed {
            throw SyncConflictDetected(
                localVersion: operation.localVersion,
                remoteVersion: operation.remoteVersion,
                localReference: operation.payloadReference ?? local.id.rawValue,
                remoteReference: remote.id.rawValue
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
