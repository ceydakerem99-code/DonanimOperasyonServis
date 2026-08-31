import XCTest
@testable import DonanimOperasyonServis

@MainActor
final class ReportLifecycleTests: XCTestCase {

    private func makeAdminDependencies(from container: DIContainer) -> AdminDependencies {
        container.makeAdminDependencies()
    }

    private func makeOperatorDependencies(from container: DIContainer) -> OperatorDependencies {
        container.makeOperatorDependencies()
    }

    private func seedReportData(
        container: DIContainer,
        deps: AdminDependencies,
        admin: User
    ) async throws {
        let customer = DomainFixtures.customer()
        try await deps.userRepository.save(admin)
        try await deps.customerRepository.save(customer)
        try await container.workOrderRepository.save(
            DomainFixtures.workOrder(customerId: customer.id, status: .completed)
        )
        try await container.workOrderRepository.save(
            DomainFixtures.workOrder(
                id: WorkOrderID("wo-assigned"),
                customerId: customer.id,
                status: .assigned
            )
        )
    }

    func testAllAdminReportKindsSettleAfterCancellation() async throws {
        let container = DIContainer.mock()
        let deps = makeAdminDependencies(from: container)
        let admin = DomainFixtures.adminUser()
        try await seedReportData(container: container, deps: deps, admin: admin)

        for kind in AdminReportKind.allCases {
            let vm = AdminReportDetailViewModel(kind: kind, actor: admin, dependencies: deps)
            let task = Task { await vm.load() }
            task.cancel()
            await task.value
            XCTAssertNotEqual(vm.phase, .loading, "Admin \(kind) should not remain loading after cancel")
        }
    }

    func testAllOperatorReportKindsSettleAfterCancellation() async throws {
        let container = DIContainer.mock()
        let deps = makeOperatorDependencies(from: container)
        let operatorUser = DomainFixtures.operatorUser()
        let customer = DomainFixtures.customer()
        try await deps.userRepository.save(operatorUser)
        try await deps.customerRepository.save(customer)
        try await container.workOrderRepository.save(
            DomainFixtures.workOrder(customerId: customer.id, status: .completed)
        )

        for kind in AdminReportKind.allCases {
            let vm = OperatorReportDetailViewModel(kind: kind, actor: operatorUser, dependencies: deps)
            let task = Task { await vm.load() }
            task.cancel()
            await task.value
            XCTAssertNotEqual(vm.phase, .loading, "Operator \(kind) should not remain loading after cancel")
        }
    }

    func testRepeatedAdminReportLoadRemainsStableAfterCancellation() async throws {
        let container = DIContainer.mock()
        let deps = makeAdminDependencies(from: container)
        let admin = DomainFixtures.adminUser()
        try await seedReportData(container: container, deps: deps, admin: admin)

        let vm = AdminReportDetailViewModel(kind: .workOrders, actor: admin, dependencies: deps)
        await vm.load()
        XCTAssertEqual(vm.phase, .loaded)

        let cancelled = Task { await vm.load() }
        cancelled.cancel()
        await cancelled.value
        XCTAssertNotEqual(vm.phase, .loading)
        XCTAssertEqual(vm.phase, .loaded)

        await vm.load()
        XCTAssertEqual(vm.phase, .loaded)
    }

    func testAdminWorkOrderReportCancellationSettlesLoading() async throws {
        let container = DIContainer.mock()
        let deps = makeAdminDependencies(from: container)
        let admin = DomainFixtures.adminUser()
        let order = DomainFixtures.workOrder(status: .completed)
        try await deps.userRepository.save(admin)
        try await container.workOrderRepository.save(order)

        let vm = AdminWorkOrderReportViewModel(workOrderId: order.id, actor: admin, dependencies: deps)
        let task = Task { await vm.load() }
        task.cancel()
        await task.value
        XCTAssertNotEqual(vm.phase, .loading)
    }

