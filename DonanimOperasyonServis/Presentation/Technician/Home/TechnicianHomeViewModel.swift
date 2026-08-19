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

    init(actor: User, dependencies: TechnicianDependencies) {
        self.actor = actor
        self.dependencies = dependencies
        self.userFirstName = actor.fullName.split(separator: " ").first.map(String.init) ?? actor.fullName
    }

    func load() async {
        phase = .loading
        do {
            let orders = try await dependencies.getWorkOrders.execute(actor: actor)
            summary = Self.makeSummary(from: orders)
            let cards = try await Self.makeCards(from: orders, dependencies: dependencies)
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
        } catch let error as DomainError {
            phase = .error(error.technicianMessage)
        } catch {
            phase = .error("Veriler yüklenemedi.")
        }
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
    ) async throws -> [WorkOrderCardData] {
        var cards: [WorkOrderCardData] = []
        for order in orders.sorted(by: { $0.scheduledDate < $1.scheduledDate }) {
            let customer = try await dependencies.customerRepository.fetch(id: order.customerId)
            cards.append(
                WorkOrderPresentationMapping.cardData(
                    from: order,
                    customerName: customer.name,
                    technicianName: nil
                )
            )
        }
        return cards
    }
}

#if DEBUG
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
