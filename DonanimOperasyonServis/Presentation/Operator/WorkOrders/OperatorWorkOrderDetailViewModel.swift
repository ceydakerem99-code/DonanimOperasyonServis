import Foundation
import Observation

struct OperatorWorkOrderDetailContent: Equatable, Sendable {
    let workOrder: WorkOrder
    let customer: Customer
    let technicianName: String
    let notes: [WorkOrderNote]
    let photos: [WorkOrderPhoto]
    let locations: [WorkOrderLocation]
    let signatures: [Signature]
    let timeline: [WorkOrderStatusHistory]
    let editRequests: [EditRequest]
    let pendingSyncCount: Int

    var photoCount: Int { photos.count }
    var locationCount: Int { locations.count }
    var signatureCount: Int { signatures.count }

    var reportSnapshot: WorkOrderReportSnapshot {
        WorkOrderReportSnapshot(
            workOrder: workOrder,
            customerName: customer.name,
            customerAddress: [customer.address, customer.city].compactMap { $0 }.joined(separator: ", "),
            technicianName: technicianName,
            notes: notes,
            photos: photos,
            locations: locations,
            signatures: signatures,
            timeline: timeline,
            editRequests: editRequests
        )
    }
}

@Observable
@MainActor
final class OperatorWorkOrderDetailViewModel {
    enum Phase: Equatable {
        case loading
        case loaded
        case error(String)
    }

    private(set) var phase: Phase = .loading
    private(set) var content: OperatorWorkOrderDetailContent?
    private(set) var editBlockedMessage: String?
    /// When true, edit alert offers navigation to edit-request inbox.
    private(set) var offersEditRequestNavigation = false

    private(set) var showsAssignSheet = false
    private(set) var assignableTechnicians: [User] = []
    private(set) var workOrdersForAssignment: [WorkOrder] = []
    private(set) var assignmentLocationContext: TechnicianAssignmentLocationContext?
    private var locationsByWorkOrderId: [WorkOrderID: [WorkOrderLocation]] = [:]
    var technicianSearchText = ""
    private(set) var isAssigning = false
    private(set) var isLoadingTechnicians = false
    private(set) var assignmentError: String?
    private(set) var selectedTechnicianId: UserID?

    let workOrderId: WorkOrderID
    private let actor: User
    private let dependencies: OperatorDependencies
    private let asyncLoad = AsyncLoadSession()

    var showsLoadingIndicator: Bool { asyncLoad.showsLoadingIndicator }
    var hasCachedContent: Bool { content != nil }

    /// Policy-backed visibility for the assign / reassign action.
    var canAssignTechnician: Bool {
        RoleAccessPolicy.can(.assignWorkOrder, as: actor.role)
    }

    var assignActionTitle: String {
        "Teknisyeni Değiştir"
    }

    var mediaLoader: WorkOrderMediaLoader {
        WorkOrderMediaLoader(storage: dependencies.storageDataSource)
    }

    init(workOrderId: WorkOrderID, actor: User, dependencies: OperatorDependencies) {
        self.workOrderId = workOrderId
        self.actor = actor
        self.dependencies = dependencies
    }

    func load() async {
        let context = asyncLoad.start(hadCachedContent: hasCachedContent)
        if !context.hadCachedContentAtStart { phase = .loading }
        defer { asyncLoad.finish(generation: context.generation) }
        let generation = context.generation
        do {
            let loaded = try await fetchContentWithDirectoryRefreshIfNeeded()
            guard asyncLoad.isCurrent(generation) else { return }
            content = loaded
            phase = .loaded
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
        } catch let error as DomainError {
            guard asyncLoad.isCurrent(generation) else { return }
            phase = .error(error.operatorMessage)
        } catch {
            guard asyncLoad.isCurrent(generation) else { return }
            phase = .error("İş emri detayı yüklenemedi.")
        }
    }

    func attemptEdit() {
        guard let order = content?.workOrder else { return }
        if order.status.isTerminal {
            offersEditRequestNavigation = true
            editBlockedMessage = DomainError.workOrderLocked(order.id).operatorMessage
        } else {
            offersEditRequestNavigation = false
            editBlockedMessage = "Bu sürümde aktif iş emirleri doğrudan düzenlenemez."
        }
    }

    func clearEditMessage() {
        editBlockedMessage = nil
        offersEditRequestNavigation = false
    }

