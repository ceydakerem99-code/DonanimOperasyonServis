import Foundation
import Observation

struct TechnicianHomeSummary: Equatable, Sendable {
    var total = 0
    var inProgress = 0
    var paused = 0
    var completed = 0
}

@Observable
@MainActor
final class TechnicianHomeViewModel {
    enum Phase: Equatable {
        case loading
        case loaded
        case empty
        case error(String)
    }

    private(set) var phase: Phase = .loading
    private(set) var summary = TechnicianHomeSummary()
    private(set) var activeJob: WorkOrderCardData?
    private(set) var upcomingJobs: [WorkOrderCardData] = []
    let userFirstName: String

    private let actor: User
    private let dependencies: TechnicianDependencies
    private let asyncLoad = AsyncLoadSession()

    var showsLoadingIndicator: Bool { asyncLoad.showsLoadingIndicator }
    var hasCachedContent: Bool { summary.total > 0 || activeJob != nil || !upcomingJobs.isEmpty }

    init(actor: User, dependencies: TechnicianDependencies) {
        self.actor = actor
        self.dependencies = dependencies
        self.userFirstName = actor.fullName.split(separator: " ").first.map(String.init) ?? actor.fullName
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
            try await applyFromLocalCache(generation: generation)
            #if DEBUG
            let cacheMs = cacheStarted.duration(to: .now).milliseconds
            AppLogger.app.info("HOME LOAD CACHE durationMs=\(cacheMs)")
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
            phase = .error("Veriler yüklenemedi.")
            return
        }

        guard asyncLoad.isCurrent(generation) else { return }
        guard await dependencies.networkReachability.isReachable else { return }

        #if DEBUG
        let refreshStarted = ContinuousClock.now
        AppLogger.app.info("HOME LOAD REFRESH START")
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
        AppLogger.app.info("HOME LOAD REFRESH END durationMs=\(refreshMs)")
        #endif

        try? await applyFromLocalCache(generation: generation)
    }

    /// Pulls remote assignments + notifications, then re-renders from local cache.
    /// Used after foregrounding or when another tab receives assignment updates.
    func refreshFromRemoteDirectory() async {
        let generation = asyncLoad.loadGeneration
        guard await dependencies.networkReachability.isReachable else {
            try? await applyFromLocalCache(generation: generation)
            return
        }

        await dependencies.localDirectoryCacheRefresh.refreshTechnicianAssignments(
            technicianId: actor.id
        )
        await dependencies.localDirectoryCacheRefresh.refreshNotifications(
            recipientUserId: actor.id
        )

        guard asyncLoad.isCurrent(generation) else { return }
        try? await applyFromLocalCache(generation: generation)
    }

    private func applyFromLocalCache(generation: Int) async throws {
        let orders = try await dependencies.getWorkOrders.execute(actor: actor)
        guard asyncLoad.isCurrent(generation) else { return }

        summary = Self.makeSummary(from: orders)
        let cards = await Self.makeCards(from: orders, dependencies: dependencies)
        guard asyncLoad.isCurrent(generation) else { return }

        activeJob = cards.first { card in
            guard let order = orders.first(where: { $0.id.rawValue == card.id }) else { return false }
            return order.status == .inProgress || WorkOrderPresentationMapping.isActiveStatus(order.status)
        }
        upcomingJobs = cards
            .filter { card in
                orders.first(where: { $0.id.rawValue == card.id })?.status == .assigned
            }
            .prefix(3)
            .map { $0 }
        phase = orders.isEmpty ? .empty : .loaded

        #if DEBUG
        AppLogger.app.info("HOME LOAD END phase=\(String(describing: self.phase), privacy: .public)")
        #endif
    }

    private static func makeSummary(from orders: [WorkOrder]) -> TechnicianHomeSummary {
        TechnicianHomeSummary(
            total: orders.count,
            inProgress: orders.filter { WorkOrderPresentationMapping.isActiveStatus($0.status) || $0.status == .inProgress }.count,
            paused: orders.filter { $0.status == .paused }.count,
            completed: orders.filter { $0.status == .completed }.count
        )
    }

    private static func makeCards(
        from orders: [WorkOrder],
        dependencies: TechnicianDependencies
    ) async -> [WorkOrderCardData] {
        var cards: [WorkOrderCardData] = []
        for order in orders.sorted(by: { $0.scheduledDate < $1.scheduledDate }) {
            let customerName = (try? await dependencies.customerRepository.fetch(id: order.customerId))?.name
                ?? "Bilinmeyen müşteri"
            cards.append(
                WorkOrderPresentationMapping.cardData(
                    from: order,
                    customerName: customerName,
                    technicianName: nil
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

extension TechnicianHomeViewModel {
    static func previewLoaded() -> TechnicianHomeViewModel {
        let vm = TechnicianHomeViewModel(
            actor: TechnicianPreviewData.technician,
            dependencies: DIContainer.mock().makeTechnicianDependencies()
        )
        vm.phase = .loaded
        vm.summary = TechnicianHomeSummary(total: 8, inProgress: 2, paused: 1, completed: 5)
        vm.activeJob = WorkOrderPresentationMapping.cardData(
            from: TechnicianPreviewData.workOrder(status: .inProgress),
            customerName: TechnicianPreviewData.customer.name,
            technicianName: nil
        )
        return vm
    }
}
#endif