    func testReportListToDetailBackDoesNotRemainLoading() async throws {
        let container = DIContainer.mock()
        let deps = makeAdminDependencies(from: container)
        let admin = DomainFixtures.adminUser()
        try await seedReportData(container: container, deps: deps, admin: admin)

        let cache = AdminReportDetailViewModelCache(actor: admin, dependencies: deps)
        let panel = cache.viewModel(for: .workOrders)
        await panel.load()
        XCTAssertEqual(panel.phase, .loaded)

        let cancelled = Task { await panel.load() }
        cancelled.cancel()
        await cancelled.value
        XCTAssertNotEqual(panel.phase, .loading)
        XCTAssertEqual(panel.phase, .loaded)
    }

    func testReportDetailAToBBackIsStable() async throws {
        let container = DIContainer.mock()
        let deps = makeAdminDependencies(from: container)
        let admin = DomainFixtures.adminUser()
        let customer = DomainFixtures.customer()
        try await deps.userRepository.save(admin)
        try await deps.customerRepository.save(customer)

        let orderA = DomainFixtures.workOrder(
            id: WorkOrderID("wo-report-a"),
            workOrderNumber: "WO-A",
            customerId: customer.id,
            status: .completed
        )
        let orderB = DomainFixtures.workOrder(
            id: WorkOrderID("wo-report-b"),
            workOrderNumber: "WO-B",
            customerId: customer.id,
            status: .completed
        )
        try await container.workOrderRepository.save(orderA)
        try await container.workOrderRepository.save(orderB)

        let panelCache = AdminReportDetailViewModelCache(actor: admin, dependencies: deps)
        let panel = panelCache.viewModel(for: .signatures)
        await panel.load()
        XCTAssertEqual(panel.phase, .loaded)

        let detailA = AdminWorkOrderReportViewModel(workOrderId: orderA.id, actor: admin, dependencies: deps)
        await detailA.load()
        XCTAssertEqual(detailA.phase, .loaded)

        let detailB = AdminWorkOrderReportViewModel(workOrderId: orderB.id, actor: admin, dependencies: deps)
        await detailB.load()
        XCTAssertEqual(detailB.phase, .loaded)

        let popSimulation = Task { await panel.load() }
        popSimulation.cancel()
        await popSimulation.value
        XCTAssertNotEqual(panel.phase, .loading)
        XCTAssertEqual(panel.phase, .loaded)
        XCTAssertEqual(detailA.content?.snapshot.workOrder.id, orderA.id)
    }

    func testReportDetailAToBToCBackIsStable() async throws {
        let container = DIContainer.mock()
        let deps = makeAdminDependencies(from: container)
        let admin = DomainFixtures.adminUser()
        let customer = DomainFixtures.customer()
        try await deps.userRepository.save(admin)
        try await deps.customerRepository.save(customer)

        let orders = (1...3).map { index in
            DomainFixtures.workOrder(
                id: WorkOrderID("wo-report-\(index)"),
                workOrderNumber: "WO-\(index)",
                customerId: customer.id,
                status: .completed
            )
        }
        for order in orders {
            try await container.workOrderRepository.save(order)
        }

        let panel = AdminReportDetailViewModelCache(actor: admin, dependencies: deps)
            .viewModel(for: .workOrders)
        await panel.load()

        for order in orders {
            let detail = AdminWorkOrderReportViewModel(workOrderId: order.id, actor: admin, dependencies: deps)
            await detail.load()
            XCTAssertEqual(detail.phase, .loaded)
        }

        XCTAssertEqual(panel.phase, .loaded)
    }

    func testRepeatedReportPushPopDoesNotDuplicateLoad() async throws {
        let container = DIContainer.mock()
        let deps = makeAdminDependencies(from: container)
        let admin = DomainFixtures.adminUser()
        try await seedReportData(container: container, deps: deps, admin: admin)

        let cache = AdminReportDetailViewModelCache(actor: admin, dependencies: deps)
        let panel = cache.viewModel(for: .workOrders)

        for _ in 0..<3 {
            await panel.load()
            XCTAssertEqual(panel.phase, .loaded)
            let cancelled = Task { await panel.load() }
            cancelled.cancel()
            await cancelled.value
            XCTAssertNotEqual(panel.phase, .loading)
        }
    }

