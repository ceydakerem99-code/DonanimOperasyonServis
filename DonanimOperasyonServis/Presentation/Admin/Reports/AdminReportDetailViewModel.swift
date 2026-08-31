import Foundation
import Observation

@Observable
@MainActor
final class AdminReportDetailViewModel {
    enum Phase: Equatable {
        case loading
        case loaded
        case empty
        case error(String)
    }

    let kind: AdminReportKind
    private(set) var phase: Phase = .loading
    private(set) var payload = ReportDetailPayload()
    var reportSearchText = ""

    private let actor: User
    private let dependencies: AdminDependencies
    private let asyncLoad = AsyncLoadSession()
    private var cachedOrders: [WorkOrder] = []

    var showsLoadingIndicator: Bool { asyncLoad.showsLoadingIndicator }
    var hasCachedContent: Bool { !payload.isEmpty }

    var displayedWorkOrderEntries: [WorkOrderReportEntry] {
        ReportSearchFilters.filterWorkOrders(payload.workOrderEntries, query: reportSearchText)
    }

    var displayedSignatureEntries: [SignatureReportEntry] {
        ReportSearchFilters.filterSignatures(payload.signatureEntries, query: reportSearchText)
    }

    var displayedPhotoEntries: [PhotoReportEntry] {
        ReportSearchFilters.filterPhotos(payload.photoEntries, query: reportSearchText)
    }

    var displayedPauseEntries: [PauseReportEntry] {
        ReportSearchFilters.filterPauses(payload.pauseEntries, query: reportSearchText)
    }

    var displayedTechnicianEntries: [TechnicianPerformanceEntry] {
        ReportSearchFilters.filterTechnicians(payload.technicianEntries, query: reportSearchText)
    }

    var metrics: [AdminReportMetric] { payload.metrics }
    var statusBreakdown: [AdminStatusBreakdown] { payload.statusBreakdown }

    var canBulkDelete: Bool {
        RoleAccessPolicy.can(.deleteWorkOrder, as: actor.role) && kind == .workOrders
    }

    var isSelectionMode = false
    private(set) var selectedOrderIDs: Set<WorkOrderID> = []
    private(set) var isPerformingBulkDelete = false
    var showsBulkDeleteConfirmation = false
    private(set) var bulkResultSummary: String?
    private(set) var bulkFailureDetails: [BulkWorkOrderMutationFailure] = []

    var selectedCount: Int { selectedOrderIDs.count }
    var selectionSummaryText: String {
        selectedCount == 0 ? "Seçim yok" : "\(selectedCount) iş emri seçildi"
    }
    var canPerformBulkDelete: Bool {
        selectedCount > 0 && !isPerformingBulkDelete && canBulkDelete
    }
    var bulkDeleteConfirmationMessage: String {
        "\(selectedCount) iş emri kalıcı olarak silinecek. Bu işlem geri alınamaz."
    }
    var bulkResultDetailMessage: String {
        guard !bulkFailureDetails.isEmpty else { return bulkResultSummary ?? "" }
        let lines = bulkFailureDetails.map { "\($0.workOrderNumber): \($0.reason)" }
        let header = bulkResultSummary ?? ""
        return ([header] + lines).joined(separator: "\n")
    }
    var eligibleSelectableCount: Int {
        cachedOrders.filter(WorkOrderBulkMutationPolicy.supportsBulkDelete).count
    }

