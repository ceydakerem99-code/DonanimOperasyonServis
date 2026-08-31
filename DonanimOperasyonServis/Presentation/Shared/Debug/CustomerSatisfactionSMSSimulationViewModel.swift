#if DEBUG
import Foundation
import Observation

struct CompletedWorkOrderSurveyOption: Identifiable, Equatable, Sendable {
    let id: WorkOrderID
    let workOrderNumber: String
    let customerName: String
    let customerPhone: String?
    let satisfactionId: CustomerSatisfactionID

    var smsPreviewContent: CustomerSatisfactionSMSPreviewContent {
        CustomerSatisfactionSurveySMS.previewContent(
            customerName: customerName,
            workOrderNumber: workOrderNumber,
            satisfactionId: satisfactionId
        )
    }
}

enum CustomerSatisfactionSMSSimulationCopy {
    static func surveyRoute(for satisfactionId: CustomerSatisfactionID) -> String {
        CustomerSatisfactionSurveySMS.surveyLink(for: satisfactionId)
    }

    static func message(
        customerName: String,
        workOrderNumber: String,
        satisfactionId: CustomerSatisfactionID
    ) -> String {
        CustomerSatisfactionSurveySMS.messageBody(
            customerName: customerName,
            workOrderNumber: workOrderNumber,
            satisfactionId: satisfactionId
        )
    }
}

@Observable
@MainActor
final class CustomerSatisfactionSMSSimulationViewModel {
    private(set) var options: [CompletedWorkOrderSurveyOption] = []
    private(set) var isLoading = false
    private(set) var loadError: String?
    private(set) var deliveryError: String?
    private(set) var isSending = false
    var selectedOrderId: WorkOrderID?

    var selectedOption: CompletedWorkOrderSurveyOption? {
        guard let selectedOrderId else { return nil }
        return options.first { $0.id == selectedOrderId }
    }

    var showsSentStatus: Bool {
        guard let selectedOption else { return false }
        return CustomerSatisfactionSMSSimulator.wasSent(satisfactionId: selectedOption.satisfactionId)
    }

    func load(container: DIContainer) async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }

        do {
            let orders = try await container.workOrderRepository.list(
                filter: WorkOrderFilter(status: .completed)
            )
            let customers = try await container.customerRepository.list(searchText: nil)
            let customersById = Dictionary(uniqueKeysWithValues: customers.map { ($0.id, $0) })

            var loaded: [CompletedWorkOrderSurveyOption] = []
            for order in orders.sorted(by: Self.sortNewestFirst) {
                let satisfactions = try await container.customerSatisfactionRepository.list(for: order.id)
                guard let pending = satisfactions.first(where: { $0.status == .pending }) else { continue }
                let customer = customersById[order.customerId]
                loaded.append(
                    CompletedWorkOrderSurveyOption(
                        id: order.id,
                        workOrderNumber: order.workOrderNumber,
                        customerName: customer?.name ?? "Bilinmeyen müşteri",
                        customerPhone: customer?.phoneNumber?.rawValue,
                        satisfactionId: pending.id
                    )
                )
            }

            options = loaded
            if let selectedOrderId,
               !loaded.contains(where: { $0.id == selectedOrderId }) {
                self.selectedOrderId = loaded.first?.id
            } else if selectedOrderId == nil {
                selectedOrderId = loaded.first?.id
            }
            if loaded.isEmpty {
                loadError = "Pending müşteri memnuniyeti kaydı olan tamamlanmış iş emri bulunamadı. Önce bir iş emrini tamamlayın."
            }
        } catch {
            loadError = "Tamamlanan iş emirleri yüklenemedi."
            options = []
        }
    }

    func selectOrder(_ orderId: WorkOrderID) {
        selectedOrderId = orderId
    }

    /// A test SMS must obey the same invariant as production delivery: its
    /// token is never exposed until the exact satisfaction document exists
    /// in the remote store used by the web survey.
    func resimulateSendSMS(container: DIContainer) async {
        guard let option = selectedOption else { return }
        isSending = true
        deliveryError = nil
        defer { isSending = false }
        do {
            guard await container.networkReachability.isReachable else {
                deliveryError = "Bağlantı yok. Değerlendirme kaydı senkronize edilince SMS gönderilecek."
                return
            }
            _ = try await container.syncManager.syncPending()
            let remote = try await container.remoteCustomerSatisfactionRepository.fetch(
                id: option.satisfactionId
            )
            guard remote.id == option.satisfactionId else {
                deliveryError = "Değerlendirme kaydı doğrulanamadı."
                return
            }
            CustomerSatisfactionSMSSimulator.simulateSend(
                customerName: option.customerName,
                workOrderNumber: option.workOrderNumber,
                satisfactionId: option.satisfactionId,
                recipientPhone: option.customerPhone
            )
        } catch {
            deliveryError = "Değerlendirme kaydı henüz sunucuya ulaşmadı; SMS gönderilmedi."
        }
    }

    private static func sortNewestFirst(_ lhs: WorkOrder, _ rhs: WorkOrder) -> Bool {
        let left = lhs.completedAt ?? lhs.updatedAt
        let right = rhs.completedAt ?? rhs.updatedAt
        return left > right
    }
}
#endif
