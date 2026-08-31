import Foundation
import Observation

@Observable
@MainActor
final class OperatorCustomerAnalyticsViewModel {
    enum Phase: Equatable {
        case loading
        case ready
        case empty
        case error(String)
    }

    private(set) var phase: Phase = .loading
    private(set) var customers: [Customer] = []
    private(set) var selectedCustomer: Customer?
    private(set) var summary: CustomerAnalyticsSummary?
    private(set) var technicianHistory: [CustomerTechnicianVisitEntry] = []
    private(set) var operationHistory: [CustomerOperationEntry] = []
    private(set) var deviceHistory: [CustomerDeviceEntry] = []
    private(set) var timeline: [CustomerTimelineEntry] = []

    var customerSearchText = ""

    private let actor: User
    private let dependencies: OperatorDependencies
    private let asyncLoad = AsyncLoadSession()
    private var cachedOrders: [WorkOrder] = []
    private var techniciansById: [UserID: User] = [:]

    var showsLoadingIndicator: Bool { asyncLoad.showsLoadingIndicator }
    var hasCachedContent: Bool { !customers.isEmpty }

    var filteredCustomers: [Customer] {
        ReportSearchFilters.filterCustomersForAnalytics(customers, query: customerSearchText)
    }

    var customerPickerCards: [CustomerAnalyticsPickerCard] {
        filteredCustomers.map { customer in
            let orders = cachedOrders.filter { $0.customerId == customer.id }
            let summary = CustomerAnalyticsAggregator.summary(customer: customer, orders: orders)
            return CustomerAnalyticsPickerCard(
                id: customer.id,
                customer: customer,
                workplace: summary.workplace,
                totalVisits: summary.totalVisits,
                shortSummary: CustomerAnalyticsAggregator.pickerShortSummary(from: summary)
            )
        }
    }

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
            let orders = try await dependencies.getWorkOrders.execute(actor: actor, filter: .all)
            guard asyncLoad.isCurrent(generation) else { return }
            cachedOrders = orders

            let customerList = try await dependencies.customerRepository.list(searchText: nil)
            guard asyncLoad.isCurrent(generation) else { return }
            customers = customerList.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }

            techniciansById = await loadTechnicians(from: orders)
            guard asyncLoad.isCurrent(generation) else { return }

            if let selectedCustomer, customers.contains(where: { $0.id == selectedCustomer.id }) {
                applyAnalytics(for: selectedCustomer, generation: generation)
            } else {
                clearAnalytics()
            }

            phase = customers.isEmpty ? .empty : .ready
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
            phase = .error("Müşteri analizi yüklenemedi.")
        }
    }

    func selectCustomer(_ customer: Customer) {
        selectedCustomer = customer
        applyAnalytics(for: customer, generation: asyncLoad.loadGeneration)
    }

    func clearSelection() {
        clearAnalytics()
    }

    private func applyAnalytics(for customer: Customer, generation: Int) {
        guard asyncLoad.isCurrent(generation) else { return }
        let scoped = cachedOrders.filter { $0.customerId == customer.id }
        summary = CustomerAnalyticsAggregator.summary(customer: customer, orders: scoped)
        technicianHistory = CustomerAnalyticsAggregator.technicianHistory(
            orders: scoped.filter { $0.status != .rejected },
            technicians: techniciansById
        )
        operationHistory = CustomerAnalyticsAggregator.operationHistory(orders: scoped)
        deviceHistory = CustomerAnalyticsAggregator.deviceHistory(orders: scoped)
        timeline = CustomerAnalyticsAggregator.timeline(orders: scoped, technicians: techniciansById)
    }

    private func clearAnalytics() {
        selectedCustomer = nil
        summary = nil
        technicianHistory = []
        operationHistory = []
        deviceHistory = []
        timeline = []
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
