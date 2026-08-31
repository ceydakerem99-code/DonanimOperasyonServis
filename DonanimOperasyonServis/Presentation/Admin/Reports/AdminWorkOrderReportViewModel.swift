import Foundation
import Observation

struct AdminWorkOrderReportContent: Equatable, Sendable {
    let snapshot: WorkOrderReportSnapshot
}

@Observable
@MainActor
final class AdminWorkOrderReportViewModel {
    enum Phase: Equatable {
        case loading
        case loaded
        case error(String)
    }

    private(set) var phase: Phase = .loading
    private(set) var content: AdminWorkOrderReportContent?
    private(set) var pdfData: Data?
    private(set) var pdfFileURL: URL?
    private(set) var isExportingPDF = false
    private(set) var isDeleting = false
    private(set) var deleteError: String?
    var showsDeleteConfirmation = false

    private let workOrderId: WorkOrderID
    private let actor: User
    private let dependencies: AdminDependencies
    private let asyncLoad = AsyncLoadSession()

    var showsLoadingIndicator: Bool { asyncLoad.showsLoadingIndicator }
    var hasCachedContent: Bool { content != nil }

    var mediaLoader: WorkOrderMediaLoader {
        WorkOrderMediaLoader(storage: dependencies.storageDataSource)
    }

    var canDeleteWorkOrder: Bool {
        guard RoleAccessPolicy.can(.deleteWorkOrder, as: actor.role) else { return false }
        guard let status = content?.snapshot.workOrder.status else { return false }
        return status != .completed
    }

    var deleteConfirmationMessage: String {
        let number = content?.snapshot.workOrder.workOrderNumber ?? workOrderId.rawValue
        return "\(number) numaralı iş emri kalıcı olarak silinecek. Bu işlem geri alınamaz."
    }

    init(workOrderId: WorkOrderID, actor: User, dependencies: AdminDependencies) {
        self.workOrderId = workOrderId
        self.actor = actor
        self.dependencies = dependencies
    }

    func load() async {
        let context = asyncLoad.start(hadCachedContent: hasCachedContent)
        if !context.hadCachedContentAtStart { phase = .loading }
        defer { asyncLoad.finish(generation: context.generation) }
        let generation = context.generation
        if !context.hadCachedContentAtStart {
            pdfData = nil
            pdfFileURL = nil
        }
        do {
            guard RoleAccessPolicy.can(.viewSystemReports, as: actor.role)
                || RoleAccessPolicy.can(.viewServiceReport, as: actor.role)
            else {
                throw DomainError.unauthorized(action: .viewServiceReport)
            }
            let order = try await dependencies.getSystemWorkOrder.execute(actor: actor, id: workOrderId)
            guard asyncLoad.isCurrent(generation) else { return }
            let customer = try? await dependencies.customerRepository.fetch(id: order.customerId)
            let technicianName = (try? await dependencies.userRepository.fetch(id: order.assignedTechnicianId))?.fullName
            async let notesTask = dependencies.workOrderNoteRepository.list(for: order.id)
            async let signaturesTask = dependencies.signatureRepository.list(for: order.id)
            async let photosTask = dependencies.workOrderPhotoRepository.list(for: order.id)
            async let locationsTask = dependencies.workOrderLocationRepository.list(for: order.id)
            async let timelineTask = dependencies.statusHistoryRepository.list(for: order.id)
            async let editRequestsTask = dependencies.editRequestRepository.list(for: order.id)
            let notes = try await notesTask
            let signatures = (try? await signaturesTask) ?? []
            let photos = (try? await photosTask) ?? []
            let locations = (try? await locationsTask) ?? []
            let timeline = (try? await timelineTask) ?? []
            let editRequests = (try? await editRequestsTask) ?? []

            guard asyncLoad.isCurrent(generation) else { return }
            let snapshot = WorkOrderReportSnapshot(
                workOrder: order,
                customerName: customer?.name ?? "Bilinmeyen müşteri",
                customerAddress: customer.map { [$0.address, $0.city].compactMap { $0 }.joined(separator: ", ") },
                technicianName: technicianName,
                notes: notes.sorted { $0.createdAt > $1.createdAt },
                photos: photos.sorted { $0.capturedAt > $1.capturedAt },
                locations: locations.sorted { $0.capturedAt > $1.capturedAt },
                signatures: signatures.sorted { $0.capturedAt > $1.capturedAt },
                timeline: timeline.sorted { $0.occurredAt < $1.occurredAt },
                editRequests: editRequests.sorted { $0.createdAt > $1.createdAt }
            )
            content = AdminWorkOrderReportContent(snapshot: snapshot)
            phase = .loaded
        } catch is CancellationError {
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
            phase = .error(error.adminMessage)
        } catch {
            guard asyncLoad.isCurrent(generation) else { return }
            phase = .error("Rapor yüklenemedi.")
        }
    }

