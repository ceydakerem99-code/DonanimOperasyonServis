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
    var selectedFilter: TechnicianWorkOrderListFilter = .all
    var searchText = ""

    private let actor: User
    private let dependencies: TechnicianDependencies

    init(actor: User, dependencies: TechnicianDependencies) {
        self.actor = actor
        self.dependencies = dependencies
    }

    func load() async {
        phase = .loading
        do {
            let orders = try await dependencies.getWorkOrders.execute(actor: actor)
            let filtered = Self.applyFilter(selectedFilter, to: orders)
            let searched = Self.applySearch(searchText, to: filtered)
            cards = await Self.makeCards(from: searched, dependencies: dependencies)
            phase = cards.isEmpty ? .empty : .loaded
        } catch is CancellationError {
            return
        } catch let error as DomainError {
            phase = .error(error.technicianMessage)
        } catch {
            phase = .error("İş emirleri yüklenemedi.")
        }
    }

    func selectFilter(_ filter: TechnicianWorkOrderListFilter) async {
        selectedFilter = filter
        await load()
    }

    private static func applyFilter(_ filter: TechnicianWorkOrderListFilter, to orders: [WorkOrder]) -> [WorkOrder] {
        switch filter {
        case .all: return orders
        case .urgent: return orders.filter { $0.priority == .urgent }
        case .inProgress: return orders.filter { $0.status == .inProgress || WorkOrderPresentationMapping.isActiveStatus($0.status) }
        case .paused: return orders.filter { $0.status == .paused }
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
        dependencies: TechnicianDependencies
    ) async -> [WorkOrderCardData] {
        var cards: [WorkOrderCardData] = []
        for order in orders.sorted(by: { $0.scheduledDate > $1.scheduledDate }) {
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
