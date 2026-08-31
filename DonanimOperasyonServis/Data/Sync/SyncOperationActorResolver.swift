import Foundation

/// Resolves the Firebase Auth UID that must be active when applying
/// a queue row remotely. Prefers the persisted `actorUserId`; falls
/// back to entity payload fields for legacy rows.
enum SyncOperationActorResolver {

    static func resolve(
        operation: SyncOperation,
        local: SyncEntityRepositories
    ) async throws -> String? {
        if let stored = operation.actorUserId?.trimmingCharacters(in: .whitespacesAndNewlines),
           !stored.isEmpty {
            return stored
        }
        return try await inferFromEntity(operation: operation, local: local)
    }

    private static func inferFromEntity(
        operation: SyncOperation,
        local: SyncEntityRepositories
    ) async throws -> String? {
        switch operation.entityType {
        case .user:
            return operation.entityId
        case .customer:
            return nil
        case .workOrder:
            guard let order = try? await local.workOrders.fetch(id: WorkOrderID(operation.entityId)) else {
                return nil
            }
            switch operation.operationType {
            case .create:
                return order.createdByUserId.rawValue
            case .update, .delete:
                return order.assignedTechnicianId.rawValue
            }
        case .workOrderNote:
            guard let parentId = operation.payloadReference else { return nil }
            let notes = try await local.notes.list(for: WorkOrderID(parentId))
            return notes.first(where: { $0.id == operation.entityId })?.authorUserId.rawValue
        case .workOrderPhoto:
            guard let parentId = operation.payloadReference else { return nil }
            let photos = try await local.photos.list(for: WorkOrderID(parentId))
            return photos.first(where: { $0.id == operation.entityId })?.capturedByUserId.rawValue
        case .workOrderLocation:
            guard let parentId = operation.payloadReference else { return nil }
            let locations = try await local.locations.list(for: WorkOrderID(parentId))
            return locations.first(where: { $0.id == operation.entityId })?.capturedByUserId.rawValue
        case .workOrderStatusHistory:
            guard let parentId = operation.payloadReference else { return nil }
            let rows = try await local.statusHistory.list(for: WorkOrderID(parentId))
            return rows.first(where: { $0.id == operation.entityId })?.actorUserId.rawValue
        case .signature:
            guard let parentId = operation.payloadReference else { return nil }
            let rows = try await local.signatures.list(for: WorkOrderID(parentId))
            return rows.first(where: { $0.id == operation.entityId })?.capturedByUserId.rawValue
        case .editRequest:
            guard let request = try? await local.editRequests.fetch(id: EditRequestID(operation.entityId)) else {
                return nil
            }
            switch operation.operationType {
            case .create:
                return request.requestedByUserId.rawValue
            case .update:
                return request.reviewedByUserId?.rawValue ?? request.requestedByUserId.rawValue
            case .delete:
                return request.requestedByUserId.rawValue
            }
        case .notification:
            return operation.payloadReference
        case .customerSatisfaction:
            guard let satisfaction = try? await local.customerSatisfactions.fetch(
                id: CustomerSatisfactionID(operation.entityId)
            ) else {
                return nil
            }
            switch operation.operationType {
            case .create:
                if let order = try? await local.workOrders.fetch(id: satisfaction.workOrderId) {
                    return order.createdByUserId.rawValue
                }
                return nil
            case .update, .delete:
                return nil
            }
        }
    }
}
