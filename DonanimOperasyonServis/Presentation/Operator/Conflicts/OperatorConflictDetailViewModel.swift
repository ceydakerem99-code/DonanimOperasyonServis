import Foundation
import Observation

@Observable
@MainActor
final class OperatorConflictDetailViewModel {
    enum Phase: Equatable {
        case loading
        case loaded
        case resolving
        case resolved(String)
        case error(String)
    }

    private(set) var phase: Phase = .loading
    private(set) var conflict: SyncConflict?
    private(set) var actionMessage: String?

    let conflictId: SyncConflictID
    private let actor: User
    private let dependencies: OperatorDependencies
    private let asyncLoad = AsyncLoadSession()

    var showsLoadingIndicator: Bool { asyncLoad.showsLoadingIndicator }
    var hasCachedContent: Bool { conflict != nil }

    init(conflictId: SyncConflictID, actor: User, dependencies: OperatorDependencies) {
        self.conflictId = conflictId
        self.actor = actor
        self.dependencies = dependencies
    }

    var entityTypeLabel: String {
        guard let conflict else { return "—" }
        return OperatorConflictPresentation.entityTypeLabel(conflict.entityType)
    }

    var detectedAtLabel: String {
        guard let conflict else { return "—" }
        return WorkOrderPresentationMapping.formatDateTime(conflict.detectedAt)
    }

    var canResolve: Bool {
        conflict?.resolution == nil && RoleAccessPolicy.can(.resolveSyncConflict, as: actor.role)
    }

    func load() async {
        let context = asyncLoad.start(hadCachedContent: hasCachedContent)
        if !context.hadCachedContentAtStart { phase = .loading }
        defer { asyncLoad.finish(generation: context.generation) }
        let generation = context.generation
        actionMessage = nil
        do {
            guard RoleAccessPolicy.can(.resolveSyncConflict, as: actor.role) else {
                throw DomainError.unauthorized(action: .resolveSyncConflict)
            }
            let loaded = try await dependencies.syncConflictRepository.fetch(id: conflictId)
            guard asyncLoad.isCurrent(generation) else { return }
            conflict = loaded
            if loaded.isResolved {
                phase = .resolved(loaded.resolution?.asDecision.displayName ?? "Çözüldü")
            } else {
                phase = .loaded
            }
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
            phase = .error(error.operatorMessage)
        } catch {
            guard asyncLoad.isCurrent(generation) else { return }
            phase = .error("Çakışma detayı yüklenemedi.")
        }
    }

    func resolveUsingLocal() async {
        await resolve(.useLocal)
    }

    func resolveUsingRemote() async {
        await resolve(.useRemote)
    }

    func leaveUnresolved() async {
        await resolve(.unresolved)
    }

    private func resolve(_ decision: ConflictResolutionDecision) async {
        actionMessage = nil
        phase = .resolving
        do {
            let outcome = try await dependencies.conflictResolver.resolve(
                conflictID: conflictId,
                decision: decision,
                actor: actor
            )
            conflict = outcome.conflict
            switch decision {
            case .useLocal:
                actionMessage = "Yerel sürüm seçildi. Senkron kuyruğu güncellendi."
                phase = .resolved(ConflictResolutionDecision.useLocal.displayName)
            case .useRemote:
                actionMessage = "Sunucu sürümü yerel kayda uygulandı."
                phase = .resolved(ConflictResolutionDecision.useRemote.displayName)
            case .unresolved:
                actionMessage = "Çakışma açık bırakıldı."
                phase = .loaded
            }
        } catch is CancellationError {
            phase = conflict == nil ? .error("İşlem iptal edildi.") : .loaded
        } catch let error as DomainError {
            phase = .error(error.operatorMessage)
        } catch {
            phase = .error("Çakışma çözülemedi.")
        }
    }
}
