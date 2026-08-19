import Foundation
import Observation

struct AdminDashboardSummary: Equatable, Sendable {
    var adminCount = 0
    var operatorCount = 0
    var technicianCount = 0
    var totalWorkOrders = 0
    var assigned = 0
    var inProgress = 0
    var paused = 0
    var completed = 0
    var pendingSync = 0
    var failedSync = 0
    var unresolvedConflicts = 0
    var isOnline = true
}

struct AdminActivityItem: Identifiable, Equatable, Sendable {
    let id: String
    let time: String
    let title: String
    let subtitle: String
}

@Observable
@MainActor
final class AdminDashboardViewModel {
    enum Phase: Equatable {
        case loading
        case loaded
        case empty
        case error(String)
    }

    private(set) var phase: Phase = .loading
    private(set) var summary = AdminDashboardSummary()
    private(set) var recentActivities: [AdminActivityItem] = []
    private(set) var alerts: [String] = []
    let userFirstName: String

    private let actor: User
    private let dependencies: AdminDependencies

    init(actor: User, dependencies: AdminDependencies) {
        self.actor = actor
        self.dependencies = dependencies
        self.userFirstName = actor.fullName.split(separator: " ").first.map(String.init) ?? actor.fullName
    }

    func load() async {
        phase = .loading
        do {
            let users = try await dependencies.listUsers.execute(actor: actor)
            let orders = try await dependencies.getSystemWorkOrders.execute(actor: actor)
            let now = Date()
            let pending = try await dependencies.syncOperationRepository.countPending(now: now)
            let failed = try await dependencies.syncOperationRepository.fetchFailed()
            let conflicts = try await dependencies.syncConflictRepository.listUnresolved()
            let online = await dependencies.networkReachability.isReachable

            summary = Self.makeSummary(
                users: users,
                orders: orders,
                pendingSync: pending,
                failedSync: failed.count,
                unresolvedConflicts: conflicts.count,
                isOnline: online
            )
            recentActivities = Self.makeActivities(from: orders)
            alerts = Self.makeAlerts(
                failedSync: failed.count,
                unresolvedConflicts: conflicts.count,
                isOnline: online
            )

            phase = users.isEmpty && orders.isEmpty ? .empty : .loaded
        } catch let error as DomainError {
            phase = .error(error.adminMessage)
        } catch {
            phase = .error("Veriler yüklenemedi.")
        }
    }

    private static func makeSummary(
        users: [User],
        orders: [WorkOrder],
        pendingSync: Int,
        failedSync: Int,
        unresolvedConflicts: Int,
        isOnline: Bool
    ) -> AdminDashboardSummary {
        var summary = AdminDashboardSummary()
        summary.adminCount = users.filter { $0.role == .admin && $0.isActive }.count
        summary.operatorCount = users.filter { $0.role == .operator && $0.isActive }.count
        summary.technicianCount = users.filter { $0.role == .technician && $0.isActive }.count
        summary.totalWorkOrders = orders.count
        summary.assigned = orders.filter { $0.status == .assigned }.count
        summary.inProgress = orders.filter { [.accepted, .enRoute, .arrived, .inProgress].contains($0.status) }.count
        summary.paused = orders.filter { $0.status == .paused }.count
        summary.completed = orders.filter { $0.status == .completed }.count
        summary.pendingSync = pendingSync
        summary.failedSync = failedSync
        summary.unresolvedConflicts = unresolvedConflicts
        summary.isOnline = isOnline
        return summary
    }

    private static func makeActivities(from orders: [WorkOrder]) -> [AdminActivityItem] {
        orders
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(5)
            .map { order in
                AdminActivityItem(
                    id: order.id.rawValue,
                    time: WorkOrderPresentationMapping.formatTime(order.updatedAt),
                    title: "\(order.workOrderNumber) — \(order.status.displayName)",
                    subtitle: order.workType.displayName
                )
            }
    }

    private static func makeAlerts(
        failedSync: Int,
        unresolvedConflicts: Int,
        isOnline: Bool
    ) -> [String] {
        var alerts: [String] = []
        if !isOnline {
            alerts.append("Cihaz çevrimdışı. Senkron işlemleri bekliyor.")
        }
        if failedSync > 0 {
            alerts.append("\(failedSync) başarısız senkron işlemi var.")
        }
        if unresolvedConflicts > 0 {
            alerts.append("\(unresolvedConflicts) çözülmemiş çakışma var (operasyon yetkilisi çözer).")
        }
        return alerts
    }
}

#if DEBUG
extension AdminDashboardViewModel {
    static func previewLoaded() -> AdminDashboardViewModel {
        let vm = AdminDashboardViewModel(
            actor: AdminPreviewData.adminUser,
            dependencies: DIContainer.mock().makeAdminDependencies()
        )
        vm.phase = .loaded
        vm.summary = AdminDashboardSummary(
            adminCount: 2,
            operatorCount: 6,
            technicianCount: 24,
            totalWorkOrders: 48,
            assigned: 12,
            inProgress: 8,
            paused: 3,
            completed: 25
        )
        vm.recentActivities = [
            AdminActivityItem(id: "1", time: "14:30", title: "WO-1026 — Tamamlandı", subtitle: "Arıza"),
            AdminActivityItem(id: "2", time: "13:15", title: "WO-1025 — İşlemde", subtitle: "Kurulum")
        ]
        return vm
    }

    static func previewEmpty() -> AdminDashboardViewModel {
        let vm = AdminDashboardViewModel(
            actor: AdminPreviewData.adminUser,
            dependencies: DIContainer.mock().makeAdminDependencies()
        )
        vm.phase = .empty
        return vm
    }

    static func previewError() -> AdminDashboardViewModel {
        let vm = AdminDashboardViewModel(
            actor: AdminPreviewData.adminUser,
            dependencies: DIContainer.mock().makeAdminDependencies()
        )
        vm.phase = .error("Veriler yüklenemedi.")
        return vm
    }
}
#endif