    func exportPDF() async {
        guard let snapshot = content?.snapshot, !isExportingPDF else { return }
        isExportingPDF = true
        defer { isExportingPDF = false }
        let media = await WorkOrderReportPDFExporter.collectMedia(
            snapshot: snapshot,
            loader: mediaLoader
        )
        let data = WorkOrderReportPDFExporter.makePDF(snapshot: snapshot, media: media)
        pdfData = data
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(snapshot.workOrder.workOrderNumber)-rapor.pdf")
        try? data.write(to: url, options: .atomic)
        pdfFileURL = url
    }

    func requestDeleteConfirmation() {
        deleteError = nil
        showsDeleteConfirmation = true
    }

    func cancelDeleteConfirmation() {
        showsDeleteConfirmation = false
    }

    /// Returns `true` when deletion succeeded and the caller should navigate back.
    func confirmDelete() async -> Bool {
        guard canDeleteWorkOrder else {
            deleteError = DomainError.unauthorized(action: .deleteWorkOrder).adminMessage
            showsDeleteConfirmation = false
            return false
        }

        isDeleting = true
        deleteError = nil
        defer {
            isDeleting = false
            showsDeleteConfirmation = false
        }

        do {
            try await dependencies.workOrderService.deleteWithSync(
                actor: actor,
                orderId: workOrderId
            )
            content = nil
            phase = .error("İş emri silindi.")
            return true
        } catch let error as DomainError {
            deleteError = error.adminMessage
            return false
        } catch {
            deleteError = "İş emri silinemedi."
            return false
        }
    }
}

#if DEBUG
extension AdminWorkOrderReportViewModel {
    static func previewLoaded() -> AdminWorkOrderReportViewModel {
        let vm = AdminWorkOrderReportViewModel(
            workOrderId: WorkOrderID("wo-preview"),
            actor: AdminPreviewData.adminUser,
            dependencies: DIContainer.mock().makeAdminDependencies()
        )
        vm.phase = .loaded
        let order = WorkOrder(
            id: WorkOrderID("wo-preview"),
            workOrderNumber: "WO-1026",
            createdByUserId: AdminPreviewData.operatorUser.id,
            assignedTechnicianId: AdminPreviewData.technicianUser.id,
            customerId: CustomerID("cust-1"),
            workType: .repair,
            deviceCategory: .pos,
            deviceBrand: "Ingenico",
            deviceModel: "iCT250",
            serialNumber: "SN-001",
            priority: .normal,
            scheduledDate: AdminPreviewData.referenceDate,
            status: .completed,
            createdAt: AdminPreviewData.referenceDate,
            updatedAt: AdminPreviewData.referenceDate,
            completedAt: AdminPreviewData.referenceDate
        )
        vm.content = AdminWorkOrderReportContent(
            snapshot: WorkOrderReportSnapshot(
                workOrder: order,
                customerName: "ABC Market",
                customerAddress: "Merkez, Çorum",
                technicianName: AdminPreviewData.technicianUser.fullName,
                notes: [],
                photos: [],
                locations: [],
                signatures: [],
                timeline: []
            )
        )
        return vm
    }
}
#endif
