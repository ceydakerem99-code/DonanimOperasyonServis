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
    private(set) var recentCompletedOrders: [WorkOrderCardData] = []
    let userFirstName: String

    private let actor: User
    private let dependencies: AdminDependencies
    private let asyncLoad = AsyncLoadSession()

    var showsLoadingIndicator: Bool { asyncLoad.showsLoadingIndicator }
    var hasCachedContent: Bool {
        summary.totalWorkOrders > 0
            || !recentCompletedOrders.isEmpty
            || !recentActivities.isEmpty
    }

    init(actor: User, dependencies: AdminDependencies) {
        self.actor = actor
        self.dependencies = dependencies
        self.userFirstName = actor.fullName.split(separator: " ").first.map(String.init) ?? actor.fullName
    }

    func load() async {
        let context = asyncLoad.start(hadCachedContent: hasCachedContent)
        if !context.hadCachedContentAtStart { phase = .loading }
        defer { asyncLoad.finish(generation: context.generation) }
        let generation = context.generation
        await dependencies.localDirectoryCacheRefresh.refreshUsers()
        do {
            let users = try await dependencies.listUsers.execute(actor: actor)
            let orders = try await dependencies.getSystemWorkOrders.execute(actor: actor)
            let now = Date()
            let pending = try await dependencies.syncOperationRepository.countPending(now: now)
            let issueSnapshot = try await dependencies.syncManager.issueSnapshot()
            let conflicts = try await dependencies.syncConflictRepository.listUnresolved()
            let online = await dependencies.networkReachability.isReachable

            guard asyncLoad.isCurrent(generation) else { return }
            let customers = await loadCustomerMap(for: orders)
            let technicians = await loadTechnicianMap(for: orders)
            summary = Self.makeSummary(
                users: users,
                orders: orders,
                pendingSync: pending,
                failedSync: issueSnapshot.activeFailedCount,
                unresolvedConflicts: conflicts.count,
                isOnline: online
            )
            recentActivities = Self.makeActivities(from: orders)
            recentCompletedOrders = Self.makeRecentCompletedCards(
                from: orders,
                customers: customers,
                technicians: technicians
            )

            phase = users.isEmpty && orders.isEmpty ? .empty : .loaded
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
            if hasCachedContent {
                phase = .loaded
            } else {
                phase = .error(error.adminMessage)
            }
        } catch {
            guard asyncLoad.isCurrent(generation) else { return }
            if hasCachedContent {
                phase = .loaded
            } else {
                phase = .error("Veriler yüklenemedi.")
            }
        }
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

    static func makeRecentCompletedCards(
        from orders: [WorkOrder],
        customers: [CustomerID: Customer],
        technicians: [UserID: User],
        limit: Int = 5
    ) -> [WorkOrderCardData] {
        orders
            .filter { $0.status == .completed }
            .sorted {
                ($0.completedAt ?? $0.updatedAt) > ($1.completedAt ?? $1.updatedAt)
            }
            .prefix(limit)
            .map { order in
                WorkOrderPresentationMapping.cardData(
                    from: order,
                    customerName: customers[order.customerId]?.name ?? "Bilinmeyen müşteri",
                    technicianName: technicians[order.assignedTechnicianId]?.fullName
                )
            }
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
