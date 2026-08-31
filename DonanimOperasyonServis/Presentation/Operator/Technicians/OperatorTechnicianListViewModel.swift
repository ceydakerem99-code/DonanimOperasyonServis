import Foundation
import Observation

struct OperatorTechnicianRow: Identifiable, Equatable, Sendable {
    let id: UserID
    let fullName: String
    let workingStatus: TechnicianWorkingStatus
    let workloadSummary: String
}

@Observable
@MainActor
final class OperatorTechnicianListViewModel {
    enum Phase: Equatable {
        case loading
        case loaded
        case empty
        case error(String)
    }

    private(set) var phase: Phase = .loading
    private(set) var rows: [OperatorTechnicianRow] = []
    var selectedFilter: OperatorTechnicianListFilter = .all
    private(set) var dashboardScope: OperatorTechnicianDashboardScope = .none
    var searchText = ""

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
            let orders = try await dependencies.getWorkOrders.execute(actor: actor)
            guard asyncLoad.isCurrent(generation) else { return }
            let technicians = (try? await dependencies.userRepository.list(role: .technician, isActive: true)) ?? []
            guard asyncLoad.isCurrent(generation) else { return }
            applySnapshot(orders: orders, technicians: technicians, generation: generation)
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
            phase = .error(error.operatorMessage)
            return
        } catch {
            guard asyncLoad.isCurrent(generation) else { return }
            phase = .error("Teknisyenler yüklenemedi.")
            return
        }

        guard asyncLoad.isCurrent(generation) else { return }
        if await dependencies.networkReachability.isReachable {
            await dependencies.localDirectoryCacheRefresh.refreshWorkOrders()
            if let refreshedOrders = try? await dependencies.getWorkOrders.execute(actor: actor),
               let refreshedTechnicians = try? await dependencies.userRepository.list(role: .technician, isActive: true) {
                guard asyncLoad.isCurrent(generation) else { return }
                applySnapshot(orders: refreshedOrders, technicians: refreshedTechnicians, generation: generation)
            }
        }
    }

    func selectFilter(_ filter: OperatorTechnicianListFilter) async {
        selectedFilter = filter
        dashboardScope = filter == .all ? .none : OperatorTechnicianDashboardScope(filter)
        await load()
    }

    func applyDashboardScope(_ scope: OperatorTechnicianDashboardScope) async {
        dashboardScope = scope
        selectedFilter = scope.listFilter
        await load()
    }

    func clearDashboardScope() async {
        dashboardScope = .none
        selectedFilter = .all
        await load()
    }

    private func applySnapshot(orders: [WorkOrder], technicians: [User], generation: Int) {
        guard asyncLoad.isCurrent(generation) else { return }
        let sorted = TechnicianAssignmentSupport.sortedTechniciansForAssignment(technicians, orders: orders)
        let statusFilter = selectedFilter.workingStatus

        rows = sorted
            .filter { technician in
                guard let statusFilter else { return true }
                return TechnicianAssignmentSupport.workingStatus(for: technician.id, orders: orders) == statusFilter
            }
            .filter { TechnicianAssignmentSupport.matchesTechnicianNameSearch($0, query: searchText) }
            .map { technician in
                let status = TechnicianAssignmentSupport.workingStatus(for: technician.id, orders: orders)
                let load = TechnicianAssignmentSupport.workload(for: technician.id, orders: orders)
                return OperatorTechnicianRow(
                    id: technician.id,
                    fullName: technician.fullName,
                    workingStatus: status,
                    workloadSummary: load.compactSummary
                )
            }

        phase = rows.isEmpty ? .empty : .loaded
    }
}

private extension OperatorTechnicianDashboardScope {
    init(_ filter: OperatorTechnicianListFilter) {
        switch filter {
        case .all: self = .none
        case .available: self = .available
        case .busy: self = .busy
        }
    }
}

#if DEBUG
extension OperatorTechnicianListViewModel {
    static func previewLoaded() -> OperatorTechnicianListViewModel {
        let vm = OperatorTechnicianListViewModel(
            actor: OperatorPreviewData.operatorUser,
            dependencies: DIContainer.mock().makeOperatorDependencies()
        )
        vm.phase = .loaded
        vm.rows = [
            OperatorTechnicianRow(
                id: OperatorPreviewData.technicianAhmet.id,
                fullName: OperatorPreviewData.technicianAhmet.fullName,
                workingStatus: .available,
                workloadSummary: TechnicianWorkloadCounts().compactSummary
            )
        ]
        return vm
    }
}
#endif