    func testCancelledReportLoadSettlesPhase() async throws {
        let container = DIContainer.mock()
        let deps = makeAdminDependencies(from: container)
        let admin = DomainFixtures.adminUser()
        try await seedReportData(container: container, deps: deps, admin: admin)

        let vm = AdminReportDetailViewModel(kind: .photos, actor: admin, dependencies: deps)
        let task = Task { await vm.load() }
        task.cancel()
        await task.value
        XCTAssertNotEqual(vm.phase, .loading)
    }

    func testChangingReportIDDoesNotReuseStaleDetailState() async throws {
        let container = DIContainer.mock()
        let deps = makeAdminDependencies(from: container)
        let admin = DomainFixtures.adminUser()
        let customer = DomainFixtures.customer()
        try await deps.userRepository.save(admin)
        try await deps.customerRepository.save(customer)

        let orderA = DomainFixtures.workOrder(
            id: WorkOrderID("wo-stale-a"),
            workOrderNumber: "WO-STALE-A",
            customerId: customer.id,
            status: .completed
        )
        let orderB = DomainFixtures.workOrder(
            id: WorkOrderID("wo-stale-b"),
            workOrderNumber: "WO-STALE-B",
            customerId: customer.id,
            status: .completed
        )
        try await container.workOrderRepository.save(orderA)
        try await container.workOrderRepository.save(orderB)

        let vmA = AdminWorkOrderReportViewModel(workOrderId: orderA.id, actor: admin, dependencies: deps)
        let vmB = AdminWorkOrderReportViewModel(workOrderId: orderB.id, actor: admin, dependencies: deps)
        await vmA.load()
        await vmB.load()

        XCTAssertEqual(vmA.content?.snapshot.workOrder.workOrderNumber, "WO-STALE-A")
        XCTAssertEqual(vmB.content?.snapshot.workOrder.workOrderNumber, "WO-STALE-B")
    }

    func testReportListCacheSurvivesChildDetailNavigation() async throws {
        let container = DIContainer.mock()
        let deps = makeAdminDependencies(from: container)
        let admin = DomainFixtures.adminUser()
        try await seedReportData(container: container, deps: deps, admin: admin)

        let cache = AdminReportDetailViewModelCache(actor: admin, dependencies: deps)
        let first = cache.viewModel(for: .workOrders)
        await first.load()
        let metricsBefore = first.metrics

        let detail = AdminWorkOrderReportViewModel(
            workOrderId: WorkOrderID("wo-assigned"),
            actor: admin,
            dependencies: deps
        )
        await detail.load()

        let second = cache.viewModel(for: .workOrders)
        XCTAssertTrue(first === second)
        XCTAssertEqual(second.phase, .loaded)
        XCTAssertEqual(second.metrics, metricsBefore)
    }

    func testNestedReportNavigationPathIsStable() {
        var router = AdminAppRouter(selectedTab: .reports)
        router.push(.reportDetail(.signatures))
        router.push(.workOrderReport(WorkOrderID("wo-a")))
        router.push(.workOrderReport(WorkOrderID("wo-b")))
        XCTAssertEqual(router.path.count, 3)

        router.path.removeLast()
        XCTAssertEqual(router.path.last, .workOrderReport(WorkOrderID("wo-a")))

        router.path.removeLast()
        XCTAssertEqual(router.path.last, .reportDetail(.signatures))

        router.popToRoot()
        XCTAssertTrue(router.path.isEmpty)
    }
}

@MainActor
final class SyncStatusBadgeRulesTests: XCTestCase {
    func testWaitingBadgeHiddenWhenZero() {
        XCTAssertFalse(SyncStatusBadgeRules.showsWaitingBadge(waitingCount: 0, hasError: false))
    }

    func testWaitingBadgeVisibleWhenPositive() {
        XCTAssertTrue(SyncStatusBadgeRules.showsWaitingBadge(waitingCount: 21, hasError: false))
    }

    func testErrorBadgeTakesPrecedenceOverWaitingCount() {
        XCTAssertFalse(SyncStatusBadgeRules.showsWaitingBadge(waitingCount: 21, hasError: true))
        XCTAssertTrue(SyncStatusBadgeRules.showsErrorBadge(hasError: true, errorCount: 2))
    }
}
