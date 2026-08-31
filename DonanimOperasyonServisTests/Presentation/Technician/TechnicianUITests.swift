import XCTest
@testable import DonanimOperasyonServis

@MainActor
final class TechnicianHomeViewModelTests: XCTestCase {

    func testDashboardLoadedForAssignedOrders() async throws {
        let container = DIContainer.mock()
        let deps = container.makeTechnicianDependencies()
        let tech = DomainFixtures.technicianUser()
        let operatorUser = DomainFixtures.operatorUser()
        let customer = DomainFixtures.customer(createdByUserId: operatorUser.id)

        try await deps.customerRepository.save(customer)
        try await container.workOrderRepository.save(
            DomainFixtures.workOrder(
                assignedTechnicianId: tech.id,
                customerId: customer.id,
                status: .assigned
            )
        )

        let vm = TechnicianHomeViewModel(actor: tech, dependencies: deps)
        await vm.load()

        XCTAssertEqual(vm.phase, .loaded)
        XCTAssertEqual(vm.summary.total, 1)
    }

    func testTechnicianHomeLoadsWithMissingCustomer() async throws {
        let container = DIContainer.mock()
        let deps = container.makeTechnicianDependencies()
        let tech = DomainFixtures.technicianUser()
        let missingCustomerId = CustomerID("missing-customer-home")

        try await container.workOrderRepository.save(
            DomainFixtures.workOrder(
                id: WorkOrderID("wo-missing-customer"),
                assignedTechnicianId: tech.id,
                customerId: missingCustomerId,
                status: .assigned
            )
        )

        let vm = TechnicianHomeViewModel(actor: tech, dependencies: deps)
        await vm.load()

        if case .error = vm.phase {
            XCTFail("Home should not error when customer is missing")
        }
        XCTAssertEqual(vm.phase, .loaded)
        XCTAssertEqual(vm.summary.total, 1)
        XCTAssertEqual(vm.upcomingJobs.first?.customerName, "Bilinmeyen müşteri")
    }

    func testTechnicianHomeContinuesWhenOneCustomerIsMissing() async throws {
        let container = DIContainer.mock()
        let deps = container.makeTechnicianDependencies()
        let tech = DomainFixtures.technicianUser()
        let operatorUser = DomainFixtures.operatorUser()
        let customerA = DomainFixtures.customer(
            id: CustomerID("cust-a-home"),
            name: "Alpha Market",
            createdByUserId: operatorUser.id
        )
        let customerB = DomainFixtures.customer(
            id: CustomerID("cust-b-home"),
            name: "Beta Shop",
            createdByUserId: operatorUser.id
        )

        try await deps.customerRepository.save(customerA)
        try await deps.customerRepository.save(customerB)
        try await container.workOrderRepository.save(
            DomainFixtures.workOrder(
                id: WorkOrderID("wo-a"),
                assignedTechnicianId: tech.id,
                customerId: customerA.id,
                status: .assigned
            )
        )
        try await container.workOrderRepository.save(
            DomainFixtures.workOrder(
                id: WorkOrderID("wo-b"),
                assignedTechnicianId: tech.id,
                customerId: customerB.id,
                status: .assigned
            )
        )
        try await container.workOrderRepository.save(
            DomainFixtures.workOrder(
                id: WorkOrderID("wo-c"),
                assignedTechnicianId: tech.id,
                customerId: CustomerID("cust-missing-home"),
                status: .assigned
            )
        )

        let vm = TechnicianHomeViewModel(actor: tech, dependencies: deps)
        await vm.load()

        XCTAssertEqual(vm.phase, .loaded)
        XCTAssertEqual(vm.summary.total, 3)
        let names = Set(vm.upcomingJobs.map(\.customerName))
        XCTAssertTrue(names.contains("Alpha Market"))
        XCTAssertTrue(names.contains("Beta Shop"))
        XCTAssertTrue(names.contains("Bilinmeyen müşteri"))
    }

