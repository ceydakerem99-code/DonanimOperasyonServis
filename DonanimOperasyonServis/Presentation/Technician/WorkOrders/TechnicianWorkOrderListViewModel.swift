import Foundation
import Observation

@Observable
@MainActor
final class TechnicianWorkOrderListViewModel {
    enum Phase: Equatable {
        case loading
        case loaded
        case empty
        case error(String)
    }

    private(set) var phase: Phase = .loading
    private(set) var cards: [WorkOrderCardData] = []
    var selectedFilter: TechnicianWorkOrderListFilter = .active
    var searchText = ""

    private let actor: User
    private let dependencies: TechnicianDependencies
    private let asyncLoad = AsyncLoadSession()
    private var cachedOrders: [WorkOrder] = []

    var showsLoadingIndicator: Bool { asyncLoad.showsLoadingIndicator }
    var hasCachedContent: Bool { !cards.isEmpty }

    init(actor: User, dependencies: TechnicianDependencies) {
        self.actor = actor
        self.dependencies = dependencies
    }

    func load() async {
        let context = asyncLoad.start(hadCachedContent: hasCachedContent)
        if !context.hadCachedContentAtStart { phase = .loading }
        defer { asyncLoad.finish(generation: context.generation) }
        let generation = context.generation

        #if DEBUG
        let cacheStarted = ContinuousClock.now
        #endif

        do {
            try await reloadFromLocalCache(generation: generation)
            #if DEBUG
            let cacheMs = cacheStarted.duration(to: .now).milliseconds
            AppLogger.app.info("WORKORDERS LOAD CACHE durationMs=\(cacheMs)")
            #endif
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
            return
        } catch let error as DomainError {
            guard asyncLoad.isCurrent(generation) else { return }
            phase = .error(error.technicianMessage)
            return
        } catch {
            guard asyncLoad.isCurrent(generation) else { return }
            phase = .error("İş emirleri yüklenemedi.")
            return
        }

        guard asyncLoad.isCurrent(generation) else { return }
        guard await dependencies.networkReachability.isReachable else { return }

        #if DEBUG
        let refreshStarted = ContinuousClock.now
        AppLogger.app.info("WORKORDERS REFRESH START")
        #endif

        await dependencies.localDirectoryCacheRefresh.refreshTechnicianAssignments(
            technicianId: actor.id
        )
        await dependencies.localDirectoryCacheRefresh.refreshNotifications(
            recipientUserId: actor.id
        )

        guard asyncLoad.isCurrent(generation) else { return }

        #if DEBUG
        let refreshMs = refreshStarted.duration(to: .now).milliseconds
        AppLogger.app.info("WORKORDERS REFRESH END durationMs=\(refreshMs)")
        #endif

        try? await reloadFromLocalCache(generation: generation)
    }

    /// Pulls remote assignments + notifications, then re-renders from local cache.
    func refreshFromRemoteDirectory() async {
        let generation = asyncLoad.loadGeneration
        guard await dependencies.networkReachability.isReachable else {
            try? await reloadFromLocalCache(generation: generation)
            return
        }

        await dependencies.localDirectoryCacheRefresh.refreshTechnicianAssignments(
            technicianId: actor.id
        )
        await dependencies.localDirectoryCacheRefresh.refreshNotifications(
            recipientUserId: actor.id
        )

        guard asyncLoad.isCurrent(generation) else { return }
        try? await reloadFromLocalCache(generation: generation)
    }

    func applyLocalSearch() async {
        let generation = asyncLoad.loadGeneration
        await applyPresentation(from: cachedOrders, generation: generation)
    }

    func selectFilter(_ filter: TechnicianWorkOrderListFilter) async {
        selectedFilter = filter
        await applyLocalSearch()
    }

    private func reloadFromLocalCache(generation: Int) async throws {
        cachedOrders = try await dependencies.getWorkOrders.execute(actor: actor)
        guard asyncLoad.isCurrent(generation) else { return }
        await applyPresentation(from: cachedOrders, generation: generation)
    }

    private func applyPresentation(from orders: [WorkOrder], generation: Int) async {
        let filtered = Self.applyFilter(selectedFilter, to: orders)
        let searched = Self.applySearch(searchText, to: filtered)
        let built = await Self.makeCards(from: searched, dependencies: dependencies)
        guard asyncLoad.isCurrent(generation) else { return }
        cards = built
        phase = cards.isEmpty ? .empty : .loaded
    }

    private static func applyFilter(_ filter: TechnicianWorkOrderListFilter, to orders: [WorkOrder]) -> [WorkOrder] {
        switch filter {
        case .active: return orders.filter { !$0.status.isTerminal }
        case .urgent: return orders.filter { $0.priority == .urgent && !$0.status.isTerminal }
        case .inProgress: return orders.filter { $0.status == .inProgress || WorkOrderPresentationMapping.isActiveStatus($0.status) }
        case .paused: return orders.filter { $0.status == .paused }
        case .completed: return orders.filter { $0.status.isTerminal }
        }
    }

    private static func applySearch(_ text: String, to orders: [WorkOrder]) -> [WorkOrder] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return orders }
        let needle = trimmed.lowercased()
        return orders.filter {
            $0.workOrderNumber.lowercased().contains(needle)
                || $0.deviceBrand.lowercased().contains(needle)
        }
    }

    private static func makeCards(
        from orders: [WorkOrder],
        dependencies: TechnicianDependencies,
        now: Date = Date(),
        calendar: Calendar = .current
    ) async -> [WorkOrderCardData] {
        var cards: [WorkOrderCardData] = []
        for order in WorkOrderListSorting.sortAssignedWorkOrders(orders) {
            let customerName = (try? await dependencies.customerRepository.fetch(id: order.customerId))?.name
                ?? "Bilinmeyen müşteri"
            cards.append(
                WorkOrderPresentationMapping.cardData(
                    from: order,
                    customerName: customerName,
                    technicianName: nil,
                    now: now,
                    calendar: calendar
                )
            )
        }
        return cards
    }
}

#if DEBUG
private extension Duration {
    var milliseconds: Int64 {
        let components = components
        return Int64(components.seconds) * 1000 + Int64(components.attoseconds / 1_000_000_000_000_000)
    }
}

extension TechnicianWorkOrderListViewModel {
    static func previewLoaded() -> TechnicianWorkOrderListViewModel {
        let vm = TechnicianWorkOrderListViewModel(
            actor: TechnicianPreviewData.technician,
            dependencies: DIContainer.mock().makeTechnicianDependencies()
        )
        vm.phase = .loaded
        vm.cards = TechnicianPreviewData.sampleOrders.map {
            WorkOrderPresentationMapping.cardData(
                from: $0,
                customerName: TechnicianPreviewData.customer.name,
                technicianName: nil
            )
        }
        return vm
    }
}
#endif
