import Foundation
import Observation

struct OperatorDashboardSummary: Equatable, Sendable {
    var total: Int = 0
    var assigned: Int = 0
    var inProgress: Int = 0
    var completed: Int = 0
}

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
    private(set) var summary = OperatorDashboardSummary()
    private(set) var urgentOrders: [WorkOrderCardData] = []
    private(set) var greetingDate = WorkOrderPresentationMapping.greetingDate()
    let userFirstName: String

    private let actor: User
    private let dependencies: OperatorDependencies

    init(actor: User, dependencies: OperatorDependencies) {
        self.actor = actor
        self.dependencies = dependencies
        self.userFirstName = actor.fullName.split(separator: " ").first.map(String.init) ?? actor.fullName
    }

    func load() async {
        phase = .loading
        do {
            let orders = try await dependencies.getWorkOrders.execute(actor: actor)
            summary = Self.makeSummary(from: orders)
            urgentOrders = await Self.makeUrgentCards(from: orders, dependencies: dependencies)
            phase = orders.isEmpty ? .empty : .loaded
        } catch is CancellationError {
            return
        } catch let error as DomainError {
            phase = .error(error.operatorMessage)
        } catch {
            phase = .error("Veriler yüklenemedi.")
        }
    }

    private static func makeSummary(from orders: [WorkOrder]) -> OperatorDashboardSummary {
        OperatorDashboardSummary(
            total: orders.count,
            assigned: orders.filter { $0.status == .assigned }.count,
            inProgress: orders.filter { WorkOrderPresentationMapping.isActiveStatus($0.status) }.count,
            completed: orders.filter { $0.status == .completed }.count
        )
    }

    private static func makeUrgentCards(
        from orders: [WorkOrder],
        dependencies: OperatorDependencies
    ) async -> [WorkOrderCardData] {
        let urgent = orders
            .filter { $0.priority == .urgent && $0.status != .completed }
            .sorted { $0.scheduledDate < $1.scheduledDate }

        var cards: [WorkOrderCardData] = []
        for order in urgent.prefix(5) {
            let customerName = (try? await dependencies.customerRepository.fetch(id: order.customerId))?.name
                ?? "Bilinmeyen müşteri"
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

#if DEBUG
extension OperatorDashboardViewModel {
    static func previewLoaded() -> OperatorDashboardViewModel {
        let vm = OperatorDashboardViewModel(
            actor: OperatorPreviewData.operatorUser,
            dependencies: DIContainer.mock().makeOperatorDependencies()
        )
        vm.phase = .loaded
        vm.summary = OperatorDashboardSummary(total: 24, assigned: 8, inProgress: 10, completed: 6)
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
