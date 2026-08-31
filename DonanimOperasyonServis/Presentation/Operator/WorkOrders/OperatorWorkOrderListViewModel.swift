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
    private(set) var displayedOrders: [WorkOrder] = []
    var isSelectionMode = false
    private(set) var selectedOrderIDs: Set<WorkOrderID> = []
    private(set) var isPerformingBulkMutation = false
    private(set) var bulkResultSummary: String?
    private(set) var bulkFailureDetails: [BulkWorkOrderMutationFailure] = []

    var showsBulkAssignSheet = false
    var showsBulkPrioritySheet = false
    var showsBulkScheduleSheet = false
    var bulkPrioritySelection: WorkOrderPriority = .normal
    var bulkScheduledDate = Date()
    var bulkScheduledStart = Date()
    var bulkScheduledEnd = Date().addingTimeInterval(3600)
    var technicianSearchText = ""
    private(set) var assignableTechnicians: [User] = []
    private(set) var workOrdersForAssignment: [WorkOrder] = []
    private(set) var assignmentLocationContext: TechnicianAssignmentLocationContext?
    private var locationsByWorkOrderId: [WorkOrderID: [WorkOrderLocation]] = [:]
    private(set) var isLoadingTechnicians = false
    private(set) var selectedTechnicianId: UserID?

    var selectedCount: Int { selectedOrderIDs.count }
    var selectionSummaryText: String {
        selectedCount == 0 ? "Seçim yok" : "\(selectedCount) iş emri seçildi"
    }
    var canPerformBulkActions: Bool {
        selectedCount > 0 && !isPerformingBulkMutation
    }
    var eligibleSelectableCount: Int {
        displayedOrders.filter(WorkOrderBulkMutationPolicy.supportsBulkPlanningMutation).count
    }

    var bulkResultDetailMessage: String {
        guard !bulkFailureDetails.isEmpty else { return bulkResultSummary ?? "" }
        let lines = bulkFailureDetails.map { "\($0.workOrderNumber): \($0.reason)" }
        let header = bulkResultSummary ?? ""
        return ([header] + lines).joined(separator: "\n")
    }

    var filteredAssignableTechnicians: [User] {
        let filtered = TechnicianAssignmentSupport.filterTechniciansByName(
            assignableTechnicians,
            query: technicianSearchText
        )
        return TechnicianAssignmentSupport.sortedTechniciansForAssignment(
            filtered,
            orders: workOrdersForAssignment,
            locationContext: assignmentLocationContext
        )
    }

    var selectedFilter: OperatorWorkOrderListFilter = .all
    /// Optional priority scope (e.g. urgent from dashboard "Tüm Acil İşler").
    private(set) var priorityFilter: WorkOrderPriority?
    private(set) var dashboardScope: OperatorWorkOrderDashboardScope = .none
    var searchText = ""

    private let actor: User
    private let dependencies: OperatorDependencies
    private let asyncLoad = AsyncLoadSession()
    private var cachedOrders: [WorkOrder] = []
    private var cachedCustomers: [CustomerID: Customer] = [:]
    private var cachedTechnicians: [UserID: User] = [:]

    var showsLoadingIndicator: Bool { asyncLoad.showsLoadingIndicator }
    var hasCachedContent: Bool { !cards.isEmpty }

    init(actor: User, dependencies: OperatorDependencies) {
        self.actor = actor
        self.dependencies = dependencies
    }

    func load() async {
        let context = asyncLoad.start(hadCachedContent: hasCachedContent)
        if !context.hadCachedContentAtStart { phase = .loading }
        defer { asyncLoad.finish(generation: context.generation) }
        let generation = context.generation
        let repositoryFilter = WorkOrderFilter(
            status: selectedFilter.matchesActiveStatuses ? nil : selectedFilter.status,
            priority: priorityFilter
        )

        do {
            let orders = try await dependencies.getWorkOrders.execute(actor: actor, filter: repositoryFilter)
            guard asyncLoad.isCurrent(generation) else { return }
            try await applyLoadedOrders(orders, generation: generation)
        } catch is CancellationError {
            guard asyncLoad.isCurrent(generation) else { return }
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
            if hasCachedContent {
                phase = .loaded
            } else {
                phase = .error(error.operatorMessage)
            }
            return
        } catch {
            guard asyncLoad.isCurrent(generation) else { return }
            if hasCachedContent {
                phase = .loaded
            } else {
                phase = .error("İş emirleri yüklenemedi.")
            }
            return
        }

        guard asyncLoad.isCurrent(generation) else { return }
        if await dependencies.networkReachability.isReachable {
            await dependencies.localDirectoryCacheRefresh.refreshWorkOrders(filter: repositoryFilter)
            if let refreshed = try? await dependencies.getWorkOrders.execute(actor: actor, filter: repositoryFilter) {
                guard asyncLoad.isCurrent(generation) else { return }
                try? await applyLoadedOrders(refreshed, generation: generation)
            }
        }
    }

    private func applyLoadedOrders(_ orders: [WorkOrder], generation: Int) async throws {
        var scoped = orders
        if selectedFilter.matchesActiveStatuses {
            scoped = scoped.filter { WorkOrderPresentationMapping.isActiveStatus($0.status) }
        }
        scoped = Self.applyDashboardScope(dashboardScope, to: scoped)
        if selectedFilter == .completed {
            scoped = scoped.filter { $0.status == .completed }
        } else if let status = selectedFilter.status {
            scoped = scoped.filter { $0.status == status }
        }
        cachedOrders = scoped
        cachedCustomers = await loadCustomerMap(for: scoped)
        cachedTechnicians = await loadTechnicianMap(for: scoped)
        await applyPresentation(generation: generation)
    }

    private func loadCustomerMap(for orders: [WorkOrder]) async -> [CustomerID: Customer] {
        var map: [CustomerID: Customer] = [:]
        if let customers = try? await dependencies.customerRepository.list(searchText: nil) {
            for customer in customers { map[customer.id] = customer }
        }
        for customerId in Set(orders.map(\.customerId)) where map[customerId] == nil {
            if let customer = try? await dependencies.customerRepository.fetch(id: customerId) {
                map[customerId] = customer
            }
        }
        return map
    }

    private func loadTechnicianMap(for orders: [WorkOrder]) async -> [UserID: User] {
        var map: [UserID: User] = [:]
        if let technicians = try? await dependencies.userRepository.list(role: .technician, isActive: nil) {
            for tech in technicians { map[tech.id] = tech }
        }
        for techId in Set(orders.map(\.assignedTechnicianId)) where map[techId] == nil {
            if let tech = try? await dependencies.userRepository.fetch(id: techId) {
                map[techId] = tech
            }
        }
        return map
    }

    func setSelectionMode(_ enabled: Bool) {
        isSelectionMode = enabled
        if !enabled {
            selectedOrderIDs.removeAll()
        }
    }

    func isSelected(_ orderId: WorkOrderID) -> Bool {
        selectedOrderIDs.contains(orderId)
    }

    func canSelect(_ orderId: WorkOrderID) -> Bool {
        guard let order = displayedOrders.first(where: { $0.id == orderId }) else { return false }
        return WorkOrderBulkMutationPolicy.supportsBulkPlanningMutation(order)
    }

    func toggleSelection(_ orderId: WorkOrderID) {
        guard canSelect(orderId) else { return }
        if selectedOrderIDs.contains(orderId) {
            selectedOrderIDs.remove(orderId)
        } else {
            selectedOrderIDs.insert(orderId)
        }
    }

    func selectAllEligible() {
        selectedOrderIDs = Set(
            WorkOrderBulkMutationPolicy.eligibleOrders(from: displayedOrders).map(\.id)
        )
    }

    func clearSelection() {
        selectedOrderIDs.removeAll()
    }

    func prepareBulkAssignSheet() async {
        guard canPerformBulkActions else { return }
        showsBulkAssignSheet = true
        isLoadingTechnicians = true
        technicianSearchText = ""
        selectedTechnicianId = nil
        workOrdersForAssignment = (try? await dependencies.getWorkOrders.execute(actor: actor, filter: .all)) ?? displayedOrders
        do {
            assignableTechnicians = try await dependencies.userRepository.list(role: .technician, isActive: true)
        } catch {
            assignableTechnicians = []
        }
        isLoadingTechnicians = false
        if await dependencies.networkReachability.isReachable {
            await dependencies.localDirectoryCacheRefresh.refreshTechnicians()
            if let refreshed = try? await dependencies.userRepository.list(role: .technician, isActive: true) {
                assignableTechnicians = refreshed
            }
        }
        await reloadBulkAssignmentLocations()
    }

    private func reloadBulkAssignmentLocations() async {
        let selectedOrders = displayedOrders.filter { selectedOrderIDs.contains($0.id) }
        let locationOrderIds = Array(
            Set(workOrdersForAssignment.map(\.id)).union(selectedOrderIDs)
        )
        locationsByWorkOrderId = await TechnicianAssignmentLocationLoader.loadLocations(
            for: locationOrderIds,
            repository: dependencies.workOrderLocationRepository
        )
        assignmentLocationContext = TechnicianAssignmentLocationBuilder.buildContext(
            workOrderSite: TechnicianAssignmentLocationBuilder.resolveBulkAssignmentSite(
                selectedOrders: selectedOrders,
                locationsByWorkOrderId: locationsByWorkOrderId
            ),
            technicians: assignableTechnicians,
            locationsByWorkOrderId: locationsByWorkOrderId
        )
    }

    func locationLabel(for technician: User) -> String? {
        guard assignmentLocationContext != nil else { return nil }
        return assignmentLocationContext?.assignmentLocationLabel(for: technician.id)
    }

    func isRecommended(_ technician: User) -> Bool {
        TechnicianAssignmentSupport.isRecommended(
            technicianId: technician.id,
            among: assignableTechnicians,
            orders: workOrdersForAssignment,
            locationContext: assignmentLocationContext
        )
    }

    func workingStatus(for technician: User) -> TechnicianWorkingStatus {
        TechnicianAssignmentSupport.workingStatus(for: technician.id, orders: workOrdersForAssignment)
    }

    func workload(for technician: User) -> TechnicianWorkloadCounts {
        TechnicianAssignmentSupport.workload(for: technician.id, orders: workOrdersForAssignment)
    }

    func selectTechnicianForBulkAssign(_ technician: User) {
        selectedTechnicianId = technician.id
    }

    func confirmBulkAssign() async {
        guard let technicianId = selectedTechnicianId else { return }
        await performBulkAssign(technicianId: technicianId)
    }

    func selectBulkPriority(_ priority: WorkOrderPriority) {
        bulkPrioritySelection = priority
    }

    func confirmBulkPriorityUpdate() async {
        await performBulkPriorityUpdate(priority: bulkPrioritySelection)
    }

    func confirmBulkScheduleUpdate() async {
        await performBulkScheduleUpdate()
    }

    func cancelPendingBulkMutation() {}

    func dismissBulkResult() {
        bulkResultSummary = nil
        bulkFailureDetails = []
    }

    private func ordersByID() -> [WorkOrderID: WorkOrder] {
        Dictionary(uniqueKeysWithValues: displayedOrders.map { ($0.id, $0) })
    }

    private func performBulkAssign(technicianId: UserID) async {
        isPerformingBulkMutation = true
        defer { isPerformingBulkMutation = false }
        let result = await OperatorWorkOrderBulkOperations.assignTechnician(
            orderIds: Array(selectedOrderIDs),
            ordersByID: ordersByID(),
            technicianId: technicianId,
            actor: actor,
            service: dependencies.workOrderService
        )
        applyBulkResult(result)
        showsBulkAssignSheet = false
        selectedTechnicianId = nil
        await reloadAfterBulkMutation()
    }

    private func performBulkPriorityUpdate(priority: WorkOrderPriority) async {
        isPerformingBulkMutation = true
        defer { isPerformingBulkMutation = false }
        let result = await OperatorWorkOrderBulkOperations.updatePriority(
            orderIds: Array(selectedOrderIDs),
            ordersByID: ordersByID(),
            priority: priority,
            actor: actor,
            service: dependencies.workOrderService
        )
        applyBulkResult(result)
        showsBulkPrioritySheet = false
        await reloadAfterBulkMutation()
    }

    private func performBulkScheduleUpdate() async {
        isPerformingBulkMutation = true
        defer { isPerformingBulkMutation = false }
        let range = ScheduledTimeRange(start: bulkScheduledStart, end: bulkScheduledEnd)
        let result = await OperatorWorkOrderBulkOperations.updateSchedule(
            orderIds: Array(selectedOrderIDs),
            ordersByID: ordersByID(),
            scheduledDate: bulkScheduledDate,
            scheduledTimeRange: range,
            actor: actor,
            service: dependencies.workOrderService
        )
        applyBulkResult(result)
        showsBulkScheduleSheet = false
        await reloadAfterBulkMutation()
    }

    private func reloadAfterBulkMutation() async {
        await load()
    }

    private func applyBulkResult(_ result: BulkWorkOrderMutationResult) {
        bulkFailureDetails = result.failures
        if result.successCount > 0 && result.failureCount == 0 {
            bulkResultSummary = "\(result.successCount) iş emri güncellendi"
            selectedOrderIDs.subtract(result.succeeded)
        } else if result.successCount > 0 && result.failureCount > 0 {
            bulkResultSummary = "\(result.successCount) iş emri güncellendi\n\(result.failureCount) iş emri güncellenemedi"
            selectedOrderIDs = Set(result.failures.map(\.orderId))
        } else if result.failureCount > 0 {
            bulkResultSummary = "\(result.failureCount) iş emri güncellenemedi"
        } else {
            bulkResultSummary = "Güncellenecek iş emri bulunamadı."
        }
    }

    func selectFilter(_ filter: OperatorWorkOrderListFilter) async {
        selectedFilter = filter
        priorityFilter = nil
        dashboardScope = filter == .paused ? .paused : .none
        await load()
    }

    func showUrgentPriorityOnly() async {
        await applyDashboardScope(.urgent)
    }

    func applyDashboardScope(_ scope: OperatorWorkOrderDashboardScope) async {
        dashboardScope = scope
        selectedFilter = scope.listFilter
        priorityFilter = scope.priorityFilter
        await load()
    }

    func clearDashboardScope() async {
        dashboardScope = .none
        priorityFilter = nil
        selectedFilter = .all
        await load()
    }

    func clearPriorityFilter() async {
        priorityFilter = nil
        dashboardScope = .none
        await load()
    }

    /// Resets list scope to the default operator listing after create.
    func resetToDefaultListingAndLoad() async {
        selectedFilter = .all
        priorityFilter = nil
        dashboardScope = .none
        searchText = ""
        await load()
    }

    private static func applyDashboardScope(
        _ scope: OperatorWorkOrderDashboardScope,
        to orders: [WorkOrder],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [WorkOrder] {
        switch scope {
        case .none:
            return orders
        case .open:
            return orders.filter { !$0.status.isTerminal }
        case .urgent:
            return orders.filter { $0.priority == .urgent && !$0.status.isTerminal }
        case .overdue:
            return WorkOrderTimeStatusPolicy.filterDashboardOverdue(orders, now: now, calendar: calendar)
        case .paused:
            return orders.filter { $0.status == .paused }
        case .completed:
            return orders.filter { $0.status == .completed }
        }
    }

    func applyLocalSearch() async {
        await applyPresentation(generation: asyncLoad.loadGeneration)
    }

    private func applyPresentation(generation: Int) async {
        let filtered = Self.applySearch(
            searchText,
            to: cachedOrders,
            customers: cachedCustomers,
            technicians: cachedTechnicians
        )
        let built = await Self.makeCards(
            from: filtered,
            customers: cachedCustomers,
            technicians: cachedTechnicians,
            dependencies: dependencies
        )
        guard asyncLoad.isCurrent(generation) else { return }
        displayedOrders = filtered
        cards = built
        selectedOrderIDs = selectedOrderIDs.intersection(Set(filtered.map(\.id)))
        phase = cards.isEmpty ? .empty : .loaded
    }

    private static func applySearch(
        _ text: String,
        to orders: [WorkOrder],
        customers: [CustomerID: Customer] = [:],
        technicians: [UserID: User] = [:]
    ) -> [WorkOrder] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return orders }
        let needle = trimmed.lowercased()
        return orders.filter { order in
            order.workOrderNumber.lowercased().contains(needle)
                || order.deviceBrand.lowercased().contains(needle)
                || order.deviceModel.lowercased().contains(needle)
                || order.serialNumber.lowercased().contains(needle)
                || order.issueDescription?.lowercased().contains(needle) == true
                || technicians[order.assignedTechnicianId]?.fullName.lowercased().contains(needle) == true
                || customerMatches(customers[order.customerId], needle: needle)
        }
    }

    private static func customerMatches(_ customer: Customer?, needle: String) -> Bool {
        guard let customer else { return false }
        return customer.name.lowercased().contains(needle)
            || CustomerAnalyticsAggregator.workplaceLabel(for: customer).lowercased().contains(needle)
            || customer.address.lowercased().contains(needle)
            || customer.city?.lowercased().contains(needle) == true
            || customer.id.rawValue.lowercased().contains(needle)
    }

    private static func makeCards(
        from orders: [WorkOrder],
        customers: [CustomerID: Customer],
        technicians: [UserID: User],
        dependencies: OperatorDependencies,
        now: Date = Date(),
        calendar: Calendar = .current
    ) async -> [WorkOrderCardData] {
        var cards: [WorkOrderCardData] = []
        for order in orders.sorted(by: {
            let t0 = $0.status.isTerminal
            let t1 = $1.status.isTerminal
            if t0 != t1 { return !t0 }
            if $0.priority.sortOrder != $1.priority.sortOrder {
                return $0.priority.sortOrder > $1.priority.sortOrder
            }
            return $0.scheduledDate > $1.scheduledDate
        }) {
            let customerName = customers[order.customerId]?.name ?? "Bilinmeyen müşteri"
            let technicianName = technicians[order.assignedTechnicianId]?.fullName
            cards.append(
                WorkOrderPresentationMapping.cardData(
                    from: order,
                    customerName: customerName,
                    technicianName: technicianName,
                    now: now,
                    calendar: calendar
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
