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
    let appVersion: String

    private let actor: User
    private let dependencies: AdminDependencies

    init(actor: User, dependencies: AdminDependencies) {
        self.actor = actor
        self.dependencies = dependencies
        self.appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
    }

    func load() async {
        phase = .loading
        do {
            guard RoleAccessPolicy.can(.manageSystemConfiguration, as: actor.role) else {
                throw DomainError.unauthorized(action: .manageSystemConfiguration)
            }
            let now = Date()
            let pending = try await dependencies.syncOperationRepository.countPending(now: now)
            let failed = try await dependencies.syncOperationRepository.fetchFailed()
            let inProgress = try await dependencies.syncOperationRepository.fetchInProgress()
            let conflicts = try await dependencies.syncConflictRepository.listUnresolved()
            let online = await dependencies.networkReachability.isReachable

            health = AdminSystemHealth(
                pendingSync: pending,
                failedSync: failed.count,
                inProgressSync: inProgress.count,
                unresolvedConflicts: conflicts.count,
                isOnline: online
            )
            phase = .loaded
        } catch let error as DomainError {
            phase = .error(error.adminMessage)
        } catch {
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
