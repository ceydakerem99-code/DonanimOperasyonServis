import Foundation
import SwiftData

/// SwiftData persistence model for `AppNotification`.
@Model
final class NotificationModel {

    @Attribute(.unique) var id: String

    var recipientUserId: String
    var typeRaw: String
    var title: String
    var body: String
    var relatedWorkOrderId: String?
    var relatedEditRequestId: String?
    var isRead: Bool
    var createdAt: Date

    init(
        id: String,
        recipientUserId: String,
        typeRaw: String,
        title: String,
        body: String,
        relatedWorkOrderId: String?,
        relatedEditRequestId: String?,
        isRead: Bool,
        createdAt: Date
    ) {
        self.id = id
        self.recipientUserId = recipientUserId
        self.typeRaw = typeRaw
        self.title = title
        self.body = body
        self.relatedWorkOrderId = relatedWorkOrderId
        self.relatedEditRequestId = relatedEditRequestId
        self.isRead = isRead
        self.createdAt = createdAt
    }
}

extension NotificationModel {

    convenience init(domain: AppNotification) {
        self.init(
            id: domain.id.rawValue,
            recipientUserId: domain.recipientUserId.rawValue,
            typeRaw: domain.type.rawValue,
            title: domain.title,
            body: domain.body,
            relatedWorkOrderId: domain.relatedWorkOrderId?.rawValue,
            relatedEditRequestId: domain.relatedEditRequestId?.rawValue,
            isRead: domain.isRead,
            createdAt: domain.createdAt
        )
    }

    func apply(domain: AppNotification) {
        self.recipientUserId = domain.recipientUserId.rawValue
        self.typeRaw = domain.type.rawValue
        self.title = domain.title
        self.body = domain.body
        self.relatedWorkOrderId = domain.relatedWorkOrderId?.rawValue
        self.relatedEditRequestId = domain.relatedEditRequestId?.rawValue
        self.isRead = domain.isRead
        self.createdAt = domain.createdAt
    }

    func toDomain() -> AppNotification? {
        guard let type = NotificationType(rawValue: typeRaw) else { return nil }
        return AppNotification(
            id: NotificationID(id),
            recipientUserId: UserID(recipientUserId),
            type: type,
            title: title,
            body: body,
            relatedWorkOrderId: relatedWorkOrderId.map(WorkOrderID.init),
            relatedEditRequestId: relatedEditRequestId.map(EditRequestID.init),
            isRead: isRead,
            createdAt: createdAt
        )
    }
}
