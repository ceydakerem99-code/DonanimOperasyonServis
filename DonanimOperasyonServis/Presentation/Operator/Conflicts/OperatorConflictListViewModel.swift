import Foundation
import Observation

struct OperatorConflictRowData: Identifiable, Equatable, Sendable {
    let id: SyncConflictID
    let entityTypeLabel: String
    let entityId: String
    let detectedAtLabel: String
    let localVersion: Int
    let remoteVersion: Int
    let localReference: String?
    let remoteReference: String?
}

@Observable
@MainActor
final class OperatorConflictListViewModel {
    enum Phase: Equatable {
        case loading
        case loaded
        case empty
        case error(String)
    }

    private(set) var phase: Phase = .loading
    private(set) var rows: [OperatorConflictRowData] = []

    private let actor: User
    private let dependencies: OperatorDependencies
    private let asyncLoad = AsyncLoadSession()

    var showsLoadingIndicator: Bool { asyncLoad.showsLoadingIndicator }
    var hasCachedContent: Bool { !rows.isEmpty }

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
            guard RoleAccessPolicy.can(.resolveSyncConflict, as: actor.role) else {
                throw DomainError.unauthorized(action: .resolveSyncConflict)
            }
            let conflicts = try await dependencies.syncConflictRepository.listUnresolved()
            guard asyncLoad.isCurrent(generation) else { return }
            rows = conflicts
                .sorted { $0.detectedAt > $1.detectedAt }
                .map(Self.makeRow)
            phase = rows.isEmpty ? .empty : .loaded
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
            phase = .error("Çakışmalar yüklenemedi.")
        }
    }

    static func makeRow(_ conflict: SyncConflict) -> OperatorConflictRowData {
        OperatorConflictRowData(
            id: conflict.id,
            entityTypeLabel: OperatorConflictPresentation.entityTypeLabel(conflict.entityType),
            entityId: conflict.entityId,
            detectedAtLabel: WorkOrderPresentationMapping.formatDateTime(conflict.detectedAt),
            localVersion: conflict.localVersion,
            remoteVersion: conflict.remoteVersion,
            localReference: conflict.localReference,
            remoteReference: conflict.remoteReference
        )
    }
}

enum OperatorConflictPresentation {
    static func entityTypeLabel(_ type: SyncEntityType) -> String {
        switch type {
        case .user: return "Kullanıcı"
        case .customer: return "Müşteri"
        case .workOrder: return "İş Emri"
        case .workOrderNote: return "İş Emri Notu"
        case .workOrderStatusHistory: return "Durum Geçmişi"
        case .workOrderPhoto: return "Fotoğraf"
        case .workOrderLocation: return "Konum"
        case .signature: return "İmza"
        case .editRequest: return "Düzenleme Talebi"
        case .notification: return "Bildirim"
        case .customerSatisfaction: return "Müşteri Memnuniyeti"
        }
    }
}

#if DEBUG
extension OperatorConflictListViewModel {
    static func previewEmpty() -> OperatorConflictListViewModel {
        let vm = OperatorConflictListViewModel(
            actor: OperatorPreviewData.operatorUser,
            dependencies: DIContainer.mock().makeOperatorDependencies()
        )
        vm.phase = .empty
        return vm
    }
}
#endif
