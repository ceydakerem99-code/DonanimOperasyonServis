import Foundation

/// Shared Domain-entity load / apply used by reconciliation and
/// conflict resolution. Callers pass repository bundles — never
/// SwiftData `ModelContext` or Firebase types.
enum SyncEntityRecordBridge {

    static func load(
        entityType: SyncEntityType,
        entityId: String,
        parentId: String?,
        from repos: SyncEntityRepositories,
        missingParentReason: String = "sync.payloadReferenceMissing"
    ) async throws -> ReconciledRecord? {
        do {
            return try await loadPresent(
                entityType: entityType,
                entityId: entityId,
                parentId: parentId,
                from: repos,
                missingParentReason: missingParentReason
            )
        } catch let error as DomainError {
            if case .notFound = error { return nil }
            throw error
        }
    }

    static func apply(
        _ record: ReconciledRecord,
        to local: SyncEntityRepositories
    ) async throws {
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

    // MARK: - Present

    static func loadPresent(
        entityType: SyncEntityType,
        entityId: String,
        parentId: String?,
        from repos: SyncEntityRepositories,
        missingParentReason: String = "sync.payloadReferenceMissing"
    ) async throws -> ReconciledRecord {
        switch entityType {
        case .user:
            return .user(try await repos.users.fetch(id: UserID(entityId)))
        case .customer:
            return .customer(try await repos.customers.fetch(id: CustomerID(entityId)))
        case .workOrder:
            return .workOrder(try await repos.workOrders.fetch(id: WorkOrderID(entityId)))
        case .editRequest:
            return .editRequest(try await repos.editRequests.fetch(id: EditRequestID(entityId)))
        case .workOrderNote:
            return .workOrderNote(
                try await requireChild(
                    try await repos.notes.list(for: parentWorkOrderId(parentId, reason: missingParentReason)),
                    id: entityId,
                    entity: "WorkOrderNote",
                    key: \.id
                )
            )
        case .workOrderPhoto:
            return .workOrderPhoto(
                try await requireChild(
                    try await repos.photos.list(for: parentWorkOrderId(parentId, reason: missingParentReason)),
                    id: entityId,
                    entity: "WorkOrderPhoto",
                    key: \.id
                )
            )
        case .workOrderLocation:
            return .workOrderLocation(
                try await requireChild(
                    try await repos.locations.list(for: parentWorkOrderId(parentId, reason: missingParentReason)),
                    id: entityId,
                    entity: "WorkOrderLocation",
                    key: \.id
                )
            )
        case .workOrderStatusHistory:
            return .workOrderStatusHistory(
                try await requireChild(
                    try await repos.statusHistory.list(for: parentWorkOrderId(parentId, reason: missingParentReason)),
                    id: entityId,
                    entity: "WorkOrderStatusHistory",
                    key: \.id
                )
            )
        case .signature:
            return .signature(
                try await requireChild(
                    try await repos.signatures.list(for: parentWorkOrderId(parentId, reason: missingParentReason)),
                    id: entityId,
                    entity: "Signature",
                    key: \.id
                )
            )
        case .notification:
            let parent = try requireParent(parentId, reason: missingParentReason)
            let items = try await repos.notifications.list(for: UserID(parent), unreadOnly: false)
            guard let found = items.first(where: { $0.id.rawValue == entityId }) else {
                throw DomainError.notFound(entity: "AppNotification", id: entityId)
            }
            return .notification(found)
        }
    }

    private static func parentWorkOrderId(_ parentId: String?, reason: String) throws -> WorkOrderID {
        WorkOrderID(try requireParent(parentId, reason: reason))
    }

    private static func requireParent(_ parentId: String?, reason: String) throws -> String {
        let raw = parentId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !raw.isEmpty else { throw DomainError.invalidData(reason: reason) }
        return raw
    }

    private static func requireChild<T>(
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
}