    func testTechnicianHomeRefreshesRemoteDirectoryWhenOnline() async throws {
        let container = DIContainer.mock()
        let reachability = await container.networkReachability as! FakeNetworkReachability
        await reachability.setReachable(true)

        let tech = DomainFixtures.mehmetTechnician()
        let operatorUser = DomainFixtures.operatorUser()
        let customer = DomainFixtures.customer(
            id: CustomerID("cust-remote-home"),
            name: "Remote Customer",
            createdByUserId: operatorUser.id
        )
        let remoteOrder = DomainFixtures.workOrder(
            id: WorkOrderID("wo-remote-home"),
            assignedTechnicianId: tech.id,
            customerId: customer.id,
            status: .assigned
        )

        try await container.remoteWorkOrderRepository.save(remoteOrder)
        try await container.remoteCustomerRepository.save(customer)

        let deps = container.makeTechnicianDependencies()
        let vm = TechnicianHomeViewModel(actor: tech, dependencies: deps)
        await vm.load()

        XCTAssertEqual(vm.phase, .loaded)
        XCTAssertEqual(vm.summary.total, 1)
        XCTAssertEqual(vm.upcomingJobs.first?.customerName, "Remote Customer")
    }

    func testTechnicianHomeUsesLocalDataWhenOffline() async throws {
        let container = DIContainer.mock()
        let reachability = await container.networkReachability as! FakeNetworkReachability
        await reachability.setReachable(false)

        let tech = DomainFixtures.technicianUser()
        let operatorUser = DomainFixtures.operatorUser()
        let localCustomer = DomainFixtures.customer(
            id: CustomerID("cust-local-home"),
            name: "Local Customer",
            createdByUserId: operatorUser.id
        )
        let localOrder = DomainFixtures.workOrder(
            id: WorkOrderID("wo-local-home"),
            assignedTechnicianId: tech.id,
            customerId: localCustomer.id,
            status: .assigned
        )
        let remoteOnlyOrder = DomainFixtures.workOrder(
            id: WorkOrderID("wo-remote-only"),
            assignedTechnicianId: tech.id,
            customerId: localCustomer.id,
            status: .assigned
        )

        try await container.workOrderRepository.save(localOrder)
        try await container.customerRepository.save(localCustomer)
        try await container.remoteWorkOrderRepository.save(remoteOnlyOrder)

        let deps = container.makeTechnicianDependencies()
        let vm = TechnicianHomeViewModel(actor: tech, dependencies: deps)
        await vm.load()

        XCTAssertEqual(vm.phase, .loaded)
        XCTAssertEqual(vm.summary.total, 1)
        XCTAssertEqual(vm.upcomingJobs.first?.id, localOrder.id.rawValue)
    }

    func testTechnicianHomeRendersLocalCacheBeforeRemoteRefresh() async throws {
        let container = DIContainer.mock()
        let reachability = await container.networkReachability as! FakeNetworkReachability
        await reachability.setReachable(true)

        let tech = DomainFixtures.technicianUser()
        let operatorUser = DomainFixtures.operatorUser()
        let localCustomer = DomainFixtures.customer(
            id: CustomerID("cust-cache-first"),
            name: "Cache Customer",
            createdByUserId: operatorUser.id
        )
        let localOrder = DomainFixtures.workOrder(
            id: WorkOrderID("wo-cache-first"),
            assignedTechnicianId: tech.id,
            customerId: localCustomer.id,
            status: .assigned
        )
        let remoteOrder = DomainFixtures.workOrder(
            id: WorkOrderID("wo-remote-later"),
            assignedTechnicianId: tech.id,
            customerId: localCustomer.id,
            status: .assigned
        )

        try await container.workOrderRepository.save(localOrder)
        try await container.customerRepository.save(localCustomer)
        try await container.remoteWorkOrderRepository.save(localOrder)
        try await container.remoteWorkOrderRepository.save(remoteOrder)
        try await container.remoteCustomerRepository.save(localCustomer)

        let slowRemote = SlowListWorkOrderRepository(
            inner: container.remoteWorkOrderRepository,
            delayNanoseconds: 300_000_000
        )
        let refresh = LocalDirectoryCacheRefresh(
            localUsers: container.userRepository,
            remoteUsers: container.remoteUserRepository,
            localCustomers: container.customerRepository,
            remoteCustomers: container.remoteCustomerRepository,
            localWorkOrders: container.workOrderRepository,
            remoteWorkOrders: slowRemote,
            localNotifications: container.notificationRepository,
            remoteNotifications: container.remoteNotificationRepository,
            syncOperationRepository: container.syncOperationRepository,
            reconciliationEngine: container.reconciliationEngine,
            networkReachability: reachability
        )
        let deps = technicianDependencies(from: container, refresh: refresh)
        let vm = TechnicianHomeViewModel(actor: tech, dependencies: deps)

        let loadTask = Task { await vm.load() }
        try await waitUntil(timeout: 1) { vm.phase == .loaded && vm.summary.total == 1 }
        await loadTask.value

        XCTAssertEqual(vm.phase, .loaded)
        XCTAssertEqual(vm.summary.total, 2)
    }

