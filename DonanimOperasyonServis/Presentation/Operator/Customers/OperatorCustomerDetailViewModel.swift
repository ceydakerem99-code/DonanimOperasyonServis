import Foundation
import Observation

struct OperatorCustomerDetailContent: Equatable, Sendable {
    let customer: Customer
    let workOrderCards: [WorkOrderCardData]
}

@Observable
@MainActor
final class OperatorCustomerDetailViewModel {
    enum Phase: Equatable {
        case loading
        case loaded
        case error(String)
    }

    let customerId: CustomerID

    private(set) var phase: Phase = .loading
    private(set) var content: OperatorCustomerDetailContent?

    private let actor: User
    private let dependencies: OperatorDependencies
    private let asyncLoad = AsyncLoadSession()

    var showsLoadingIndicator: Bool { asyncLoad.showsLoadingIndicator }
    var hasCachedContent: Bool { content != nil }

    init(customerId: CustomerID, actor: User, dependencies: OperatorDependencies) {
        self.customerId = customerId
        self.actor = actor
        self.dependencies = dependencies
    }

    func load() async {
        let context = asyncLoad.start(hadCachedContent: hasCachedContent)
        if !context.hadCachedContentAtStart { phase = .loading }
        defer { asyncLoad.finish(generation: context.generation) }
        let generation = context.generation
        let workOrderFilter = WorkOrderFilter(customerId: customerId)

        do {
            let customer = try await dependencies.customerRepository.fetch(id: customerId)
            let orders = try await dependencies.getWorkOrders.execute(
                actor: actor,
                filter: workOrderFilter
            )
            guard asyncLoad.isCurrent(generation) else { return }
            try await applyContent(customer: customer, orders: orders, generation: generation)
        } catch is CancellationError {
            guard asyncLoad.isCurrent(generation) else { return }
            if let settled = asyncLoad.settleCancelledLoad(
                context: context,
                phase: phase,
                loadingPhase: Phase.loading,
                loadedPhase: Phase.loaded,
                emptyPhase: Phase.error("Yükleme iptal edildi. Tekrar deneyin.")
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
            phase = .error("Müşteri detayı yüklenemedi.")
            return
        }

        guard asyncLoad.isCurrent(generation) else { return }
        if await dependencies.networkReachability.isReachable {
            await dependencies.localDirectoryCacheRefresh.refreshWorkOrders(filter: workOrderFilter)
            if let customer = try? await dependencies.customerRepository.fetch(id: customerId),
               let orders = try? await dependencies.getWorkOrders.execute(
                   actor: actor,
                   filter: workOrderFilter
               ) {
                guard asyncLoad.isCurrent(generation) else { return }
                try? await applyContent(customer: customer, orders: orders, generation: generation)
            }
        }
    }

    private func applyContent(
        customer: Customer,
        orders: [WorkOrder],
        generation: Int
    ) async throws {
        let cards = await Self.makeCards(
            from: orders,
            customerName: customer.name,
            dependencies: dependencies
        )
        guard asyncLoad.isCurrent(generation) else { return }
        content = OperatorCustomerDetailContent(customer: customer, workOrderCards: cards)
        phase = .loaded
    }

    private static func makeCards(
        from orders: [WorkOrder],
        customerName: String,
        dependencies: OperatorDependencies
    ) async -> [WorkOrderCardData] {
        let sorted = orders.sorted {
            if $0.status.isTerminal != $1.status.isTerminal {
                return !$0.status.isTerminal
            }
            return $0.scheduledDate > $1.scheduledDate
        }
        var cards: [WorkOrderCardData] = []
        for order in sorted {
            let technician = try? await dependencies.userRepository.fetch(id: order.assignedTechnicianId)
            cards.append(
                WorkOrderPresentationMapping.cardData(
                    from: order,
                    customerName: customerName,
                    technicianName: technician?.fullName
                )
            )
        }
        return cards
    }
}
