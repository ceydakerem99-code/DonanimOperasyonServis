import Foundation
import Observation

struct OperatorWorkOrderDetailContent: Equatable, Sendable {
    let workOrder: WorkOrder
    let customer: Customer
    let technicianName: String
    let notes: [WorkOrderNote]
    let timeline: [WorkOrderStatusHistory]
    let pendingSyncCount: Int
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

    let workOrderId: WorkOrderID
    private let actor: User
    private let dependencies: OperatorDependencies

    init(workOrderId: WorkOrderID, actor: User, dependencies: OperatorDependencies) {
        self.workOrderId = workOrderId
        self.actor = actor
        self.dependencies = dependencies
    }

    func load() async {
        phase = .loading
        do {
            let order = try await dependencies.getWorkOrder.execute(actor: actor, id: workOrderId)
            let customer = try await dependencies.customerRepository.fetch(id: order.customerId)
            let technician = try await dependencies.userRepository.fetch(id: order.assignedTechnicianId)
            let notes = try await dependencies.workOrderNoteRepository.list(for: order.id)
            let timeline = try await dependencies.statusHistoryRepository.list(for: order.id)
            let pendingOps = try await dependencies.syncOperationRepository.list(
                entityType: .workOrder,
                entityId: order.id.rawValue
            )
            let relatedPending = pendingOps.filter { $0.status == .pending || $0.status == .failed }.count

            content = OperatorWorkOrderDetailContent(
                workOrder: order,
                customer: customer,
                technicianName: technician.fullName,
                notes: notes,
                timeline: timeline.sorted { $0.occurredAt < $1.occurredAt },
                pendingSyncCount: relatedPending
            )
            phase = .loaded
        } catch let error as DomainError {
            phase = .error(error.operatorMessage)
        } catch {
            phase = .error("İş emri detayı yüklenemedi.")
        }
    }

    func attemptEdit() {
        guard let order = content?.workOrder else { return }
        if order.status.isTerminal {
            editBlockedMessage = DomainError.workOrderLocked(order.id).operatorMessage
        } else {
            editBlockedMessage = "Aktif iş emirleri doğrudan düzenlenemez. Tamamlanan iş emirleri için düzenleme talebi süreci kullanılır."
        }
    }

    func clearEditMessage() {
        editBlockedMessage = nil
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
            pendingSyncCount: 0
        )
        return vm
    }
}
#endif