    func testTechnicianHomeCancellationDoesNotRemainLoading() async throws {
        let container = DIContainer.mock()
        let reachability = await container.networkReachability as! FakeNetworkReachability
        await reachability.setReachable(true)

        let tech = DomainFixtures.technicianUser()
        let operatorUser = DomainFixtures.operatorUser()
        let customer = DomainFixtures.customer(createdByUserId: operatorUser.id)
        try await container.workOrderRepository.save(
            DomainFixtures.workOrder(assignedTechnicianId: tech.id, customerId: customer.id)
        )
        try await container.customerRepository.save(customer)

        let slowRemote = SlowListWorkOrderRepository(
            inner: container.remoteWorkOrderRepository,
            delayNanoseconds: 500_000_000
        )
        let refresh = LocalDirectoryCacheRefresh(
            localUsers: container.userRepository,
            remoteUsers: container.remoteUserRepository,
            localCustomers: container.customerRepository,
            remoteCustomers: container.remoteCustomerRepository,
            localWorkOrders: container.workOrderRepository,
            remoteWorkOrders: slowRemote,
            localNotifications: container.notificationRepository,
            remoteNotifications: container.remoteNotificationRepository,
            syncOperationRepository: container.syncOperationRepository,
            reconciliationEngine: container.reconciliationEngine,
            networkReachability: reachability
        )
        let deps = technicianDependencies(from: container, refresh: refresh)
        let vm = TechnicianHomeViewModel(actor: tech, dependencies: deps)

        let task = Task { await vm.load() }
        try await waitUntil(timeout: 1) { vm.phase == .loaded }
        task.cancel()
        await task.value

        XCTAssertNotEqual(vm.phase, .loading)
    }
}

@MainActor
final class TechnicianWorkOrderListPerformanceTests: XCTestCase {

    func testTechnicianWorkOrdersRendersLocalCacheBeforeRemoteRefresh() async throws {
        let container = DIContainer.mock()
        let reachability = await container.networkReachability as! FakeNetworkReachability
        await reachability.setReachable(true)

        let tech = DomainFixtures.technicianUser()
        let operatorUser = DomainFixtures.operatorUser()
        let customer = DomainFixtures.customer(
            id: CustomerID("cust-list-cache"),
            createdByUserId: operatorUser.id
        )
        let localOrder = DomainFixtures.workOrder(
            id: WorkOrderID("wo-list-cache"),
            assignedTechnicianId: tech.id,
            customerId: customer.id
        )

        try await container.workOrderRepository.save(localOrder)
        try await container.customerRepository.save(customer)
        try await container.remoteWorkOrderRepository.save(localOrder)

        let slowRemote = SlowListWorkOrderRepository(
            inner: container.remoteWorkOrderRepository,
            delayNanoseconds: 300_000_000
        )
        let refresh = LocalDirectoryCacheRefresh(
            localUsers: container.userRepository,
            remoteUsers: container.remoteUserRepository,
            localCustomers: container.customerRepository,
            remoteCustomers: container.remoteCustomerRepository,
            localWorkOrders: container.workOrderRepository,
            remoteWorkOrders: slowRemote,
            localNotifications: container.notificationRepository,
            remoteNotifications: container.remoteNotificationRepository,
            syncOperationRepository: container.syncOperationRepository,
            reconciliationEngine: container.reconciliationEngine,
            networkReachability: reachability
        )
        let deps = technicianDependencies(from: container, refresh: refresh)
        let vm = TechnicianWorkOrderListViewModel(actor: tech, dependencies: deps)

        let loadTask = Task { await vm.load() }
        try await waitUntil(timeout: 1) { vm.phase == .loaded && vm.cards.count == 1 }
        await loadTask.value

        XCTAssertEqual(vm.phase, .loaded)
        XCTAssertEqual(vm.cards.count, 1)
    }

