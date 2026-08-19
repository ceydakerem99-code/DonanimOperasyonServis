import Foundation
import Observation

struct AdminWorkOrderReportContent: Equatable, Sendable {
    let workOrder: WorkOrder
    let customerName: String
    let noteCount: Int
    let signatureCount: Int
    let photoCount: Int
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

    private let workOrderId: WorkOrderID
    private let actor: User
    private let dependencies: AdminDependencies

    init(workOrderId: WorkOrderID, actor: User, dependencies: AdminDependencies) {
        self.workOrderId = workOrderId
        self.actor = actor
        self.dependencies = dependencies
    }

    func load() async {
        phase = .loading
        do {
            let order = try await dependencies.getSystemWorkOrder.execute(actor: actor, id: workOrderId)
            let customerName = (try? await dependencies.customerRepository.fetch(id: order.customerId))?.name
                ?? "Bilinmeyen müşteri"
            let notes = try await dependencies.workOrderNoteRepository.list(for: order.id)
            let signatures = (try? await dependencies.signatureRepository.list(for: order.id)) ?? []
            let photos = (try? await dependencies.workOrderPhotoRepository.list(for: order.id)) ?? []
            content = AdminWorkOrderReportContent(
                workOrder: order,
                customerName: customerName,
                noteCount: notes.count,
                signatureCount: signatures.count,
                photoCount: photos.count
            )
            phase = .loaded
        } catch is CancellationError {
            return
        } catch let error as DomainError {
            phase = .error(error.adminMessage)
        } catch {
            phase = .error("Rapor yüklenemedi.")
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
        vm.content = AdminWorkOrderReportContent(
            workOrder: WorkOrder(
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
            ),
            customerName: "ABC Market",
            noteCount: 3,
            signatureCount: 1,
            photoCount: 2
        )
        return vm
    }
}
#endif
