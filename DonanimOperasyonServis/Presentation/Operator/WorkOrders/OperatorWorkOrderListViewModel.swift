import Foundation
import Observation

@Observable
@MainActor
final class OperatorWorkOrderListViewModel {
    enum Phase: Equatable {
        case loading
        case loaded
        case empty
        case error(String)
    }

    private(set) var phase: Phase = .loading
    private(set) var cards: [WorkOrderCardData] = []
    var selectedFilter: OperatorWorkOrderListFilter = .all
    var searchText = ""

    private let actor: User
    private let dependencies: OperatorDependencies
    private var loadGeneration = 0

    init(actor: User, dependencies: OperatorDependencies) {
        self.actor = actor
        self.dependencies = dependencies
    }

    func load() async {
        loadGeneration &+= 1
        let generation = loadGeneration
        phase = .loading
        do {
            let filter = WorkOrderFilter(status: selectedFilter.status)
            let orders = try await dependencies.getWorkOrders.execute(actor: actor, filter: filter)
            guard generation == loadGeneration, !Task.isCancelled else { return }
            let filtered = Self.applySearch(searchText, to: orders)
            let built = await Self.makeCards(from: filtered, dependencies: dependencies)
            guard generation == loadGeneration, !Task.isCancelled else { return }
            cards = built
            phase = cards.isEmpty ? .empty : .loaded
        } catch is CancellationError {
            return
        } catch let error as DomainError {
            guard generation == loadGeneration else { return }
            phase = .error(error.operatorMessage)
        } catch {
            guard generation == loadGeneration else { return }
            phase = .error("İş emirleri yüklenemedi.")
        }
    }

    func selectFilter(_ filter: OperatorWorkOrderListFilter) async {
        selectedFilter = filter
        await load()
    }

    private static func applySearch(_ text: String, to orders: [WorkOrder]) -> [WorkOrder] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return orders }
        let needle = trimmed.lowercased()
        return orders.filter {
            $0.workOrderNumber.lowercased().contains(needle)
                || $0.deviceBrand.lowercased().contains(needle)
                || $0.deviceModel.lowercased().contains(needle)
                || $0.serialNumber.lowercased().contains(needle)
        }
    }

    private static func makeCards(
        from orders: [WorkOrder],
        dependencies: OperatorDependencies
    ) async -> [WorkOrderCardData] {
        var cards: [WorkOrderCardData] = []
        for order in orders.sorted(by: { $0.scheduledDate > $1.scheduledDate }) {
            let customerName: String
            if let customer = try? await dependencies.customerRepository.fetch(id: order.customerId) {
                customerName = customer.name
            } else {
                customerName = "Bilinmeyen müşteri"
            }
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
extension OperatorWorkOrderListViewModel {
    static func previewLoaded() -> OperatorWorkOrderListViewModel {
        let vm = OperatorWorkOrderListViewModel(
            actor: OperatorPreviewData.operatorUser,
            dependencies: DIContainer.mock().makeOperatorDependencies()
        )
        vm.phase = .loaded
        vm.cards = OperatorPreviewData.sampleWorkOrders.map {
            WorkOrderPresentationMapping.cardData(
                from: $0,
                customerName: OperatorPreviewData.customerABC.name,
                technicianName: OperatorPreviewData.technicianAhmet.fullName
            )
        }
        return vm
    }

    static func previewEmpty() -> OperatorWorkOrderListViewModel {
        let vm = OperatorWorkOrderListViewModel(
            actor: OperatorPreviewData.operatorUser,
            dependencies: DIContainer.mock().makeOperatorDependencies()
        )
        vm.phase = .empty
        return vm
    }
}
#endif
