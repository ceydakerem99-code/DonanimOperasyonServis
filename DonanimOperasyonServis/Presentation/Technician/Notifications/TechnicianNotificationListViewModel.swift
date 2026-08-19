import Foundation
import Observation

struct TechnicianNotificationRow: Identifiable, Equatable, Sendable {
    let id: NotificationID
    let title: String
    let body: String
    let createdAt: Date
    let isRead: Bool
}

@Observable
@MainActor
final class TechnicianNotificationListViewModel {
    enum Phase: Equatable {
        case loading
        case loaded
        case empty
        case error(String)
    }

    private(set) var phase: Phase = .loading
    private(set) var notifications: [TechnicianNotificationRow] = []

    private let actor: User
    private let dependencies: TechnicianDependencies

    init(actor: User, dependencies: TechnicianDependencies) {
        self.actor = actor
        self.dependencies = dependencies
    }

    func load() async {
        phase = .loading
        do {
            let items = try await dependencies.notificationRepository.list(for: actor.id, unreadOnly: false)
            notifications = items.sorted { $0.createdAt > $1.createdAt }.map {
                TechnicianNotificationRow(
                    id: $0.id,
                    title: $0.title,
                    body: $0.body,
                    createdAt: $0.createdAt,
                    isRead: $0.isRead
                )
            }
            phase = notifications.isEmpty ? .empty : .loaded
        } catch is CancellationError {
            return
        } catch let error as DomainError {
            phase = .error(error.technicianMessage)
        } catch {
            phase = .error("Bildirimler yüklenemedi.")
        }
    }
}

#if DEBUG
extension TechnicianNotificationListViewModel {
    static func previewLoaded() -> TechnicianNotificationListViewModel {
        let vm = TechnicianNotificationListViewModel(
            actor: TechnicianPreviewData.technician,
            dependencies: DIContainer.mock().makeTechnicianDependencies()
        )
        vm.phase = .loaded
        vm.notifications = TechnicianPreviewData.sampleNotifications.map {
            TechnicianNotificationRow(
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
