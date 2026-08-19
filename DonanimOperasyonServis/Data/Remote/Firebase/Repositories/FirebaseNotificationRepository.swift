import Foundation

/// Firestore-backed implementation of `NotificationRepository`.
/// Persistence only — FCM / APNs / push-token handling is
/// explicitly out of scope for Phase 4.
struct FirebaseNotificationRepository: NotificationRepository {

    let dataSource: any FirestoreDataSource

    init(dataSource: any FirestoreDataSource) {
        self.dataSource = dataSource
    }

    func list(for recipientId: UserID, unreadOnly: Bool) async throws -> [AppNotification] {
        var predicates: [FirestorePredicate] = [
            .equal("recipientUserId", .string(recipientId.rawValue))
        ]
        if unreadOnly {
            predicates.append(.equal("isRead", .bool(false)))
        }
        let dtos = try await dataSource.list(
            FirestoreNotificationDTO.self,
            collection: .notifications,
            predicates: predicates,
            orderBy: [.descending("createdAt")]
        )
        return try dtos.map {
            try FirebaseRepositoryMapper.requireDomain($0, entity: "AppNotification") { $0.toDomain() }
        }
    }

    func save(_ notification: AppNotification) async throws {
        try await dataSource.set(
            FirestoreNotificationDTO(domain: notification),
            collection: .notifications,
            id: notification.id.rawValue
        )
    }

    func markAsRead(id: NotificationID) async throws {
        guard let dto = try await dataSource.fetch(
            FirestoreNotificationDTO.self,
            collection: .notifications,
            id: id.rawValue
        ) else {
            throw DomainError.notFound(entity: "AppNotification", id: id.rawValue)
        }
        let updated = FirestoreNotificationDTO(
            id: dto.id,
            recipientUserId: dto.recipientUserId,
            type: dto.type,
            title: dto.title,
            body: dto.body,
            relatedWorkOrderId: dto.relatedWorkOrderId,
            relatedEditRequestId: dto.relatedEditRequestId,
            isRead: true,
            createdAt: dto.createdAt
        )
        try await dataSource.set(updated, collection: .notifications, id: id.rawValue)
    }

    func delete(id: NotificationID) async throws {
        try await dataSource.delete(collection: .notifications, id: id.rawValue)
    }
}
