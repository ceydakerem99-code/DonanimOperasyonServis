import XCTest
@testable import DonanimOperasyonServis

@MainActor
final class FinalQAFixTests: XCTestCase {

    // MARK: - Customer analytics cards

    func testCustomerCardsAreSeparated() async throws {
        let container = DIContainer.mock()
        let deps = container.makeAdminDependencies()
        let admin = DomainFixtures.adminUser()
        let customerA = DomainFixtures.customer(id: CustomerID("cust-a"), name: "ABC Market")
        let customerB = DomainFixtures.customer(id: CustomerID("cust-b"), name: "XYZ Ltd")
        try await deps.userRepository.save(admin)
        try await deps.customerRepository.save(customerA)
        try await deps.customerRepository.save(customerB)
        try await container.workOrderRepository.save(
            DomainFixtures.workOrder(id: WorkOrderID("wo-a"), customerId: customerA.id, status: .completed)
        )
        try await container.workOrderRepository.save(
            DomainFixtures.workOrder(id: WorkOrderID("wo-b"), customerId: customerB.id, status: .assigned)
        )

        let vm = CustomerAnalyticsViewModel(actor: admin, dependencies: deps)
        await vm.load()

        XCTAssertEqual(vm.customerPickerCards.count, 2)
        XCTAssertEqual(Set(vm.customerPickerCards.map(\.id)).count, 2)
        XCTAssertTrue(vm.customerPickerCards.allSatisfy { !$0.shortSummary.isEmpty })
        XCTAssertTrue(vm.customerPickerCards.allSatisfy { $0.totalVisits >= 0 })
    }

    // MARK: - Dashboard recent completed

    func testRecentCompletedOrdersSortedNewestFirst() async throws {
        let container = DIContainer.mock()
        let deps = container.makeAdminDependencies()
        let admin = DomainFixtures.adminUser()
        let customer = DomainFixtures.customer()
        let tech = DomainFixtures.technicianUser()
        let older = DomainFixtures.workOrder(
            id: WorkOrderID("wo-old"),
            assignedTechnicianId: tech.id,
            customerId: customer.id,
            status: .completed,
            completedAt: DomainFixtures.referenceDate
        )
        let newer = DomainFixtures.workOrder(
            id: WorkOrderID("wo-new"),
            workOrderNumber: "WO-NEW",
            assignedTechnicianId: tech.id,
            customerId: customer.id,
            status: .completed,
            completedAt: DomainFixtures.referenceDate.addingTimeInterval(7200)
        )
        try await deps.userRepository.save(admin)
        try await deps.userRepository.save(tech)
        try await deps.customerRepository.save(customer)
        try await container.workOrderRepository.save(older)
        try await container.workOrderRepository.save(newer)

        let vm = AdminDashboardViewModel(actor: admin, dependencies: deps)
        await vm.load()

        XCTAssertEqual(vm.recentCompletedOrders.first?.workOrderNumber, "WO-NEW")
        XCTAssertEqual(vm.recentCompletedOrders.last?.workOrderNumber, "WO-0001")
    }

    // MARK: - Local work order search

    func testWorkOrderSearchMatchesCustomer() async throws {
        let cards = try await searchCards(matching: "Ceka")
        XCTAssertEqual(cards.count, 1)
        XCTAssertEqual(cards.first?.customerName, "Ceka Market")
    }

    func testWorkOrderSearchMatchesTechnician() async throws {
        let cards = try await searchCards(matching: "Mehmet")
        XCTAssertEqual(cards.count, 1)
        XCTAssertEqual(cards.first?.technicianName, "Mehmet Kerem")
    }

    func testWorkOrderSearchMatchesWorkplace() async throws {
        let cards = try await searchCards(matching: "Bağdat")
        XCTAssertEqual(cards.count, 1)
        XCTAssertEqual(cards.first?.customerName, "Ceka Market")
    }

