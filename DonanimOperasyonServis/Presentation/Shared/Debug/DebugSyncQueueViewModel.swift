#if DEBUG
import Foundation
import Observation

@Observable
@MainActor
final class DebugSyncQueueViewModel {
    enum Phase: Equatable {
        case loading
        case loaded
        case empty
        case error(String)
    }

    private(set) var phase: Phase = .loading
    private(set) var operations: [SyncOperation] = []
    private(set) var retryingOperationId: SyncOperationID?
    private(set) var actionMessage: String?
    var selectedStatus: SyncStatus = .pending

    private let repository: SyncOperationRepository
    private let syncManager: any SyncManaging
    private let asyncLoad = AsyncLoadSession()

    var showsLoadingIndicator: Bool { asyncLoad.showsLoadingIndicator }
    var hasCachedContent: Bool { !operations.isEmpty }

    init(repository: SyncOperationRepository, syncManager: any SyncManaging) {
        self.repository = repository
        self.syncManager = syncManager
    }

    func isRetrying(_ operationId: SyncOperationID) -> Bool {
        retryingOperationId == operationId
    }

    /// DEBUG-only manual retry for a single `.failed` row. Uses
    /// `LocalToRemoteSyncManager.sync(operation:)` which calls
    /// `prepareRetry` then runs the normal apply / mark* pipeline.
    func retry(operation: SyncOperation) async {
        guard operation.status == .failed else { return }
        guard retryingOperationId == nil else { return }

        retryingOperationId = operation.id
        actionMessage = nil
        defer { retryingOperationId = nil }

        do {
            try await syncManager.sync(operation: operation)
            let updated = try await repository.fetch(id: operation.id)
            switch updated.status {
            case .succeeded:
                actionMessage = "Operasyon senkronize edildi."
            case .failed:
                actionMessage = "Operasyon yine başarısız: \(updated.errorMessage ?? "—")"
            case .conflict:
                actionMessage = "Operasyon çakışma durumuna geçti."
            case .pending, .inProgress:
                actionMessage = "Operasyon beklemeye alındı (hold veya bağımlılık)."
            }
            await load()
        } catch let error as DomainError {
            actionMessage = error.adminMessage
            await load()
        } catch {
            actionMessage = "Sync denemesi tamamlanamadı."
            await load()
        }
    }

    func load() async {
        let context = asyncLoad.start(hadCachedContent: hasCachedContent)
        if !context.hadCachedContentAtStart { phase = .loading }
        defer { asyncLoad.finish(generation: context.generation) }
        let generation = context.generation
        do {
            let rows = try await repository.fetch(status: selectedStatus)
            guard asyncLoad.isCurrent(generation) else { return }
            operations = rows
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
            phase = .error("Sync kuyruğu yüklenemedi.")
        }
    }
}
#endif
