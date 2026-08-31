import Foundation
import Observation

@Observable
@MainActor
final class OperatorDashboardViewModel {
    enum Phase: Equatable {
        case loading
        case loaded
        case empty
        case error(String)
    }

    private(set) var phase: Phase = .loading
    private(set) var operationsKPIs = OperatorOperationsKPIs()
    private(set) var urgentOrders: [WorkOrderCardData] = []
    private(set) var recentCompletedOrders: [WorkOrderCardData] = []
    private(set) var greetingDate = WorkOrderPresentationMapping.greetingDate()
    let userFirstName: String

    private let actor: User
    private let dependencies: OperatorDependencies
    private let calendar: Calendar
    private let asyncLoad = AsyncLoadSession()

    private var cachedOrders: [WorkOrder] = []
    private var cachedTechnicians: [User] = []

    var showsLoadingIndicator: Bool { asyncLoad.showsLoadingIndicator }
    var hasCachedContent: Bool {
        operationsKPIs.openWorkOrders > 0
            || !urgentOrders.isEmpty
            || !recentCompletedOrders.isEmpty
            || !cachedOrders.isEmpty
    }

    init(
        actor: User,
        dependencies: OperatorDependencies,
        calendar: Calendar = .current
    ) {
        self.actor = actor
        self.dependencies = dependencies
        self.calendar = calendar
        self.userFirstName = actor.fullName.split(separator: " ").first.map(String.init) ?? actor.fullName
    }

    func load(now: Date = Date()) async {
        let context = asyncLoad.start(hadCachedContent: hasCachedContent)
        if !context.hadCachedContentAtStart { phase = .loading }
        defer { asyncLoad.finish(generation: context.generation) }

        do {
            try await reloadDashboard(now: now, generation: context.generation, allowRemoteRefresh: true)
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
            guard asyncLoad.isCurrent(context.generation) else { return }
            if hasCachedContent {
                phase = .loaded
            } else {
                phase = .error(error.operatorMessage)
            }
        } catch {
            guard asyncLoad.isCurrent(context.generation) else { return }
            if hasCachedContent {
                phase = .loaded
            } else {
                phase = .error("Veriler yüklenemedi.")
            }
        }
    }

    /// Cache-first refresh for sync completion, tab return, or local persistence updates.
    func refreshFromLocalCache(now: Date = Date()) async {
        let context = asyncLoad.start(hadCachedContent: true)
        defer { asyncLoad.finish(generation: context.generation) }
        try? await reloadDashboard(now: now, generation: context.generation, allowRemoteRefresh: false)
    }

    private func reloadDashboard(
        now: Date,
        generation: Int,
        allowRemoteRefresh: Bool
    ) async throws {
        let orders = try await dependencies.getWorkOrders.execute(actor: actor)
        guard asyncLoad.isCurrent(generation) else { return }
        try await applyDashboard(orders: orders, now: now, generation: generation)

        guard allowRemoteRefresh, asyncLoad.isCurrent(generation) else { return }
        guard await dependencies.networkReachability.isReachable else { return }

        await dependencies.localDirectoryCacheRefresh.refreshWorkOrders()
        guard asyncLoad.isCurrent(generation) else { return }
        if let refreshed = try? await dependencies.getWorkOrders.execute(actor: actor) {
            try? await applyDashboard(orders: refreshed, now: now, generation: generation)
        }
    }

    private func applyDashboard(orders: [WorkOrder], now: Date, generation: Int) async throws {
        cachedOrders = orders
        cachedTechnicians = (try? await dependencies.userRepository.list(role: .technician, isActive: true)) ?? []
        guard asyncLoad.isCurrent(generation) else { return }

        let customers = await loadCustomerMap(for: orders)
        guard asyncLoad.isCurrent(generation) else { return }

        operationsKPIs = OperatorDashboardOperations.computeKPIs(
            orders: orders,
            technicians: cachedTechnicians,
            now: now,
            calendar: calendar
        )
        urgentOrders = makeUrgentCards(
            from: orders,
            customers: customers,
            technicians: technicianMap(from: cachedTechnicians)
        )
        recentCompletedOrders = AdminDashboardViewModel.makeRecentCompletedCards(
            from: orders,
            customers: customers,
            technicians: technicianMap(from: cachedTechnicians)
        )
        phase = orders.isEmpty ? .empty : .loaded
    }

    private func loadCustomerMap(for orders: [WorkOrder]) async -> [CustomerID: Customer] {
        var map: [CustomerID: Customer] = [:]
        if let customers = try? await dependencies.customerRepository.list(searchText: nil) {
            for customer in customers {
                map[customer.id] = customer
            }
        }
        for customerId in Set(orders.map(\.customerId)) where map[customerId] == nil {
            if let customer = try? await dependencies.customerRepository.fetch(id: customerId) {
                map[customerId] = customer
            }
        }
        return map
    }

    private func technicianMap(from technicians: [User]) -> [UserID: User] {
        Dictionary(uniqueKeysWithValues: technicians.map { ($0.id, $0) })
    }

    private func makeUrgentCards(
        from orders: [WorkOrder],
        customers: [CustomerID: Customer],
        technicians: [UserID: User]
    ) -> [WorkOrderCardData] {
        orders
            .filter { $0.priority == .urgent && !$0.status.isTerminal }
            .sorted { $0.scheduledDate < $1.scheduledDate }
            .prefix(5)
            .map { order in
                WorkOrderPresentationMapping.cardData(
                    from: order,
                    customerName: customers[order.customerId]?.name ?? "Bilinmeyen müşteri",
                    technicianName: technicians[order.assignedTechnicianId]?.fullName
                )
            }
    }
}

#if DEBUG
extension OperatorDashboardViewModel {
    static func previewLoaded() -> OperatorDashboardViewModel {
        let vm = OperatorDashboardViewModel(
            actor: OperatorPreviewData.operatorUser,
            dependencies: DIContainer.mock().makeOperatorDependencies()
        )
        vm.phase = .loaded
        vm.operationsKPIs = OperatorOperationsKPIs(
            openWorkOrders: 24,
            urgentWorkOrders: 3,
            overdueWorkOrders: 2,
            pausedWorkOrders: 1,
            availableTechnicians: 3,
            busyTechnicians: 2,
            availableTechnicianPreview: OperatorTechnicianIdentityPreview(
                count: 3,
                previewNames: ["Mehmet Kerem", "Ahmet Yılmaz"],
                overflowCount: 1
            ),
            busyTechnicianPreview: OperatorTechnicianIdentityPreview(
                count: 2,
                previewNames: ["Burak Şahin", "Can Öztürk"],
                overflowCount: 0
            )
        )
        vm.urgentOrders = OperatorPreviewData.urgentCards
        return vm
    }

    static func previewEmpty() -> OperatorDashboardViewModel {
        let vm = OperatorDashboardViewModel(
            actor: OperatorPreviewData.operatorUser,
            dependencies: DIContainer.mock().makeOperatorDependencies()
        )
        vm.phase = .empty
        return vm
    }

    static func previewError() -> OperatorDashboardViewModel {
        let vm = OperatorDashboardViewModel(
            actor: OperatorPreviewData.operatorUser,
            dependencies: DIContainer.mock().makeOperatorDependencies()
        )
        vm.phase = .error("İş emirleri alınamadı.")
        return vm
    }
}
#endif
