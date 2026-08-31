import Foundation
import Observation

struct AdminSystemHealth: Equatable, Sendable {
    var pendingSync = 0
    var failedSync = 0
    var inProgressSync = 0
    var unresolvedConflicts = 0
    var isOnline = true
}

@Observable
@MainActor
final class AdminSystemViewModel {
    enum Phase: Equatable {
        case loading
        case loaded
        case error(String)
    }

    private(set) var phase: Phase = .loading
    private(set) var health = AdminSystemHealth()
    private(set) var syncStatusMessage: String?
    let appVersion: String

    private let actor: User
    private let dependencies: AdminDependencies
    private let syncProgressStore: SyncProgressStore?
    private let asyncLoad = AsyncLoadSession()

    var showsLoadingIndicator: Bool { asyncLoad.showsLoadingIndicator }
    var hasCachedContent: Bool {
        health.pendingSync > 0 || health.failedSync > 0 || health.inProgressSync > 0
            || health.unresolvedConflicts > 0 || phase == .loaded
    }

    var accountService: ProfileAccountService {
        dependencies.profileAccountService
    }

    init(
        actor: User,
        dependencies: AdminDependencies,
        syncProgressStore: SyncProgressStore? = nil
    ) {
        self.actor = actor
        self.dependencies = dependencies
        self.syncProgressStore = syncProgressStore
        self.appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
    }

    func load() async {
        let context = asyncLoad.start(hadCachedContent: hasCachedContent)
        if !context.hadCachedContentAtStart { phase = .loading }
        defer { asyncLoad.finish(generation: context.generation) }
        let generation = context.generation
        do {
            guard RoleAccessPolicy.can(.manageSystemConfiguration, as: actor.role) else {
                throw DomainError.unauthorized(action: .manageSystemConfiguration)
            }
            let now = Date()
            let pending = try await dependencies.syncOperationRepository.countPending(now: now)
            let issueSnapshot = try await dependencies.syncManager.issueSnapshot()
            let inProgress = try await dependencies.syncOperationRepository.fetchInProgress()
            let conflicts = try await dependencies.syncConflictRepository.listUnresolved()
            let online = await dependencies.networkReachability.isReachable

            guard asyncLoad.isCurrent(generation) else { return }
            health = AdminSystemHealth(
                pendingSync: pending,
                failedSync: issueSnapshot.activeFailedCount,
                inProgressSync: inProgress.count,
                unresolvedConflicts: conflicts.count,
                isOnline: online
            )
            if let store = syncProgressStore {
                if store.isSyncing {
                    syncStatusMessage = store.statusMessage
                } else {
                    syncStatusMessage = store.lastReport?.summaryLine ?? store.statusMessage
                }
            }
            phase = .loaded
        } catch is CancellationError {
            if let settled = asyncLoad.settleCancelledLoad(
                context: context,
                phase: phase,
                loadingPhase: Phase.loading,
                loadedPhase: Phase.loaded,
                emptyPhase: Phase.error("Yükleme iptal edildi. Tekrar deneyin.")
            ) {
                phase = settled
            }
        } catch let error as DomainError {
            guard asyncLoad.isCurrent(generation) else { return }
            phase = .error(error.adminMessage)
        } catch {
            guard asyncLoad.isCurrent(generation) else { return }
            phase = .error("Sistem bilgileri yüklenemedi.")
        }
    }
}

#if DEBUG
extension AdminSystemViewModel {
    static func previewLoaded() -> AdminSystemViewModel {
        let vm = AdminSystemViewModel(
            actor: AdminPreviewData.adminUser,
            dependencies: DIContainer.mock().makeAdminDependencies()
        )
        vm.phase = .loaded
        vm.health = AdminSystemHealth(pendingSync: 3, failedSync: 1, inProgressSync: 0, unresolvedConflicts: 2)
        return vm
    }
}
#endif
