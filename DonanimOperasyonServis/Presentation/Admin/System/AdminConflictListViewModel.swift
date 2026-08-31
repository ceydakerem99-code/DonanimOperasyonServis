import Foundation
import Observation

struct AdminConflictRowData: Identifiable, Equatable, Sendable {
    let id: String
    let entityType: String
    let entityId: String
    let detectedAt: String
}

@Observable
@MainActor
final class AdminConflictListViewModel {
    enum Phase: Equatable {
        case loading
        case loaded
        case empty
        case error(String)
    }

    private(set) var phase: Phase = .loading
    private(set) var rows: [AdminConflictRowData] = []

    private let actor: User
    private let dependencies: AdminDependencies
    private let asyncLoad = AsyncLoadSession()

    var showsLoadingIndicator: Bool { asyncLoad.showsLoadingIndicator }
    var hasCachedContent: Bool { !rows.isEmpty }

    init(actor: User, dependencies: AdminDependencies) {
        self.actor = actor
        self.dependencies = dependencies
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
            let conflicts = try await dependencies.syncConflictRepository.listUnresolved()
            guard asyncLoad.isCurrent(generation) else { return }
            rows = conflicts.map {
                AdminConflictRowData(
                    id: $0.id.rawValue,
                    entityType: $0.entityType.rawValue,
                    entityId: $0.entityId,
                    detectedAt: WorkOrderPresentationMapping.formatDateTime($0.detectedAt)
                )
            }
            phase = rows.isEmpty ? .empty : .loaded
        } catch is CancellationError {
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
            phase = .error(error.adminMessage)
        } catch {
            guard asyncLoad.isCurrent(generation) else { return }
            phase = .error("Çakışmalar yüklenemedi.")
        }
    }
}

#if DEBUG
extension AdminConflictListViewModel {
    static func previewEmpty() -> AdminConflictListViewModel {
        let vm = AdminConflictListViewModel(
            actor: AdminPreviewData.adminUser,
            dependencies: DIContainer.mock().makeAdminDependencies()
        )
        vm.phase = .empty
        return vm
    }
}
#endif
