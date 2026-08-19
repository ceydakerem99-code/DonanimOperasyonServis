import Foundation

/// SwiftData-backed implementation of `NotificationRepository`.
struct SwiftDataNotificationRepository: NotificationRepository {

    let store: LocalPersistence

    init(store: LocalPersistence) {
        self.store = store
    }

    func list(for recipientId: UserID, unreadOnly: Bool) async throws -> [AppNotification] {
        try await store.listNotifications(
            recipientUserId: recipientId.rawValue,
            unreadOnly: unreadOnly
        )
    }

    func save(_ notification: AppNotification) async throws {
        try await store.upsertNotification(notification)
    }

    func markAsRead(id: NotificationID) async throws {
        try await store.markNotificationAsRead(id: id.rawValue)
    }

    func delete(id: NotificationID) async throws {
        try await store.deleteNotification(id: id.rawValue)
    }
}
