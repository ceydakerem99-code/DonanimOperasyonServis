import Foundation
import Observation

@Observable
@MainActor
final class OperatorCustomerSatisfactionViewModel {
    enum Phase: Equatable {
        case loading
        case ready
        case empty
        case error(String)
    }

    private(set) var phase: Phase = .loading
    private(set) var summary: CustomerSatisfactionSummary?
    private(set) var ratingBars: [CustomerSatisfactionRatingBar] = []
    private(set) var technicianSummaries: [CustomerSatisfactionTechnicianSummary] = []
    private(set) var recentEntries: [CustomerSatisfactionEntry] = []

    private let actor: User
    private let dependencies: OperatorDependencies
    private let asyncLoad = AsyncLoadSession()

    var showsLoadingIndicator: Bool { asyncLoad.showsLoadingIndicator }
    var hasCachedContent: Bool { summary != nil }

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
            guard RoleAccessPolicy.can(.viewSystemReports, as: actor.role) else {
                throw DomainError.unauthorized(action: .viewSystemReports)
            }

            let orders = try await dependencies.getWorkOrders.execute(actor: actor, filter: .all)
            guard asyncLoad.isCurrent(generation) else { return }
            let workOrdersById = Dictionary(uniqueKeysWithValues: orders.map { ($0.id, $0) })
            let visibleWorkOrderIds = Set(orders.map(\.id))

            await dependencies.localDirectoryCacheRefresh.refreshCustomerSatisfactions()
            let allSatisfactions = try await loadAllSatisfactions()
            guard asyncLoad.isCurrent(generation) else { return }
            let satisfactions = allSatisfactions.filter { visibleWorkOrderIds.contains($0.workOrderId) }

            let customerList = try await dependencies.customerRepository.list(searchText: nil)
            guard asyncLoad.isCurrent(generation) else { return }
            let customersById = Dictionary(uniqueKeysWithValues: customerList.map { ($0.id, $0) })

            let techniciansById = await loadTechnicians(from: orders)
            guard asyncLoad.isCurrent(generation) else { return }

            apply(
                satisfactions: satisfactions,
                workOrdersById: workOrdersById,
                customersById: customersById,
                techniciansById: techniciansById
            )
        } catch is CancellationError {
            if let settled = asyncLoad.settleCancelledLoad(
                context: context,
                phase: phase,
                loadingPhase: Phase.loading,
                loadedPhase: Phase.ready,
                emptyPhase: Phase.empty
            ) {
                phase = settled
            }
        } catch let error as DomainError {
            guard asyncLoad.isCurrent(generation) else { return }
            phase = .error(error.operatorMessage)
        } catch {
            guard asyncLoad.isCurrent(generation) else { return }
            phase = .error("Müşteri memnuniyeti verileri yüklenemedi.")
        }
    }

    private func apply(
        satisfactions: [CustomerSatisfaction],
        workOrdersById: [WorkOrderID: WorkOrder],
        customersById: [CustomerID: Customer],
        techniciansById: [UserID: User]
    ) {
        guard !satisfactions.isEmpty else {
            summary = nil
            ratingBars = []
            technicianSummaries = []
            recentEntries = []
            phase = .empty
            return
        }

        let builtSummary = CustomerSatisfactionAggregator.summary(from: satisfactions)
        summary = builtSummary
        ratingBars = CustomerSatisfactionAggregator.ratingBars(from: builtSummary)
        technicianSummaries = CustomerSatisfactionAggregator.technicianSummaries(
            satisfactions: satisfactions,
            workOrdersById: workOrdersById,
            techniciansById: techniciansById
        )
        recentEntries = CustomerSatisfactionAggregator.entries(
            satisfactions: satisfactions,
            workOrdersById: workOrdersById,
            customersById: customersById,
            techniciansById: techniciansById
        )
        phase = .ready
    }

    private func loadAllSatisfactions() async throws -> [CustomerSatisfaction] {
        let repository = dependencies.customerSatisfactionRepository
        async let pending = repository.listByStatus(.pending)
        async let submitted = repository.listByStatus(.submitted)
        async let expired = repository.listByStatus(.expired)
        return try await pending + submitted + expired
    }

    private func loadTechnicians(from orders: [WorkOrder]) async -> [UserID: User] {
        var result: [UserID: User] = [:]
        if let technicians = try? await dependencies.userRepository.list(role: .technician, isActive: nil) {
            for tech in technicians { result[tech.id] = tech }
        }
        for techId in Set(orders.map(\.assignedTechnicianId)) where result[techId] == nil {
            if let tech = try? await dependencies.userRepository.fetch(id: techId) {
                result[techId] = tech
            }
        }
        return result
    }
}
