import Foundation
import Observation

struct AdminReportMetric: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let value: String
}

struct AdminStatusBreakdown: Identifiable, Equatable, Sendable {
    let id: String
    let status: WorkOrderStatus
    let count: Int
    let percentage: Double
}

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
    private(set) var metrics: [AdminReportMetric] = []
    private(set) var statusBreakdown: [AdminStatusBreakdown] = []

    private let actor: User
    private let dependencies: AdminDependencies

    init(kind: AdminReportKind, actor: User, dependencies: AdminDependencies) {
        self.kind = kind
        self.actor = actor
        self.dependencies = dependencies
    }

    func load() async {
        phase = .loading
        do {
            let orders = try await dependencies.getSystemWorkOrders.execute(actor: actor)
            switch kind {
            case .workOrders:
                buildWorkOrderReport(from: orders)
            case .technicianPerformance:
                buildTechnicianReport(from: orders)
            case .customerSummary:
                buildCustomerReport(from: orders)
            case .pauseReasons:
                buildPauseReasonReport(from: orders)
            case .signatures, .photos:
                buildAttachmentReport(kind: kind, orders: orders)
            }
            phase = metrics.isEmpty && statusBreakdown.isEmpty ? .empty : .loaded
        } catch let error as DomainError {
            phase = .error(error.adminMessage)
        } catch {
            phase = .error("Rapor yüklenemedi.")
        }
    }

    private func buildWorkOrderReport(from orders: [WorkOrder]) {
        let total = orders.count
        let completed = orders.filter { $0.status == .completed }.count
        let completionRate = total > 0 ? Double(completed) / Double(total) * 100 : 0

        metrics = [
            AdminReportMetric(id: "total", title: "Toplam İş Emri", value: "\(total)"),
            AdminReportMetric(id: "completed", title: "Tamamlanan", value: "\(completed)"),
            AdminReportMetric(id: "rate", title: "Tamamlanma Oranı", value: String(format: "%.0f%%", completionRate))
        ]

        statusBreakdown = WorkOrderStatus.allCases.compactMap { status in
            let count = orders.filter { $0.status == status }.count
            guard count > 0 else { return nil }
            let pct = total > 0 ? Double(count) / Double(total) * 100 : 0
            return AdminStatusBreakdown(
                id: status.rawValue,
                status: status,
                count: count,
                percentage: pct
            )
        }
    }

    private func buildTechnicianReport(from orders: [WorkOrder]) {
        var counts: [UserID: Int] = [:]
        for order in orders {
            counts[order.assignedTechnicianId, default: 0] += 1
        }
        metrics = counts.map { techId, count in
            AdminReportMetric(
                id: techId.rawValue,
                title: techId.rawValue,
                value: "\(count) iş emri"
            )
        }.sorted { $0.title < $1.title }
    }

    private func buildCustomerReport(from orders: [WorkOrder]) {
        let grouped = Dictionary(grouping: orders, by: \.customerId)
        metrics = grouped.map { customerId, items in
            AdminReportMetric(
                id: customerId.rawValue,
                title: customerId.rawValue,
                value: "\(items.count) iş emri"
            )
        }.sorted { $0.title < $1.title }
    }

    private func buildPauseReasonReport(from orders: [WorkOrder]) {
        let paused = orders.filter { $0.status == .paused }
        let grouped = Dictionary(grouping: paused.compactMap(\.currentPauseReason)) { $0 }
        metrics = grouped.map { reason, items in
            AdminReportMetric(
                id: reason.rawValue,
                title: reason.displayName,
                value: "\(items.count)"
            )
        }
        if metrics.isEmpty {
            metrics = PauseReason.allCases.map {
                AdminReportMetric(id: $0.rawValue, title: $0.displayName, value: "0")
            }
        }
    }

    private func buildAttachmentReport(kind: AdminReportKind, orders: [WorkOrder]) {
        let completed = orders.filter { $0.status == .completed }.count
        metrics = [
            AdminReportMetric(
                id: "completed",
                title: "Tamamlanan İş Emri",
                value: "\(completed)"
            ),
            AdminReportMetric(
                id: "hint",
                title: kind == .signatures ? "İmza Kayıtları" : "Fotoğraf Kayıtları",
                value: completed > 0 ? "Detay için iş emri raporuna bakın" : "Veri yok"
            )
        ]
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
        vm.metrics = [
            AdminReportMetric(id: "total", title: "Toplam İş Emri", value: "48"),
            AdminReportMetric(id: "completed", title: "Tamamlanan", value: "25"),
            AdminReportMetric(id: "rate", title: "Tamamlanma Oranı", value: "52%")
        ]
        vm.statusBreakdown = [
            AdminStatusBreakdown(id: "assigned", status: .assigned, count: 12, percentage: 25),
            AdminStatusBreakdown(id: "completed", status: .completed, count: 25, percentage: 52)
        ]
        return vm
    }
}
#endif