    func attemptAssign() {
        assignmentError = nil
        guard canAssignTechnician else {
            assignmentError = DomainError.unauthorized(action: .assignWorkOrder).operatorMessage
            return
        }
        guard let order = content?.workOrder else { return }
        if order.isLocked {
            assignmentError = DomainError.workOrderLocked(order.id).operatorMessage
            return
        }
        selectedTechnicianId = order.assignedTechnicianId
        showsAssignSheet = true
    }

    func dismissAssignSheet() {
        guard !isAssigning else { return }
        showsAssignSheet = false
        assignableTechnicians = []
        workOrdersForAssignment = []
        assignmentLocationContext = nil
        locationsByWorkOrderId = [:]
        technicianSearchText = ""
        selectedTechnicianId = nil
        isLoadingTechnicians = false
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

    func locationLabel(for technician: User) -> String? {
        guard assignmentLocationContext != nil else { return nil }
        return assignmentLocationContext?.assignmentLocationLabel(for: technician.id)
    }

    func workingStatus(for technician: User) -> TechnicianWorkingStatus {
        TechnicianAssignmentSupport.workingStatus(for: technician.id, orders: workOrdersForAssignment)
    }

    func workload(for technician: User) -> TechnicianWorkloadCounts {
        TechnicianAssignmentSupport.workload(for: technician.id, orders: workOrdersForAssignment)
    }

    func isRecommended(_ technician: User) -> Bool {
        TechnicianAssignmentSupport.isRecommended(
            technicianId: technician.id,
            among: assignableTechnicians,
            orders: workOrdersForAssignment,
            locationContext: assignmentLocationContext
        )
    }

    func loadAssignableTechnicians() async {
        guard showsAssignSheet else { return }
        isLoadingTechnicians = true
        defer {
            if showsAssignSheet {
                isLoadingTechnicians = false
            }
        }

        do {
            workOrdersForAssignment = (try? await dependencies.getWorkOrders.execute(
                actor: actor,
                filter: .all
            )) ?? []
            assignableTechnicians = try await sortedActiveTechnicians()
        } catch is CancellationError {
            return
        } catch {
            assignableTechnicians = []
            workOrdersForAssignment = []
        }

        guard showsAssignSheet else { return }

        await dependencies.localDirectoryCacheRefresh.refreshTechnicians()

        if let refreshed = try? await sortedActiveTechnicians() {
            guard showsAssignSheet else { return }
            assignableTechnicians = refreshed
            workOrdersForAssignment = (try? await dependencies.getWorkOrders.execute(
                actor: actor,
                filter: .all
            )) ?? workOrdersForAssignment
        }

        if assignableTechnicians.isEmpty, showsAssignSheet {
            assignmentError = "Aktif teknisyen bulunamadı."
        }

        await reloadAssignmentLocations()
    }

    private func reloadAssignmentLocations() async {
        guard showsAssignSheet else { return }
        locationsByWorkOrderId = await TechnicianAssignmentLocationLoader.loadLocations(
            for: workOrdersForAssignment.map(\.id),
            repository: dependencies.workOrderLocationRepository
        )
        if let content, !content.locations.isEmpty {
            locationsByWorkOrderId[workOrderId] = content.locations
        }
        assignmentLocationContext = TechnicianAssignmentLocationBuilder.buildContext(
            workOrderSite: TechnicianAssignmentLocationBuilder.resolveWorkOrderSite(
                customerId: content?.workOrder.customerId,
                workOrderId: workOrderId,
                orders: workOrdersForAssignment,
                locationsByWorkOrderId: locationsByWorkOrderId
            ),
            technicians: assignableTechnicians,
            locationsByWorkOrderId: locationsByWorkOrderId
        )
    }

    private func sortedActiveTechnicians() async throws -> [User] {
        try await dependencies.userRepository.list(role: .technician, isActive: true)
            .sorted { $0.fullName.localizedCaseInsensitiveCompare($1.fullName) == .orderedAscending }
    }

    func selectTechnicianForAssign(_ technician: User) {
        selectedTechnicianId = technician.id
    }

    func confirmAssignment() async {
        guard !isAssigning else { return }
        guard canAssignTechnician else {
            assignmentError = DomainError.unauthorized(action: .assignWorkOrder).operatorMessage
            return
        }
        guard let order = content?.workOrder else { return }
        if order.isLocked {
            assignmentError = DomainError.workOrderLocked(order.id).operatorMessage
            showsAssignSheet = false
            return
        }
        guard let technicianId = selectedTechnicianId else {
            assignmentError = "Teknisyen seçin."
            return
        }
        if technicianId == order.assignedTechnicianId {
            showsAssignSheet = false
            return
        }

        isAssigning = true
        assignmentError = nil
        do {
            _ = try await dependencies.workOrderService.assignWithSync(
                actor: actor,
                orderId: order.id,
                newTechnicianId: technicianId
            )
            showsAssignSheet = false
            assignableTechnicians = []
            selectedTechnicianId = nil
            isAssigning = false
            await load()
        } catch is CancellationError {
            isAssigning = false
        } catch let error as DomainError {
            isAssigning = false
            assignmentError = error.operatorMessage
        } catch {
            isAssigning = false
            assignmentError = "Teknisyen ataması başarısız."
        }
    }

    func clearAssignmentError() {
        assignmentError = nil
    }

    private func fetchContent() async throws -> OperatorWorkOrderDetailContent {
        let order = try await dependencies.getWorkOrder.execute(actor: actor, id: workOrderId)
        let customer = try await dependencies.customerRepository.fetch(id: order.customerId)
        let technician = try await dependencies.userRepository.fetch(id: order.assignedTechnicianId)
        let notes = try await dependencies.workOrderNoteRepository.list(for: order.id)
        let timeline = try await dependencies.statusHistoryRepository.list(for: order.id)
        let photos = (try? await dependencies.workOrderPhotoRepository.list(for: order.id)) ?? []
        let locations = (try? await dependencies.workOrderLocationRepository.list(for: order.id)) ?? []
        let signatures = (try? await dependencies.signatureRepository.list(for: order.id)) ?? []
        let editRequests = (try? await dependencies.editRequestRepository.list(for: order.id)) ?? []
        let pendingOps = try await dependencies.syncOperationRepository.list(
            entityType: .workOrder,
            entityId: order.id.rawValue
        )
        let relatedPending = pendingOps.filter { $0.status == .pending || $0.status == .failed }.count

        return OperatorWorkOrderDetailContent(
            workOrder: order,
            customer: customer,
            technicianName: technician.fullName,
            notes: notes.sorted { $0.createdAt > $1.createdAt },
            photos: photos.sorted { $0.capturedAt > $1.capturedAt },
            locations: locations.sorted { $0.capturedAt > $1.capturedAt },
            signatures: signatures.sorted { $0.capturedAt > $1.capturedAt },
            timeline: timeline.sorted { $0.occurredAt < $1.occurredAt },
            editRequests: editRequests.sorted { $0.createdAt > $1.createdAt },
            pendingSyncCount: relatedPending
        )
    }

    private func fetchContentWithDirectoryRefreshIfNeeded() async throws -> OperatorWorkOrderDetailContent {
        do {
            return try await fetchContent()
        } catch let error as DomainError {
            guard shouldRefreshDirectory(after: error) else { throw error }
            await dependencies.localDirectoryCacheRefresh.refreshCustomers()
            await dependencies.localDirectoryCacheRefresh.refreshUsers()
            return try await fetchContent()
        }
    }

    private func shouldRefreshDirectory(after error: DomainError) -> Bool {
        guard case .notFound(let entity, _) = error else { return false }
        return entity == "Customer" || entity == "User"
    }
}

#if DEBUG
extension OperatorWorkOrderDetailViewModel {
    static func previewLoaded() -> OperatorWorkOrderDetailViewModel {
        let vm = OperatorWorkOrderDetailViewModel(
            workOrderId: WorkOrderID("wo-1024"),
            actor: OperatorPreviewData.operatorUser,
            dependencies: DIContainer.mock().makeOperatorDependencies()
        )
        let order = OperatorPreviewData.sampleWorkOrders[0]
        vm.phase = .loaded
        vm.content = OperatorWorkOrderDetailContent(
            workOrder: order,
            customer: OperatorPreviewData.customerABC,
            technicianName: OperatorPreviewData.technicianAhmet.fullName,
            notes: [],
            photos: [],
            locations: [],
            signatures: [],
            timeline: [
                WorkOrderStatusHistory(
                    id: "h1",
                    workOrderId: order.id,
                    fromStatus: nil,
                    toStatus: .assigned,
                    actorUserId: OperatorPreviewData.operatorUser.id,
                    occurredAt: OperatorPreviewData.referenceDate
                )
            ],
            editRequests: [],
            pendingSyncCount: 0
        )
        return vm
    }
}
#endif
