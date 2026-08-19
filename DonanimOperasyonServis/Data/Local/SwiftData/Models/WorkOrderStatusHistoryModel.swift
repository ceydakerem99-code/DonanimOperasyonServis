import Foundation
import SwiftData

/// SwiftData persistence model for `WorkOrderStatusHistory`. Rows
/// are append-only from a Domain standpoint.
@Model
final class WorkOrderStatusHistoryModel {

    @Attribute(.unique) var id: String

    var workOrder: WorkOrderModel?
    var workOrderId: String

    var fromStatusRaw: String?
    var toStatusRaw: String
    var pauseReasonRaw: String?
    var actorUserId: String
    var occurredAt: Date

    init(
        id: String,
        workOrderId: String,
        fromStatusRaw: String?,
        toStatusRaw: String,
        pauseReasonRaw: String?,
        actorUserId: String,
        occurredAt: Date
    ) {
        self.id = id
        self.workOrderId = workOrderId
        self.fromStatusRaw = fromStatusRaw
        self.toStatusRaw = toStatusRaw
        self.pauseReasonRaw = pauseReasonRaw
        self.actorUserId = actorUserId
        self.occurredAt = occurredAt
    }
}

extension WorkOrderStatusHistoryModel {

    convenience init(domain: WorkOrderStatusHistory) {
        self.init(
            id: domain.id,
            workOrderId: domain.workOrderId.rawValue,
            fromStatusRaw: domain.fromStatus?.rawValue,
            toStatusRaw: domain.toStatus.rawValue,
            pauseReasonRaw: domain.pauseReason?.rawValue,
            actorUserId: domain.actorUserId.rawValue,
            occurredAt: domain.occurredAt
        )
    }

    func toDomain() -> WorkOrderStatusHistory? {
        guard let toStatus = WorkOrderStatus(rawValue: toStatusRaw) else { return nil }

        let fromStatus: WorkOrderStatus?
        if let raw = fromStatusRaw {
            guard let decoded = WorkOrderStatus(rawValue: raw) else { return nil }
            fromStatus = decoded
        } else {
            fromStatus = nil
        }

        let pauseReason: PauseReason?
        if let raw = pauseReasonRaw {
            guard let decoded = PauseReason(rawValue: raw) else { return nil }
            pauseReason = decoded
        } else {
            pauseReason = nil
        }

        return WorkOrderStatusHistory(
            id: id,
            workOrderId: WorkOrderID(workOrderId),
            fromStatus: fromStatus,
            toStatus: toStatus,
            pauseReason: pauseReason,
            actorUserId: UserID(actorUserId),
            occurredAt: occurredAt
        )
    }
}