    func testTechnicianSearchDoesNotTriggerRemoteRefresh() async throws {
        let container = DIContainer.mock()
        let reachability = await container.networkReachability as! FakeNetworkReachability
        await reachability.setReachable(true)

        let tech = DomainFixtures.technicianUser()
        let operatorUser = DomainFixtures.operatorUser()
        let customer = DomainFixtures.customer(createdByUserId: operatorUser.id)
        let order = DomainFixtures.workOrder(
            workOrderNumber: "WO-SEARCH-1",
            assignedTechnicianId: tech.id,
            customerId: customer.id
        )

        try await container.workOrderRepository.save(order)
        try await container.customerRepository.save(customer)
        try await container.remoteWorkOrderRepository.save(order)
        try await container.remoteCustomerRepository.save(customer)

        let countingRemote = CountingListWorkOrderRepository(inner: container.remoteWorkOrderRepository)
        let refresh = LocalDirectoryCacheRefresh(
            localUsers: container.userRepository,
            remoteUsers: container.remoteUserRepository,
            localCustomers: container.customerRepository,
            remoteCustomers: container.remoteCustomerRepository,
            localWorkOrders: container.workOrderRepository,
            remoteWorkOrders: countingRemote,
            localNotifications: container.notificationRepository,
            remoteNotifications: container.remoteNotificationRepository,
            syncOperationRepository: container.syncOperationRepository,
            reconciliationEngine: container.reconciliationEngine,
            networkReachability: reachability
        )
        let deps = technicianDependencies(from: container, refresh: refresh)
        let vm = TechnicianWorkOrderListViewModel(actor: tech, dependencies: deps)
        await vm.load()
        let listCallsAfterLoad = await countingRemote.listCallCount

        vm.searchText = "SEARCH"
        await vm.applyLocalSearch()

        let listCallsAfterSearch = await countingRemote.listCallCount
        XCTAssertEqual(listCallsAfterLoad, 1)
        XCTAssertEqual(listCallsAfterSearch, 1)
        XCTAssertEqual(vm.cards.count, 1)
    }

    func testTechnicianWorkOrdersCancellationDoesNotRemainLoading() async throws {
        let container = DIContainer.mock()
        let deps = container.makeTechnicianDependencies()
        let tech = DomainFixtures.technicianUser()
        let operatorUser = DomainFixtures.operatorUser()
        let customer = DomainFixtures.customer(createdByUserId: operatorUser.id)
        try await container.workOrderRepository.save(
            DomainFixtures.workOrder(assignedTechnicianId: tech.id, customerId: customer.id)
        )
        try await container.customerRepository.save(customer)

        let vm = TechnicianWorkOrderListViewModel(actor: tech, dependencies: deps)
        let task = Task { await vm.load() }
        task.cancel()
        await task.value

        XCTAssertNotEqual(vm.phase, .loading)
    }
}

private func technicianDependencies(
    from container: DIContainer,
    refresh: LocalDirectoryCacheRefresh
) -> TechnicianDependencies {
    let base = container.makeTechnicianDependencies()
    return TechnicianDependencies(
        getWorkOrders: base.getWorkOrders,
        getWorkOrder: base.getWorkOrder,
        workOrderService: base.workOrderService,
        customerRepository: base.customerRepository,
        localDirectoryCacheRefresh: refresh,
        workOrderNoteRepository: base.workOrderNoteRepository,
        workOrderPhotoRepository: base.workOrderPhotoRepository,
        workOrderLocationRepository: base.workOrderLocationRepository,
        signatureRepository: base.signatureRepository,
        statusHistoryRepository: base.statusHistoryRepository,
        notificationRepository: base.notificationRepository,
        syncOperationRepository: base.syncOperationRepository,
        syncConflictRepository: base.syncConflictRepository,
        networkReachability: base.networkReachability,
        editRequestRepository: base.editRequestRepository,
        editRequestService: base.editRequestService,
        profileAccountService: base.profileAccountService,
        storageDataSource: base.storageDataSource
    )
}

@MainActor
private func waitUntil(
    timeout: TimeInterval,
    file: StaticString = #filePath,
    line: UInt = #line,
    _ condition: @MainActor () -> Bool
) async throws {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if condition() { return }
        try await Task.sleep(nanoseconds: 20_000_000)
    }
    XCTFail("Condition not met before timeout", file: file, line: line)
}

