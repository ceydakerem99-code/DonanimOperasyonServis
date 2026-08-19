import Foundation

/// Persistence surface for user-facing notifications.
protocol NotificationRepository: Sendable {
    func list(for recipientId: UserID, unreadOnly: Bool) async throws -> [AppNotification]
    func save(_ notification: AppNotification) async throws
    func markAsRead(id: NotificationID) async throws
    func delete(id: NotificationID) async throws
}
