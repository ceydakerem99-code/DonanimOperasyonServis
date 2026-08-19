import Foundation

/// Firestore DTO for the `notifications` collection.
struct FirestoreNotificationDTO: Codable, Hashable, Sendable {
    let id: String
    let recipientUserId: String
    let type: String
    let title: String
    let body: String
    let relatedWorkOrderId: String?
    let relatedEditRequestId: String?
    let isRead: Bool
    let createdAt: Date
}

extension FirestoreNotificationDTO {

    init(domain: AppNotification) {
        self.id = domain.id.rawValue
        self.recipientUserId = domain.recipientUserId.rawValue
        self.type = domain.type.rawValue
        self.title = domain.title
        self.body = domain.body
        self.relatedWorkOrderId = domain.relatedWorkOrderId?.rawValue
        self.relatedEditRequestId = domain.relatedEditRequestId?.rawValue
        self.isRead = domain.isRead
        self.createdAt = domain.createdAt
    }

    func toDomain() -> AppNotification? {
        guard let resolvedType = NotificationType(rawValue: type) else { return nil }
        return AppNotification(
            id: NotificationID(id),
            recipientUserId: UserID(recipientUserId),
            type: resolvedType,
            title: title,
            body: body,
            relatedWorkOrderId: relatedWorkOrderId.map(WorkOrderID.init),
            relatedEditRequestId: relatedEditRequestId.map(EditRequestID.init),
            isRead: isRead,
            createdAt: createdAt
        )
    }
}