    init(kind: AdminReportKind, actor: User, dependencies: AdminDependencies) {
        self.kind = kind
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

            let repositories = ReportDatasetBuilder.Repositories(
                customerRepository: dependencies.customerRepository,
                userRepository: dependencies.userRepository,
                signatureRepository: dependencies.signatureRepository,
                workOrderPhotoRepository: dependencies.workOrderPhotoRepository,
                statusHistoryRepository: dependencies.statusHistoryRepository
            )
            payload = await ReportDatasetBuilder.build(
                kind: kind,
                orders: orders,
                repositories: repositories
            )
            guard asyncLoad.isCurrent(generation) else { return }
            phase = payload.isEmpty ? .empty : .loaded
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
        } catch let error as DomainError {
            guard asyncLoad.isCurrent(generation) else { return }
            phase = .error(error.adminMessage)
        } catch {
            guard asyncLoad.isCurrent(generation) else { return }
            phase = .error("Rapor yüklenemedi.")
        }
    }

    func setSelectionMode(_ enabled: Bool) {
        isSelectionMode = enabled
        if !enabled {
            selectedOrderIDs.removeAll()
            showsBulkDeleteConfirmation = false
        }
    }

    func isSelected(_ orderId: WorkOrderID) -> Bool {
        selectedOrderIDs.contains(orderId)
    }

    func canSelect(_ orderId: WorkOrderID) -> Bool {
        guard let order = cachedOrders.first(where: { $0.id == orderId }) else { return false }
        return WorkOrderBulkMutationPolicy.supportsBulkDelete(order)
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
        let visibleIDs = Set(displayedWorkOrderEntries.map(\.id))
        selectedOrderIDs = Set(
            WorkOrderBulkMutationPolicy.eligibleOrdersForDelete(from: cachedOrders)
                .map(\.id)
                .filter { visibleIDs.contains($0) }
        )
    }

    func clearSelection() {
        selectedOrderIDs.removeAll()
    }

    func requestBulkDeleteConfirmation() {
        guard canPerformBulkDelete else { return }
        showsBulkDeleteConfirmation = true
    }

    func cancelBulkDeleteConfirmation() {
        showsBulkDeleteConfirmation = false
    }

    func confirmBulkDelete() async {
        guard canPerformBulkDelete else {
            showsBulkDeleteConfirmation = false
            return
        }

        isPerformingBulkDelete = true
        defer {
            isPerformingBulkDelete = false
            showsBulkDeleteConfirmation = false
        }

        let orderIds = Array(selectedOrderIDs)
        let result = await AdminWorkOrderBulkOperations.delete(
            orderIds: orderIds,
            ordersByID: ordersByID(),
            actor: actor,
            service: dependencies.workOrderService
        )
        applyBulkDeleteResult(result)
        await load()
        if result.isCompleteSuccess {
            setSelectionMode(false)
        }
    }

    func dismissBulkResult() {
        bulkResultSummary = nil
        bulkFailureDetails = []
    }

    private func ordersByID() -> [WorkOrderID: WorkOrder] {
        Dictionary(uniqueKeysWithValues: cachedOrders.map { ($0.id, $0) })
    }

    private func applyBulkDeleteResult(_ result: BulkWorkOrderMutationResult) {
        bulkFailureDetails = result.failures
        if result.successCount > 0 && result.failureCount == 0 {
            bulkResultSummary = "\(result.successCount) iş emri silindi"
            selectedOrderIDs.subtract(result.succeeded)
        } else if result.successCount > 0 && result.failureCount > 0 {
            bulkResultSummary = "\(result.successCount) iş emri silindi\n\(result.failureCount) iş emri silinemedi"
            selectedOrderIDs = Set(result.failures.map(\.orderId))
        } else if result.failureCount > 0 {
            bulkResultSummary = "\(result.failureCount) iş emri silinemedi"
        } else {
            bulkResultSummary = "Silinecek iş emri bulunamadı."
        }
    }
}

#if DEBUG
extension AdminReportDetailViewModel {
    static func previewWorkOrders() -> AdminReportDetailViewModel {
        let vm = AdminReportDetailViewModel(
            kind: .workOrders,
            actor: AdminPreviewData.adminUser,
            dependencies: DIContainer.mock().makeAdminDependencies()
        )
        vm.phase = .loaded
        vm.payload = ReportDetailPayload(
            metrics: [
                AdminReportMetric(id: "total", title: "Toplam İş Emri", value: "48"),
                AdminReportMetric(id: "completed", title: "Tamamlanan", value: "25")
            ],
            workOrderEntries: [
                WorkOrderReportEntry(
                    id: WorkOrderID("wo-preview"),
                    workOrderNumber: "WO-741970",
                    customerName: "Ceka",
                    workplace: "Ceka · Çorum",
                    technicianName: "Mehmet Kerem",
                    priority: .urgent,
                    status: .assigned,
                    scheduledDate: AdminPreviewData.referenceDate,
                    deviceLabel: "POS · Ingenico iCT250",
                    workType: .repair,
                    signatureStatusLabel: "İmzasız",
                    photoCount: 2
                )
            ]
        )
        return vm
    }
}
#endif
