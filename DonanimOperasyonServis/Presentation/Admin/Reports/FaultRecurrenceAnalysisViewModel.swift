import Foundation
import Observation

@Observable
@MainActor
final class FaultRecurrenceAnalysisViewModel {
    enum Phase: Equatable {
        case loading
        case ready
        case empty
        case error(String)
    }

    private(set) var phase: Phase = .loading
    private(set) var entries: [FaultRecurrenceEntry] = []
    private(set) var customerSummaries: [FaultRecurrenceCustomerSummary] = []
    private(set) var workTypeSummaries: [FaultRecurrenceWorkTypeSummary] = []
    private(set) var kpis: FaultRecurrenceKPIs?

    var searchText = ""
    var selectedWorkType: WorkType?
    var filterDateFrom: Date?
    var filterDateTo: Date?

    private let actor: User
    private let dependencies: AdminDependencies
    private let asyncLoad = AsyncLoadSession()
    private var cachedOrders: [WorkOrder] = []
    private var techniciansById: [UserID: User] = [:]
    private var customersById: [CustomerID: Customer] = [:]

    var showsLoadingIndicator: Bool { asyncLoad.showsLoadingIndicator }
    var hasCachedContent: Bool { !entries.isEmpty }

    var filteredEntries: [FaultRecurrenceEntry] {
        ReportSearchFilters.filterFaultRecurrenceEntries(
            entries,
            query: searchText,
            workType: selectedWorkType,
            dateFrom: filterDateFrom,
            dateTo: filterDateTo
        )
    }

    init(actor: User, dependencies: AdminDependencies) {
        self.actor = actor
        self.dependencies = dependencies
    }

    func load() async {
        let context = asyncLoad.start(hadCachedContent: hasCachedContent)
        if !context.hadCachedContentAtStart { phase = .loading }
        defer { asyncLoad.finish(generation: context.generation) }
        let generation = context.generation

        do {
            let orders = try await dependencies.getSystemWorkOrders.execute(actor: actor)
            guard asyncLoad.isCurrent(generation) else { return }
            cachedOrders = orders

            let customerList = try await dependencies.customerRepository.list(searchText: nil)
            guard asyncLoad.isCurrent(generation) else { return }
            customersById = Dictionary(uniqueKeysWithValues: customerList.map { ($0.id, $0) })

            techniciansById = await loadTechnicians(from: orders)
            guard asyncLoad.isCurrent(generation) else { return }

            applyAggregation()
            phase = entries.isEmpty ? .empty : .ready
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
            phase = .error(error.adminMessage)
        } catch {
            guard asyncLoad.isCurrent(generation) else { return }
            phase = .error("Arıza tekrar analizi yüklenemedi.")
        }
    }

    func detailRows(for entry: FaultRecurrenceEntry) -> [FaultRecurrenceDetailRow] {
        FaultRecurrenceAggregator.detailRows(
            for: entry,
            orders: cachedOrders,
            technicians: techniciansById
        )
    }

    private func applyAggregation() {
        entries = FaultRecurrenceAggregator.deviceEntries(
            orders: cachedOrders,
            customers: customersById,
            technicians: techniciansById
        )
        customerSummaries = FaultRecurrenceAggregator.customerSummaries(from: entries)
        workTypeSummaries = FaultRecurrenceAggregator.workTypeSummaries(from: entries)
        kpis = entries.isEmpty ? nil : FaultRecurrenceAggregator.kpis(from: entries)
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

#if DEBUG
extension FaultRecurrenceAnalysisViewModel {
    static func previewReady() -> FaultRecurrenceAnalysisViewModel {
        let vm = FaultRecurrenceAnalysisViewModel(
            actor: AdminPreviewData.adminUser,
            dependencies: DIContainer.mock().makeAdminDependencies()
        )
        vm.phase = .ready
        vm.entries = [
            FaultRecurrenceEntry(
                id: "preview-1",
                customerId: CustomerID("cust-preview"),
                customerName: "ABC Müşterisi",
                workplace: "ABC Müşterisi · İstanbul",
                serialNumber: "POS-01",
                deviceLabel: "POS · POS-01",
                workType: .repair,
                issueLabel: "Bağlantı problemi",
                recurrenceCount: 4,
                lastOccurrenceDate: AdminPreviewData.referenceDate,
                technicianNames: ["Mehmet Kerem", "Ahmet Yılmaz"],
                workOrderIds: []
            )
        ]
        vm.kpis = FaultRecurrenceAggregator.kpis(from: vm.entries)
        return vm
    }
}
#endif