    private func searchCards(matching query: String) async throws -> [WorkOrderCardData] {
        let container = DIContainer.mock()
        let deps = container.makeOperatorDependencies()
        let operatorUser = DomainFixtures.operatorUser()
        let customer = Customer(
            id: CustomerID("cust-ceka"),
            name: "Ceka Market",
            address: "Bağdat Cad. No:1",
            city: "İstanbul",
            createdByUserId: operatorUser.id,
            createdAt: DomainFixtures.referenceDate,
            updatedAt: DomainFixtures.referenceDate
        )
        let tech = DomainFixtures.technicianUser(fullName: "Mehmet Kerem")
        let otherTech = DomainFixtures.technicianUser(
            id: UserID("user-tech-other"),
            fullName: "Ayşe Demir"
        )
        try await deps.userRepository.save(operatorUser)
        try await deps.customerRepository.save(customer)
        try await deps.userRepository.save(tech)
        try await deps.userRepository.save(otherTech)
        try await container.workOrderRepository.save(
            DomainFixtures.workOrder(
                id: WorkOrderID("wo-search"),
                workOrderNumber: "WO-SEARCH",
                assignedTechnicianId: tech.id,
                customerId: customer.id
            )
        )
        try await container.workOrderRepository.save(
            DomainFixtures.workOrder(
                id: WorkOrderID("wo-other"),
                workOrderNumber: "WO-OTHER",
                assignedTechnicianId: otherTech.id,
                customerId: DomainFixtures.customer(id: CustomerID("cust-other"), name: "Other Shop").id
            )
        )
        try await deps.customerRepository.save(
            Customer(
                id: CustomerID("cust-other"),
                name: "Other Shop",
                address: "Ankara Cad.",
                createdByUserId: operatorUser.id,
                createdAt: DomainFixtures.referenceDate,
                updatedAt: DomainFixtures.referenceDate
            )
        )

        let vm = OperatorWorkOrderListViewModel(actor: operatorUser, dependencies: deps)
        await vm.load()
        vm.searchText = query
        await vm.applyLocalSearch()
        return vm.cards
    }

    // MARK: - Real offline

    func testRealOfflineUsesLocalCache() async throws {
        let monitor = PathMonitorNetworkReachability()
        monitor.start()
        let initialReachable = await monitor.isReachable

        let container = DIContainer.mock()
        let deps = container.makeAdminDependencies()
        let admin = DomainFixtures.adminUser()
        let customer = DomainFixtures.customer()
        try await deps.userRepository.save(admin)
        try await deps.customerRepository.save(customer)
        try await container.workOrderRepository.save(
            DomainFixtures.workOrder(customerId: customer.id, status: .completed)
        )

        let vm = AdminDashboardViewModel(actor: admin, dependencies: deps)
        await vm.load()
        XCTAssertEqual(vm.phase, .loaded)

        let reachability = await container.networkReachability as! FakeNetworkReachability
        await reachability.setReachable(false)
        await vm.load()

        XCTAssertEqual(vm.phase, .loaded)
        XCTAssertGreaterThan(vm.summary.totalWorkOrders, 0)
        _ = initialReachable
    }

