import Foundation
import Observation

struct OperatorNotificationRow: Identifiable, Equatable, Sendable {
    let id: NotificationID
    let title: String
    let body: String
    let createdAt: Date
    let isRead: Bool
}

@Observable
@MainActor
final class OperatorNotificationListViewModel {
    enum Phase: Equatable {
        case loading
        case loaded
        case empty
        case error(String)
    }

    private(set) var phase: Phase = .loading
    private(set) var notifications: [OperatorNotificationRow] = []

    private let actor: User
    private let dependencies: OperatorDependencies

    init(actor: User, dependencies: OperatorDependencies) {
        self.actor = actor
        self.dependencies = dependencies
    }

    func load() async {
        phase = .loading
        do {
            let items = try await dependencies.notificationRepository.list(
                for: actor.id,
                unreadOnly: false
            )
            notifications = items
                .sorted { $0.createdAt > $1.createdAt }
                .map {
                    OperatorNotificationRow(
                        id: $0.id,
                        title: $0.title,
                        body: $0.body,
                        createdAt: $0.createdAt,
                        isRead: $0.isRead
                    )
                }
            phase = notifications.isEmpty ? .empty : .loaded
        } catch let error as DomainError {
            phase = .error(error.operatorMessage)
        } catch {
            phase = .error("Bildirimler yüklenemedi.")
        }
    }

    func markRead(_ id: NotificationID) async {
        try? await dependencies.notificationRepository.markAsRead(id: id)
        await load()
    }
}

#if DEBUG
extension OperatorNotificationListViewModel {
    static func previewLoaded() -> OperatorNotificationListViewModel {
        let vm = OperatorNotificationListViewModel(
            actor: OperatorPreviewData.operatorUser,
            dependencies: DIContainer.mock().makeOperatorDependencies()
        )
        vm.phase = .loaded
        vm.notifications = OperatorPreviewData.sampleNotifications.map {
            OperatorNotificationRow(
                id: $0.id,
                title: $0.title,
                body: $0.body,
                createdAt: $0.createdAt,
                isRead: $0.isRead
            )
        }
        return vm
    }
}
#endif
