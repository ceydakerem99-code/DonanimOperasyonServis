import Foundation
import Observation

struct OperatorNotificationRow: Identifiable, Equatable, Sendable {
    let id: NotificationID
    let title: String
    let body: String
    let createdAt: Date
    let isRead: Bool
    let type: NotificationType
    let relatedWorkOrderId: WorkOrderID?
    let relatedEditRequestId: EditRequestID?
}

enum OperatorNotificationOpenOutcome: Equatable, Sendable {
    case workOrderDetail(WorkOrderID)
    case editRequestDetail(EditRequestID)
    case markedReadOnly
    case missingRelated
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
    private(set) var fallbackMessage: String?

    private let actor: User
    private let dependencies: OperatorDependencies
    private let asyncLoad = AsyncLoadSession()
    private var items: [AppNotification] = []

    var showsLoadingIndicator: Bool { asyncLoad.showsLoadingIndicator }
    var hasCachedContent: Bool { !notifications.isEmpty }
    var unreadCount: Int { notifications.filter { !$0.isRead }.count }

    init(actor: User, dependencies: OperatorDependencies) {
        self.actor = actor
        self.dependencies = dependencies
    }

    func load() async {
        let context = asyncLoad.start(hadCachedContent: hasCachedContent)
        if !context.hadCachedContentAtStart { phase = .loading }
        defer { asyncLoad.finish(generation: context.generation) }
        let generation = context.generation
        do {
            let prefs = try await dependencies.userRepository.fetch(id: actor.id).notificationPreferences
            let fetched = try await dependencies.notificationRepository.list(
                for: actor.id,
                unreadOnly: false
            )
            guard asyncLoad.isCurrent(generation) else { return }
            apply(items: fetched, preferences: prefs)
            phase = notifications.isEmpty ? .empty : .loaded
        } catch is CancellationError {
            guard asyncLoad.isCurrent(generation) else { return }
            if let settled = asyncLoad.settleCancelledLoad(
                context: context,
                phase: phase,
                loadingPhase: Phase.loading,
                loadedPhase: Phase.loaded,
                emptyPhase: Phase.empty
            ) {
                phase = settled
            }
        } catch let error as DomainError {
            guard asyncLoad.isCurrent(generation) else { return }
            phase = .error(error.operatorMessage)
        } catch {
            guard asyncLoad.isCurrent(generation) else { return }
            phase = .error("Bildirimler yüklenemedi.")
        }
    }

    /// Marks read, then resolves deep-link without entering a loading spinner.
    func open(_ id: NotificationID) async -> OperatorNotificationOpenOutcome {
        fallbackMessage = nil
        guard let item = items.first(where: { $0.id == id }) else {
            fallbackMessage = "İlişkili kayıt bulunamadı."
            return .missingRelated
        }

        try? await dependencies.notificationRepository.markAsRead(id: id)
       _ = try? await TechnicianSyncEnqueue.enqueueUpdate(
            entityType: .notification,
            entityId: id.rawValue,
            queue: dependencies.syncOperationRepository,
            now: Date(),
            actorUserId: actor.id.rawValue,
            payloadReference: actor.id.rawValue
        )
        markLocallyRead(id: id)

        if let workOrderId = item.relatedWorkOrderId {
            do {
                _ = try await dependencies.getWorkOrder.execute(actor: actor, id: workOrderId)
                return .workOrderDetail(workOrderId)
            } catch {
                fallbackMessage = "İlişkili kayıt bulunamadı."
                return .missingRelated
            }
        }

        if let editRequestId = item.relatedEditRequestId {
            do {
                _ = try await dependencies.editRequestRepository.fetch(id: editRequestId)
                return .editRequestDetail(editRequestId)
            } catch {
                fallbackMessage = "İlişkili kayıt bulunamadı."
                return .missingRelated
            }
        }

        return .markedReadOnly
    }

    func clearFallbackMessage() {
        fallbackMessage = nil
    }

    private func markLocallyRead(id: NotificationID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].isRead = true
        apply(items: items, preferences: cachedPreferences)
        if case .error = phase {
            return
        }
        phase = notifications.isEmpty ? .empty : .loaded
    }

    private var cachedPreferences: NotificationPreferences = .default

    private func apply(items: [AppNotification], preferences: NotificationPreferences) {
        cachedPreferences = preferences
        let visible = items.filter { preferences.allowsDisplay(of: $0.type) }
        self.items = visible.sorted { $0.createdAt > $1.createdAt }
        notifications = self.items.map(Self.mapRow)
    }

    private static func mapRow(_ notification: AppNotification) -> OperatorNotificationRow {
        OperatorNotificationRow(
            id: notification.id,
            title: notification.title,
            body: notification.body,
            createdAt: notification.createdAt,
            isRead: notification.isRead,
            type: notification.type,
            relatedWorkOrderId: notification.relatedWorkOrderId,
            relatedEditRequestId: notification.relatedEditRequestId
        )
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
        vm.apply(items: OperatorPreviewData.sampleNotifications, preferences: .default)
        return vm
    }
}
#endif