    func testRealOfflineQueuesMutation() async throws {
        let container = DIContainer.mock()
        let operatorUser = DomainFixtures.operatorUser()
        let customer = DomainFixtures.customer()
        let order = DomainFixtures.workOrder(customerId: customer.id, status: .assigned)
        try await container.userRepository.save(operatorUser)
        try await container.customerRepository.save(customer)
        try await container.workOrderRepository.save(order)

        let reachability = FakeNetworkReachability(isReachable: false)
        let base = container.makeOperatorDependencies()
        let offlineDeps = OperatorDependencies(
            getWorkOrders: base.getWorkOrders,
            getWorkOrder: base.getWorkOrder,
            workOrderService: base.workOrderService,
            customerService: base.customerService,
            workOrderTemplateService: base.workOrderTemplateService,
            customerRepository: base.customerRepository,
            userRepository: base.userRepository,
            localDirectoryCacheRefresh: base.localDirectoryCacheRefresh,
            workOrderNoteRepository: base.workOrderNoteRepository,
            workOrderPhotoRepository: base.workOrderPhotoRepository,
            workOrderLocationRepository: base.workOrderLocationRepository,
            signatureRepository: base.signatureRepository,
            statusHistoryRepository: base.statusHistoryRepository,
            editRequestRepository: base.editRequestRepository,
            editRequestService: base.editRequestService,
            customerSatisfactionRepository: base.customerSatisfactionRepository,
            customerSatisfactionService: base.customerSatisfactionService,
            notificationRepository: base.notificationRepository,
            syncOperationRepository: base.syncOperationRepository,
            syncConflictRepository: base.syncConflictRepository,
            conflictResolver: base.conflictResolver,
            networkReachability: reachability,
            profileAccountService: base.profileAccountService,
            storageDataSource: base.storageDataSource
        )

        let result = await OperatorWorkOrderBulkOperations.updatePriority(
            orderIds: [order.id],
            ordersByID: [order.id: order],
            priority: .high,
            actor: operatorUser,
            service: offlineDeps.workOrderService
        )
        XCTAssertEqual(result.successCount, 1)

        let ops = try await container.syncOperationRepository.list(
            entityType: .workOrder,
            entityId: order.id.rawValue
        )
        XCTAssertTrue(ops.contains { $0.operationType == .update && $0.status == .pending })
    }

    // MARK: - Realtime reconnect

    func testReconnectAfterNetworkRestored() async throws {
        let auth = FakeFirebaseAuthService()
        auth.setUID("uid-1")
        let transport = FakeRealtimeWebSocketTransport()
        let reachability = FakeNetworkReachability(isReachable: false)
        let config = RealtimeGatewayConfiguration(
            isEnabled: true,
            webSocketURL: URL(string: "ws://127.0.0.1:5088/ws"),
            deviceId: "test-device",
            heartbeatInterval: 60,
            initialReconnectDelay: 0.05,
            maxReconnectDelay: 0.1
        )
        let coordinator = RealtimeCoordinator(
            authService: auth,
            configuration: config,
            transport: transport,
            networkReachability: reachability
        )

        coordinator.handleAuthenticatedSession()
        try await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertEqual(coordinator.connectionState, .disconnected)

        await reachability.setReachable(true)
        try await waitUntil(timeout: 2) { coordinator.connectionState == .connected }
    }

    func testReconnectDoesNotCreateDuplicateSockets() async throws {
        let auth = FakeFirebaseAuthService()
        auth.setUID("uid-1")
        let transport = FakeRealtimeWebSocketTransport()
        let config = RealtimeGatewayConfiguration(
            isEnabled: true,
            webSocketURL: URL(string: "ws://127.0.0.1:5088/ws"),
            deviceId: "test-device",
            heartbeatInterval: 60,
            initialReconnectDelay: 0.05,
            maxReconnectDelay: 0.1
        )
        let coordinator = RealtimeCoordinator(
            authService: auth,
            configuration: config,
            transport: transport
        )

        coordinator.handleAuthenticatedSession()
        try await waitUntil(timeout: 2) { coordinator.connectionState == .connected }
        let connectsAfterInitial = await transport.connectCallCount

        coordinator.handleForeground()
        coordinator.handleForeground()
        try await Task.sleep(nanoseconds: 200_000_000)

        let connectsAfterForeground = await transport.connectCallCount
        XCTAssertEqual(connectsAfterForeground, connectsAfterInitial)
    }

    // MARK: - Reports hub

    func testCustomerReportPanelRemoved() {
        XCTAssertFalse(AdminReportKind.allCases.map(\.rawValue).contains("customerSummary"))
        XCTAssertTrue(AdminReportKind.allCases.contains(.customerAnalytics))
    }

    private func waitUntil(
        timeout: TimeInterval,
        pollIntervalNanoseconds: UInt64 = 50_000_000,
        condition: @escaping () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            try await Task.sleep(nanoseconds: pollIntervalNanoseconds)
        }
        XCTFail("Condition not met within \(timeout)s")
    }
}
