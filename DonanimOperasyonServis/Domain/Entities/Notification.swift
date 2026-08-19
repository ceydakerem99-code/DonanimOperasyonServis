import Foundation

/// A single user-facing notification item. Notifications are
/// per-recipient (`recipientUserId`) and may optionally reference an
/// operational resource (`relatedWorkOrderId` /
/// `relatedEditRequestId`) so the UI can deep-link into it.
struct AppNotification: Hashable, Sendable, Identifiable, Codable {
    let id: NotificationID
    let recipientUserId: UserID
    let type: NotificationType
    var title: String
    var body: String
    var relatedWorkOrderId: WorkOrderID?
    var relatedEditRequestId: EditRequestID?
    var isRead: Bool
    let createdAt: Date

    init(
        id: NotificationID,
        recipientUserId: UserID,
        type: NotificationType,
        title: String,
        body: String,
        relatedWorkOrderId: WorkOrderID? = nil,
        relatedEditRequestId: EditRequestID? = nil,
        isRead: Bool = false,
        createdAt: Date
    ) {
        self.id = id
        self.recipientUserId = recipientUserId
        self.type = type
        self.title = title
        self.body = body
        self.relatedWorkOrderId = relatedWorkOrderId
        self.relatedEditRequestId = relatedEditRequestId
        self.isRead = isRead
        self.createdAt = createdAt
    }
}

extension AppNotification {
    /// Convenience access to the notification's category via its
    /// `type`.
    var category: NotificationCategory { type.category }
}
