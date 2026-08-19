import Foundation

/// Firestore DTO for the `workOrderStatusHistory` collection.
///
/// From the Domain's perspective these rows are append-only. From
/// Firestore's perspective they are individually addressable
/// documents keyed by their `id`.
struct FirestoreWorkOrderStatusHistoryDTO: Codable, Hashable, Sendable {
    let id: String
    let workOrderId: String
    let fromStatus: String?
    let toStatus: String
    let pauseReason: String?
    let actorUserId: String
    let occurredAt: Date
}

extension FirestoreWorkOrderStatusHistoryDTO {

    init(domain: WorkOrderStatusHistory) {
        self.id = domain.id
        self.workOrderId = domain.workOrderId.rawValue
        self.fromStatus = domain.fromStatus?.rawValue
        self.toStatus = domain.toStatus.rawValue
        self.pauseReason = domain.pauseReason?.rawValue
        self.actorUserId = domain.actorUserId.rawValue
        self.occurredAt = domain.occurredAt
    }

    func toDomain() -> WorkOrderStatusHistory? {
        guard let resolvedToStatus = WorkOrderStatus(rawValue: toStatus) else { return nil }

        let resolvedFromStatus: WorkOrderStatus?
        if let raw = fromStatus {
            guard let decoded = WorkOrderStatus(rawValue: raw) else { return nil }
            resolvedFromStatus = decoded
        } else {
            resolvedFromStatus = nil
        }

        let resolvedPauseReason: PauseReason?
        if let raw = pauseReason {
            guard let decoded = PauseReason(rawValue: raw) else { return nil }
            resolvedPauseReason = decoded
        } else {
            resolvedPauseReason = nil
        }

        return WorkOrderStatusHistory(
            id: id,
            workOrderId: WorkOrderID(workOrderId),
            fromStatus: resolvedFromStatus,
            toStatus: resolvedToStatus,
            pauseReason: resolvedPauseReason,
            actorUserId: UserID(actorUserId),
            occurredAt: occurredAt
        )
    }
}
