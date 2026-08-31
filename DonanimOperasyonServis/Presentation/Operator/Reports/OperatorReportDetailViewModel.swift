import Foundation
import Observation

@Observable
@MainActor
final class OperatorReportDetailViewModel {
    enum Phase: Equatable {
        case loading
        case loaded
        case empty
        case error(String)
    }

    let kind: AdminReportKind
    private(set) var phase: Phase = .loading
    private(set) var payload = ReportDetailPayload()
    var reportSearchText = ""

    private let actor: User
    private let dependencies: OperatorDependencies
    private let asyncLoad = AsyncLoadSession()

    var showsLoadingIndicator: Bool { asyncLoad.showsLoadingIndicator }
    var hasCachedContent: Bool { !payload.isEmpty }

    var displayedWorkOrderEntries: [WorkOrderReportEntry] {
        ReportSearchFilters.filterWorkOrders(payload.workOrderEntries, query: reportSearchText)
    }

    var displayedSignatureEntries: [SignatureReportEntry] {
        ReportSearchFilters.filterSignatures(payload.signatureEntries, query: reportSearchText)
    }

    var displayedPhotoEntries: [PhotoReportEntry] {
        ReportSearchFilters.filterPhotos(payload.photoEntries, query: reportSearchText)
    }

    var displayedPauseEntries: [PauseReportEntry] {
        ReportSearchFilters.filterPauses(payload.pauseEntries, query: reportSearchText)
    }

    var displayedTechnicianEntries: [TechnicianPerformanceEntry] {
        ReportSearchFilters.filterTechnicians(payload.technicianEntries, query: reportSearchText)
    }

    var metrics: [AdminReportMetric] { payload.metrics }
    var statusBreakdown: [AdminStatusBreakdown] { payload.statusBreakdown }

    init(kind: AdminReportKind, actor: User, dependencies: OperatorDependencies) {
        self.kind = kind
        self.actor = actor
        self.dependencies = dependencies
    }

    func load() async {
        let context = asyncLoad.start(hadCachedContent: hasCachedContent)
        if !context.hadCachedContentAtStart { phase = .loading }
        defer { asyncLoad.finish(generation: context.generation) }
        let generation = context.generation

        do {
            let orders = try await dependencies.getWorkOrders.execute(actor: actor, filter: .all)
            guard asyncLoad.isCurrent(generation) else { return }

            let repositories = ReportDatasetBuilder.Repositories(
                customerRepository: dependencies.customerRepository,
                userRepository: dependencies.userRepository,
                signatureRepository: dependencies.signatureRepository,
                workOrderPhotoRepository: dependencies.workOrderPhotoRepository,
                statusHistoryRepository: dependencies.statusHistoryRepository
            )
            payload = await ReportDatasetBuilder.build(
                kind: kind,
                orders: orders,
                repositories: repositories
            )
            guard asyncLoad.isCurrent(generation) else { return }
            phase = payload.isEmpty ? .empty : .loaded
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
            phase = .error(error.operatorMessage)
        } catch {
            guard asyncLoad.isCurrent(generation) else { return }
            phase = .error("Rapor yüklenemedi.")
        }
    }
}