private actor SlowListWorkOrderRepository: WorkOrderRepository {
    let inner: any WorkOrderRepository
    let delayNanoseconds: UInt64

    init(inner: any WorkOrderRepository, delayNanoseconds: UInt64) {
        self.inner = inner
        self.delayNanoseconds = delayNanoseconds
    }

    func fetch(id: WorkOrderID) async throws -> WorkOrder {
        try await inner.fetch(id: id)
    }

    func list(filter: WorkOrderFilter) async throws -> [WorkOrder] {
        try await Task.sleep(nanoseconds: delayNanoseconds)
        return try await inner.list(filter: filter)
    }

    func save(_ workOrder: WorkOrder) async throws {
        try await inner.save(workOrder)
    }

    func delete(id: WorkOrderID) async throws {
        try await inner.delete(id: id)
    }
}

private actor CountingListWorkOrderRepository: WorkOrderRepository {
    let inner: any WorkOrderRepository
    private(set) var listCallCount = 0

    init(inner: any WorkOrderRepository) {
        self.inner = inner
    }

    func fetch(id: WorkOrderID) async throws -> WorkOrder {
        try await inner.fetch(id: id)
    }

    func list(filter: WorkOrderFilter) async throws -> [WorkOrder] {
        listCallCount += 1
        return try await inner.list(filter: filter)
    }

    func save(_ workOrder: WorkOrder) async throws {
        try await inner.save(workOrder)
    }

    func delete(id: WorkOrderID) async throws {
        try await inner.delete(id: id)
    }
}

@MainActor
final class TechnicianWorkOrderAccessTests: XCTestCase {

    func testTechnicianSeesOnlyAssignedWorkOrders() async throws {
        let container = DIContainer.mock()
        let deps = container.makeTechnicianDependencies()
        let techA = DomainFixtures.technicianUser(id: UserID("tech-a"))
        let techB = DomainFixtures.technicianUser(id: UserID("tech-b"), email: "b@example.com", fullName: "Tech B")
        let customer = DomainFixtures.customer()

        try await container.workOrderRepository.save(
            DomainFixtures.workOrder(id: WorkOrderID("wo-a"), assignedTechnicianId: techA.id, customerId: customer.id)
        )
        try await container.workOrderRepository.save(
            DomainFixtures.workOrder(id: WorkOrderID("wo-b"), assignedTechnicianId: techB.id, customerId: customer.id)
        )

        let orders = try await deps.getWorkOrders.execute(actor: techA)
        XCTAssertEqual(orders.count, 1)
        XCTAssertEqual(orders.first?.id.rawValue, "wo-a")
    }

    func testTechnicianCannotAccessOtherTechnicianWorkOrderDetail() async throws {
        let container = DIContainer.mock()
        let deps = container.makeTechnicianDependencies()
        let techA = DomainFixtures.technicianUser(id: UserID("tech-a"))
        let techB = DomainFixtures.technicianUser(id: UserID("tech-b"), email: "b@example.com", fullName: "Tech B")
        let order = DomainFixtures.workOrder(assignedTechnicianId: techB.id)

        try await container.workOrderRepository.save(order)

        do {
            _ = try await deps.getWorkOrder.execute(actor: techA, id: order.id)
            XCTFail("expected unauthorized")
        } catch let error as DomainError {
            if case .unauthorized = error {
                XCTAssertTrue(true)
            } else {
                XCTFail("unexpected \(error)")
            }
        }
    }
}

@MainActor
final class TechnicianWorkflowTests: XCTestCase {

    private func seedInProgressOrder(
        deps: TechnicianDependencies,
        container: DIContainer,
        tech: User
    ) async throws -> WorkOrder {
        let customer = DomainFixtures.customer()
        try await deps.customerRepository.save(customer)
        let order = DomainFixtures.workOrder(
            assignedTechnicianId: tech.id,
            customerId: customer.id,
            status: .inProgress
        )
        try await container.workOrderRepository.save(order)
        return order
    }

    func testAcceptWorkOrderTransition() async throws {
        let container = DIContainer.mock()
        let deps = container.makeTechnicianDependencies()
        let tech = DomainFixtures.technicianUser()
        let customer = DomainFixtures.customer()
        try await deps.customerRepository.save(customer)
        let order = DomainFixtures.workOrder(
            assignedTechnicianId: tech.id,
            customerId: customer.id,
            status: .assigned
        )
        try await container.workOrderRepository.save(order)

        let updated = try await deps.workOrderService.transitionStatus(
            actor: tech,
            orderId: order.id,
            newStatus: .accepted
        )
        XCTAssertEqual(updated.status, .accepted)
    }

