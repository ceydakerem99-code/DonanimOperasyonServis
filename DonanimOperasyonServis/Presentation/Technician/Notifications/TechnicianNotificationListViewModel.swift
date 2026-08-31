import Foundation
import Observation

struct TechnicianNotificationRow: Identifiable, Equatable, Sendable {
    let id: NotificationID
    let title: String
    let body: String
    let createdAt: Date
    let isRead: Bool
    let relatedWorkOrderId: WorkOrderID?
}

enum TechnicianNotificationOpenOutcome: Equatable, Sendable {
    case workOrderDetail(WorkOrderID)
    case markedReadOnly
    case missingRelated
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
    private(set) var fallbackMessage: String?

    private let actor: User
    private let dependencies: TechnicianDependencies
    private var items: [AppNotification] = []
    private let asyncLoad = AsyncLoadSession()

    var showsLoadingIndicator: Bool { asyncLoad.showsLoadingIndicator }
    var hasCachedContent: Bool { !notifications.isEmpty }
    var unreadCount: Int { notifications.filter { !$0.isRead }.count }

    init(actor: User, dependencies: TechnicianDependencies) {
        self.actor = actor
        self.dependencies = dependencies
    }

    func load() async {
        let context = asyncLoad.start(hadCachedContent: hasCachedContent)
        if !context.hadCachedContentAtStart { phase = .loading }
        defer { asyncLoad.finish(generation: context.generation) }
        let generation = context.generation
        do {
            try await reloadFromLocalCache(generation: generation)
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
            return
        } catch let error as DomainError {
            guard asyncLoad.isCurrent(generation) else { return }
            phase = .error(error.technicianMessage)
            return
        } catch {
            guard asyncLoad.isCurrent(generation) else { return }
            phase = .error("Bildirimler yüklenemedi.")
            return
        }

        guard asyncLoad.isCurrent(generation) else { return }
        guard await dependencies.networkReachability.isReachable else { return }

        await dependencies.localDirectoryCacheRefresh.refreshNotifications(
            recipientUserId: actor.id
        )
        await dependencies.localDirectoryCacheRefresh.refreshTechnicianAssignments(
            technicianId: actor.id
        )

        guard asyncLoad.isCurrent(generation) else { return }
        try? await reloadFromLocalCache(generation: generation)
    }

    /// Pulls remote assignments + notifications, then re-renders from local cache.
    func refreshFromRemoteDirectory() async {
        let generation = asyncLoad.loadGeneration
        guard await dependencies.networkReachability.isReachable else {
            try? await reloadFromLocalCache(generation: generation)
            return
        }

        await dependencies.localDirectoryCacheRefresh.refreshNotifications(
            recipientUserId: actor.id
        )
        await dependencies.localDirectoryCacheRefresh.refreshTechnicianAssignments(
            technicianId: actor.id
        )

        guard asyncLoad.isCurrent(generation) else { return }
        try? await reloadFromLocalCache(generation: generation)
    }

    private func reloadFromLocalCache(generation: Int) async throws {
        let prefs = try await dependencies.profileAccountService.loadUser(id: actor.id).notificationPreferences
        guard asyncLoad.isCurrent(generation) else { return }
        let fetched = try await dependencies.notificationRepository.list(for: actor.id, unreadOnly: false)
        guard asyncLoad.isCurrent(generation) else { return }
        let visible = fetched.filter { prefs.allowsDisplay(of: $0.type) }
        items = visible.sorted { $0.createdAt > $1.createdAt }
        notifications = items.map(Self.mapRow)
        phase = notifications.isEmpty ? .empty : .loaded
    }

    func open(_ id: NotificationID) async -> TechnicianNotificationOpenOutcome {
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
            if await dependencies.networkReachability.isReachable {
                await dependencies.localDirectoryCacheRefresh.refreshTechnicianAssignments(
                    technicianId: actor.id
                )
            }
            return .workOrderDetail(workOrderId)
        }
        return .markedReadOnly
    }

    func clearFallbackMessage() {
        fallbackMessage = nil
    }

    private func markLocallyRead(id: NotificationID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].isRead = true
        notifications = items.map(Self.mapRow)
        if case .error = phase { return }
        phase = notifications.isEmpty ? .empty : .loaded
    }

    private static func mapRow(_ n: AppNotification) -> TechnicianNotificationRow {
        TechnicianNotificationRow(
            id: n.id,
            title: n.title,
            body: n.body,
            createdAt: n.createdAt,
            isRead: n.isRead,
            relatedWorkOrderId: n.relatedWorkOrderId
        )
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
                isRead: $0.isRead,
                relatedWorkOrderId: $0.relatedWorkOrderId
            )
        }
        return vm
    }
}
#endif
