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

struct AdminReportRelatedWorkOrder: Identifiable, Equatable, Sendable {
    let id: WorkOrderID
    let workOrderNumber: String
    let subtitle: String
    let count: Int
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
    private(set) var relatedWorkOrders: [AdminReportRelatedWorkOrder] = []

    private let actor: User
    private let dependencies: AdminDependencies

    init(kind: AdminReportKind, actor: User, dependencies: AdminDependencies) {
        self.kind = kind
        self.actor = actor
        self.dependencies = dependencies
    }

    func load() async {
        phase = .loading
        relatedWorkOrders = []
        do {
            let orders = try await dependencies.getSystemWorkOrders.execute(actor: actor)
            switch kind {
            case .workOrders:
                buildWorkOrderReport(from: orders)
            case .technicianPerformance:
                await buildTechnicianReport(from: orders)
            case .customerSummary:
                await buildCustomerReport(from: orders)
            case .pauseReasons:
                buildPauseReasonReport(from: orders)
            case .signatures:
                await buildAttachmentReport(kind: .signatures, orders: orders)
            case .photos:
                await buildAttachmentReport(kind: .photos, orders: orders)
            }
            phase = metrics.isEmpty && statusBreakdown.isEmpty && relatedWorkOrders.isEmpty ? .empty : .loaded
        } catch is CancellationError {
            return
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

        relatedWorkOrders = orders
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(20)
            .map {
                AdminReportRelatedWorkOrder(
                    id: $0.id,
                    workOrderNumber: $0.workOrderNumber,
                    subtitle: $0.status.displayName,
                    count: 0
                )
            }
    }

    private func buildTechnicianReport(from orders: [WorkOrder]) async {
        var counts: [UserID: Int] = [:]
        var statusByTech: [UserID: [WorkOrderStatus: Int]] = [:]
        for order in orders {
            counts[order.assignedTechnicianId, default: 0] += 1
            statusByTech[order.assignedTechnicianId, default: [:]][order.status, default: 0] += 1
        }

        var built: [AdminReportMetric] = []
        for (techId, count) in counts.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
            let name = (try? await dependencies.userRepository.fetch(id: techId))?.fullName ?? techId.rawValue
            let statusSummary = (statusByTech[techId] ?? [:])
                .sorted { $0.key.rawValue < $1.key.rawValue }
                .map { "\($0.key.displayName):\($0.value)" }
                .joined(separator: " · ")
            built.append(
                AdminReportMetric(
                    id: techId.rawValue,
                    title: name,
                    value: statusSummary.isEmpty ? "\(count) iş emri" : "\(count) · \(statusSummary)"
                )
            )
        }
        metrics = built
        statusBreakdown = WorkOrderStatus.allCases.compactMap { status in
            let count = orders.filter { $0.status == status }.count
            guard count > 0 else { return nil }
            let pct = orders.isEmpty ? 0 : Double(count) / Double(orders.count) * 100
            return AdminStatusBreakdown(
                id: status.rawValue,
                status: status,
                count: count,
                percentage: pct
            )
        }
    }

    private func buildCustomerReport(from orders: [WorkOrder]) async {
        let grouped = Dictionary(grouping: orders, by: \.customerId)
        var built: [AdminReportMetric] = []
        for (customerId, items) in grouped.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
            let name = (try? await dependencies.customerRepository.fetch(id: customerId))?.name ?? customerId.rawValue
            built.append(
                AdminReportMetric(
                    id: customerId.rawValue,
                    title: name,
                    value: "\(items.count) iş emri"
                )
            )
        }
        metrics = built
    }

    private func buildPauseReasonReport(from orders: [WorkOrder]) {
        let paused = orders.filter { $0.status == .paused }
        let grouped = Dictionary(grouping: paused.compactMap(\.currentPauseReason)) { $0 }
        metrics = PauseReason.allCases.map { reason in
            let count = grouped[reason]?.count ?? 0
            return AdminReportMetric(
                id: reason.rawValue,
                title: reason.displayName,
                value: "\(count)"
            )
        }
    }

    private func buildAttachmentReport(kind: AdminReportKind, orders: [WorkOrder]) async {
        let completed = orders.filter { $0.status == .completed }
        var totalAttachments = 0
        var related: [AdminReportRelatedWorkOrder] = []

        for order in completed {
            let count: Int
            if kind == .signatures {
                count = (try? await dependencies.signatureRepository.list(for: order.id))?.count ?? 0
            } else {
                count = (try? await dependencies.workOrderPhotoRepository.list(for: order.id))?.count ?? 0
            }
            totalAttachments += count
            if count > 0 {
                related.append(
                    AdminReportRelatedWorkOrder(
                        id: order.id,
                        workOrderNumber: order.workOrderNumber,
                        subtitle: kind == .signatures ? "İmza" : "Fotoğraf",
                        count: count
                    )
                )
            }
        }

        metrics = [
            AdminReportMetric(
                id: "completed",
                title: "Tamamlanan İş Emri",
                value: "\(completed.count)"
            ),
            AdminReportMetric(
                id: "attachments",
                title: kind == .signatures ? "Toplam İmza" : "Toplam Fotoğraf",
                value: "\(totalAttachments)"
            )
        ]
        if related.isEmpty {
            metrics.append(
                AdminReportMetric(
                    id: "hint",
                    title: "Durum",
                    value: completed.isEmpty ? "Tamamlanan iş emri yok" : "Kayıt bulunamadı"
                )
            )
        }
        relatedWorkOrders = related.sorted { $0.workOrderNumber < $1.workOrderNumber }
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