    func testPauseRequiresReason() async throws {
        let container = DIContainer.mock()
        let deps = container.makeTechnicianDependencies()
        let tech = DomainFixtures.technicianUser()
        let order = try await seedInProgressOrder(deps: deps, container: container, tech: tech)

        do {
            _ = try await deps.workOrderService.transitionStatus(
                actor: tech,
                orderId: order.id,
                newStatus: .paused,
                pauseReason: nil
            )
            XCTFail("expected pause reason error")
        } catch let error as DomainError {
            if case .invalidData(let reason) = error {
                XCTAssertEqual(reason, "workOrder.pauseReasonRequired")
            } else {
                XCTFail("unexpected \(error)")
            }
        }
    }

    func testPauseAndResume() async throws {
        let container = DIContainer.mock()
        let deps = container.makeTechnicianDependencies()
        let tech = DomainFixtures.technicianUser()
        let order = try await seedInProgressOrder(deps: deps, container: container, tech: tech)

        _ = try await deps.workOrderService.transitionStatus(
            actor: tech,
            orderId: order.id,
            newStatus: .paused,
            pauseReason: .partWaiting
        )
        let resumed = try await deps.workOrderService.transitionStatus(
            actor: tech,
            orderId: order.id,
            newStatus: .inProgress
        )
        XCTAssertEqual(resumed.status, .inProgress)
    }

    func testCompletionValidationBlocksIncompleteOrder() async throws {
        let container = DIContainer.mock()
        let deps = container.makeTechnicianDependencies()
        let tech = DomainFixtures.technicianUser()
        let order = try await seedInProgressOrder(deps: deps, container: container, tech: tech)

        do {
            _ = try await deps.workOrderService.complete(
                actor: tech,
                orderId: order.id,
                completedLocationId: nil
            )
            XCTFail("expected incomplete")
        } catch let error as DomainError {
            if case .incompleteWorkOrder = error {
                XCTAssertTrue(true)
            } else {
                XCTFail("unexpected \(error)")
            }
        }
    }

    func testCompletedWorkOrderCannotReopen() async throws {
        let container = DIContainer.mock()
        let deps = container.makeTechnicianDependencies()
        let tech = DomainFixtures.technicianUser()
        let customer = DomainFixtures.customer()
        try await deps.customerRepository.save(customer)
        let order = DomainFixtures.workOrder(
            assignedTechnicianId: tech.id,
            customerId: customer.id,
            status: .completed
        )
        try await container.workOrderRepository.save(order)

        do {
            _ = try await deps.workOrderService.transitionStatus(
                actor: tech,
                orderId: order.id,
                newStatus: .inProgress
            )
            XCTFail("expected locked/invalid transition")
        } catch {
            XCTAssertTrue(true)
        }
    }

    func testAddNoteCreatesSyncOperation() async throws {
        let container = DIContainer.mock()
        let deps = container.makeTechnicianDependencies()
        let tech = DomainFixtures.technicianUser()
        let order = try await seedInProgressOrder(deps: deps, container: container, tech: tech)

        let note = try await deps.workOrderService.addNote(
            actor: tech,
            orderId: order.id,
            text: "Servis notu"
        )
        let ops = try await deps.syncOperationRepository.list(
            entityType: .workOrderNote,
            entityId: note.id
        )
        XCTAssertFalse(ops.isEmpty)
        XCTAssertEqual(ops.first?.payloadReference, order.id.rawValue)
    }

    func testAddPhotoMetadataCreatesSyncOperation() async throws {
        let container = DIContainer.mock()
        let deps = container.makeTechnicianDependencies()
        let tech = DomainFixtures.technicianUser()
        let order = try await seedInProgressOrder(deps: deps, container: container, tech: tech)

        let photo = try await deps.workOrderService.addPhoto(
            actor: tech,
            orderId: order.id,
            category: .before,
            imageData: TechnicianPlaceholderImage.pngData
        )
        let ops = try await deps.syncOperationRepository.list(
            entityType: .workOrderPhoto,
            entityId: photo.id
        )
        XCTAssertFalse(ops.isEmpty)
        XCTAssertEqual(ops.first?.payloadReference, order.id.rawValue)
    }

    func testLocationEventCreatesSyncOperation() async throws {
        let container = DIContainer.mock()
        let deps = container.makeTechnicianDependencies()
        let tech = DomainFixtures.technicianUser()
        let order = try await seedInProgressOrder(deps: deps, container: container, tech: tech)

        let location = try await deps.workOrderService.recordLocation(
            actor: tech,
            orderId: order.id,
            event: .enRoute,
            coordinate: LocationCoordinate(latitude: 41.0, longitude: 29.0, accuracy: 5)
        )
        let ops = try await deps.syncOperationRepository.list(
            entityType: .workOrderLocation,
            entityId: location.id
        )
        XCTAssertFalse(ops.isEmpty)
        XCTAssertEqual(ops.first?.payloadReference, order.id.rawValue)
    }

    func testSignatureCreatesSyncOperation() async throws {
        let container = DIContainer.mock()
        let deps = container.makeTechnicianDependencies()
        let tech = DomainFixtures.technicianUser()
        let order = try await seedInProgressOrder(deps: deps, container: container, tech: tech)

        let signature = try await deps.workOrderService.recordSignature(
            actor: tech,
            orderId: order.id,
            kind: .technician,
            imageData: TechnicianPlaceholderImage.pngData
        )
        let ops = try await deps.syncOperationRepository.list(
            entityType: .signature,
            entityId: signature.id
        )
        XCTAssertFalse(ops.isEmpty)
        XCTAssertEqual(ops.first?.payloadReference, order.id.rawValue)
    }

    func testOfflineStatusUpdateStillPersistsLocally() async throws {
        let container = DIContainer.mock()
        let deps = container.makeTechnicianDependencies()
        let tech = DomainFixtures.technicianUser()
        let customer = DomainFixtures.customer()
        try await deps.customerRepository.save(customer)
        let order = DomainFixtures.workOrder(
            assignedTechnicianId: tech.id,
            customerId: customer.id,
            status: .assigned
        )
        try await container.workOrderRepository.save(order)

        let updated = try await deps.workOrderService.transitionStatus(
            actor: tech,
            orderId: order.id,
            newStatus: .accepted
        )
        XCTAssertEqual(updated.status, .accepted)
        let local = try await container.workOrderRepository.fetch(id: order.id)
        XCTAssertEqual(local.status, .accepted)
    }
}

@MainActor
final class TechnicianDetailViewModelTests: XCTestCase {

    func testWorkOrderDetailLoaded() async throws {
        let container = DIContainer.mock()
        let deps = container.makeTechnicianDependencies()
        let tech = DomainFixtures.technicianUser()
        let customer = DomainFixtures.customer()
        try await deps.customerRepository.save(customer)
        let order = DomainFixtures.workOrder(
            assignedTechnicianId: tech.id,
            customerId: customer.id,
            status: .inProgress
        )
        try await container.workOrderRepository.save(order)

        let vm = TechnicianWorkOrderDetailViewModel(
            workOrderId: order.id,
            actor: tech,
            dependencies: deps
        )
        await vm.load()
        XCTAssertEqual(vm.phase, .loaded)
        XCTAssertEqual(vm.content?.workOrder.id, order.id)
    }

    func testPrimaryActionForAssignedIsAccept() {
        let action = TechnicianWorkOrderActionMapping.primaryAction(for: .assigned)
        XCTAssertEqual(action?.title, "Kabul Et")
        XCTAssertEqual(action?.targetStatus, .accepted)
    }
}

@MainActor
final class TechnicianNotificationProfileTests: XCTestCase {

    func testNotificationListLoaded() async throws {
        let container = DIContainer.mock()
        let deps = container.makeTechnicianDependencies()
        let tech = DomainFixtures.technicianUser()
        try await container.userRepository.save(tech)
        try await deps.notificationRepository.save(
            DomainFixtures.notification(recipientUserId: tech.id)
        )
        let vm = TechnicianNotificationListViewModel(actor: tech, dependencies: deps)
        await vm.load()
        XCTAssertEqual(vm.phase, .loaded)
        XCTAssertEqual(vm.notifications.count, 1)
    }

    func testTechnicianDependenciesFactory() {
        let deps = DIContainer.mock().makeTechnicianDependencies()
        XCTAssertNotNil(deps.workOrderService)
    }

    func testTechnicianNotificationsCancellationDoesNotRemainLoading() async throws {
        let container = DIContainer.mock()
        let deps = container.makeTechnicianDependencies()
        let tech = DomainFixtures.technicianUser()
        try await container.userRepository.save(tech)

        let vm = TechnicianNotificationListViewModel(actor: tech, dependencies: deps)
        let task = Task { await vm.load() }
        task.cancel()
        await task.value

        XCTAssertNotEqual(vm.phase, .loading)
    }
}
