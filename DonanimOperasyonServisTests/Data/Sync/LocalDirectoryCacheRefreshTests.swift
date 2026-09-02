import XCTest
@testable import DonanimOperasyonServis

final class LocalDirectoryCacheRefreshTests: XCTestCase {

    private var container: DIContainer!
    private var reachability: FakeNetworkReachability!

    override func setUp() async throws {
        container = DIContainer.mock()
        reachability = await container.networkReachability as? FakeNetworkReachability
    }

    // MARK: - Technicians

    func testTechnicianListIncludesMehmetAfterRemoteRefresh() async throws {
        await reachability.setReachable(true)
        let mehmet = DomainFixtures.mehmetTechnician()
        try await container.remoteUserRepository.save(mehmet)

        let refresh = makeRefresh()
        await refresh.refreshTechnicians()

        let technicians = try await container.userRepository.list(role: .technician, isActive: true)
        XCTAssertTrue(technicians.contains(where: { $0.id == DomainFixtures.mehmetTechnicianUID }))
        XCTAssertEqual(
            technicians.first(where: { $0.id == DomainFixtures.mehmetTechnicianUID })?.fullName,
            "Mehmet Kerem"
        )
    }

    func testMehmetFirestoreRoleAndAuthClaimAreConsistent() {
        let mehmet = DomainFixtures.mehmetTechnician()
        XCTAssertEqual(mehmet.role, .technician)
        XCTAssertEqual(DomainFixtures.mehmetTechnicianUID.rawValue, "v1OBBg4YMWPoo1prrf7kp9wmQAa2")
        // Firestore `users/{uid}.role` (UI) and Auth custom claim `role` (Gateway) must both be technician.
        XCTAssertEqual(UserRole.technician.rawValue, "technician")
    }

    func testNotificationRefreshPullsRemoteRowsForRecipient() async throws {
        await reachability.setReachable(true)
        let mehmet = DomainFixtures.mehmetTechnician()
        let notification = DomainFixtures.notification(
            id: NotificationID("notif-refresh"),
            recipientUserId: mehmet.id,
            type: .workOrderAssigned
        )
        try await container.remoteNotificationRepository.save(notification)

        let refresh = makeRefresh()
        await refresh.refreshNotifications(recipientUserId: mehmet.id)

        let local = try await container.notificationRepository.list(for: mehmet.id, unreadOnly: false)
        XCTAssertTrue(local.contains { $0.id == notification.id })
    }

    func testCustomerSatisfactionRefreshPullsSubmittedRemoteRows() async throws {
        await reachability.setReachable(true)
        let satisfaction = DomainFixtures.customerSatisfaction(
            id: CustomerSatisfactionID("cs-refresh-submitted"),
            status: .submitted,
            rating: .five,
            comment: "Harika hizmet"
        )
        try await container.remoteCustomerSatisfactionRepository.save(satisfaction)

        let localBefore = try await container.customerSatisfactionRepository.listByStatus(.submitted)
        XCTAssertFalse(localBefore.contains { $0.id == satisfaction.id })

        let refresh = makeRefresh()
        await refresh.refreshCustomerSatisfactions()

        let localAfter = try await container.customerSatisfactionRepository.listByStatus(.submitted)
        let refreshed = try XCTUnwrap(localAfter.first { $0.id == satisfaction.id })
        XCTAssertEqual(refreshed.status, .submitted)
        XCTAssertEqual(refreshed.rating, .five)
        XCTAssertEqual(refreshed.comment, "Harika hizmet")
    }

    func testCustomerSatisfactionRefreshUpdatesPendingLocalToSubmittedRemote() async throws {
        await reachability.setReachable(true)
        let satisfactionId = CustomerSatisfactionID("cs-refresh-pending-local")
        let pendingLocal = DomainFixtures.customerSatisfaction(id: satisfactionId, status: .pending)
        try await container.customerSatisfactionRepository.save(pendingLocal)

        var submittedRemote = pendingLocal
        submittedRemote.status = .submitted
        submittedRemote.rating = .four
        submittedRemote.comment = "Web yanıtı"
        submittedRemote.submittedAt = Date()
        try await container.remoteCustomerSatisfactionRepository.save(submittedRemote)

        let refresh = makeRefresh()
        await refresh.refreshCustomerSatisfactions()

        let local = try await container.customerSatisfactionRepository.fetch(id: satisfactionId)
        XCTAssertEqual(local.status, .submitted)
        XCTAssertEqual(local.rating, .four)
        XCTAssertEqual(local.comment, "Web yanıtı")
        XCTAssertNotNil(local.submittedAt)
    }

    func testTechnicianAssignmentRefreshPullsAssignedWorkOrdersAndCustomersWhenOnline() async throws {
        await reachability.setReachable(true)
        let tech = DomainFixtures.mehmetTechnician()
        let operatorUser = DomainFixtures.operatorUser()
        let customer = DomainFixtures.customer(
            id: CustomerID("cust-tech-refresh"),
            name: "Teknisyen Müşteri",
            createdByUserId: operatorUser.id
        )
        let remoteOrder = DomainFixtures.workOrder(
            id: WorkOrderID("wo-tech-refresh"),
            assignedTechnicianId: tech.id,
            customerId: customer.id,
            status: .assigned
        )
        try await container.remoteWorkOrderRepository.save(remoteOrder)
        try await container.remoteCustomerRepository.save(customer)

        let refresh = makeRefresh()
        await refresh.refreshTechnicianAssignments(technicianId: tech.id)

        let localOrders = try await container.workOrderRepository.list(
            filter: WorkOrderFilter(assignedTechnicianId: tech.id)
        )
        XCTAssertEqual(localOrders.map(\.id), [remoteOrder.id])
        let storedCustomer = try await container.customerRepository.fetch(id: customer.id)
        XCTAssertEqual(storedCustomer.name, "Teknisyen Müşteri")
    }

    func testTechnicianAssignmentRefreshSkippedWhenOffline() async throws {
        await reachability.setReachable(false)
        let tech = DomainFixtures.mehmetTechnician()
        let operatorUser = DomainFixtures.operatorUser()
        let customer = DomainFixtures.customer(
            id: CustomerID("cust-tech-offline"),
            createdByUserId: operatorUser.id
        )
        try await container.remoteWorkOrderRepository.save(
            DomainFixtures.workOrder(
                id: WorkOrderID("wo-tech-offline"),
                assignedTechnicianId: tech.id,
                customerId: customer.id
            )
        )

        let refresh = makeRefresh()
        await refresh.refreshTechnicianAssignments(technicianId: tech.id)

        let localOrders = try await container.workOrderRepository.list(
            filter: WorkOrderFilter(assignedTechnicianId: tech.id)
        )
        XCTAssertTrue(localOrders.isEmpty)
    }

    func testTechnicianAssignmentRefreshIsDeduplicated() async throws {
        await reachability.setReachable(true)
        let tech = DomainFixtures.mehmetTechnician()
        let operatorUser = DomainFixtures.operatorUser()
        let customer = DomainFixtures.customer(
            id: CustomerID("cust-dedupe"),
            createdByUserId: operatorUser.id
        )
        try await container.remoteWorkOrderRepository.save(
            DomainFixtures.workOrder(
                id: WorkOrderID("wo-dedupe"),
                assignedTechnicianId: tech.id,
                customerId: customer.id
            )
        )
        try await container.remoteCustomerRepository.save(customer)

        let countingRemote = CountingListWorkOrderRepository(inner: container.remoteWorkOrderRepository)
        let refresh = makeRefresh(remoteWorkOrders: countingRemote)

        async let first: Void = refresh.refreshTechnicianAssignments(technicianId: tech.id)
        async let second: Void = refresh.refreshTechnicianAssignments(technicianId: tech.id)
        _ = await (first, second)

        let listCalls = await countingRemote.listCallCount
        XCTAssertEqual(listCalls, 1)
    }

    func testTechnicianRefreshAvoidsDuplicateWorkOrderFetch() async throws {
        await reachability.setReachable(true)
        let tech = DomainFixtures.mehmetTechnician()
        let operatorUser = DomainFixtures.operatorUser()
        let customer = DomainFixtures.customer(
            id: CustomerID("cust-no-dup-fetch"),
            createdByUserId: operatorUser.id
        )
        let order = DomainFixtures.workOrder(
            id: WorkOrderID("wo-no-dup-fetch"),
            assignedTechnicianId: tech.id,
            customerId: customer.id,
            status: .assigned
        )

        try await container.workOrderRepository.save(order)
        try await container.remoteWorkOrderRepository.save(order)
        try await container.remoteCustomerRepository.save(customer)

        let countingRemote = CountingFetchWorkOrderRepository(inner: container.remoteWorkOrderRepository)
        let refresh = makeRefresh(remoteWorkOrders: countingRemote)
        await refresh.refreshTechnicianAssignments(technicianId: tech.id)

        let fetchCount = await countingRemote.fetchCallCount
        XCTAssertEqual(fetchCount, 0)
    }

    func testTechnicianCustomerRefreshUsesBoundedConcurrency() async throws {
        await reachability.setReachable(true)
        let tech = DomainFixtures.mehmetTechnician()
        let operatorUser = DomainFixtures.operatorUser()

        for index in 0..<12 {
            let customer = DomainFixtures.customer(
                id: CustomerID("cust-conc-\(index)"),
                createdByUserId: operatorUser.id
            )
            try await container.remoteCustomerRepository.save(customer)
            try await container.remoteWorkOrderRepository.save(
                DomainFixtures.workOrder(
                    id: WorkOrderID("wo-conc-\(index)"),
                    assignedTechnicianId: tech.id,
                    customerId: customer.id
                )
            )
        }

        let trackingRemote = ConcurrentTrackingCustomerRepository(
            inner: container.remoteCustomerRepository,
            delayNanoseconds: 40_000_000
        )
        let refresh = makeRefresh(remoteCustomers: trackingRemote)
        await refresh.refreshTechnicianAssignments(technicianId: tech.id)

        let maxConcurrent = await trackingRemote.maxConcurrentObserved
        let fetchCount = await trackingRemote.fetchCallCount
        XCTAssertEqual(fetchCount, 12)
        XCTAssertLessThanOrEqual(maxConcurrent, 5)
        XCTAssertGreaterThan(maxConcurrent, 1)
    }

    func testTechnicianRefreshSkipsExistingLocalCustomers() async throws {
        await reachability.setReachable(true)
        let tech = DomainFixtures.mehmetTechnician()
        let operatorUser = DomainFixtures.operatorUser()
        let customer = DomainFixtures.customer(
            id: CustomerID("cust-local-skip"),
            name: "Local Cached",
            createdByUserId: operatorUser.id
        )
        try await container.customerRepository.save(customer)
        try await container.remoteCustomerRepository.save(customer)
        try await container.remoteWorkOrderRepository.save(
            DomainFixtures.workOrder(
                id: WorkOrderID("wo-local-skip"),
                assignedTechnicianId: tech.id,
                customerId: customer.id
            )
        )

        let countingRemote = CountingFetchCustomerRepository(inner: container.remoteCustomerRepository)
        let refresh = makeRefresh(remoteCustomers: countingRemote)
        await refresh.refreshTechnicianAssignments(technicianId: tech.id)

        let fetchCount = await countingRemote.fetchCallCount
        XCTAssertEqual(fetchCount, 0)
    }

    func testLocalUserOnlineRemotePopulatesLocalCacheForAdminDirectory() async throws {
        await reachability.setReachable(true)
        let remoteAdmin = DomainFixtures.adminUser(id: UserID("admin-remote"))
        let remoteTech = DomainFixtures.mehmetTechnician()
        try await container.remoteUserRepository.save(remoteAdmin)
        try await container.remoteUserRepository.save(remoteTech)

        let refresh = makeRefresh()
        await refresh.refreshUsers()

        let local = try await container.userRepository.list(role: nil, isActive: nil)
        XCTAssertEqual(Set(local.map(\.id)), Set([remoteAdmin.id, remoteTech.id]))
    }

    func testLocalTechnicianOnlineRemoteUpdatesLocalCache() async throws {
        await reachability.setReachable(true)
        let localId = UserID("tech-remote-1")
        let stale = DomainFixtures.technicianUser(id: localId, fullName: "Eski Ad")
        let fresh = DomainFixtures.technicianUser(id: localId, fullName: "Güncel Ad")
        try await container.userRepository.save(stale)
        try await container.remoteUserRepository.save(fresh)

        let refresh = makeRefresh()
        await refresh.refreshTechnicians()

        let stored = try await container.userRepository.fetch(id: localId)
        XCTAssertEqual(stored.fullName, "Güncel Ad")
    }

    func testLocalTechnicianOfflineSkipsRemoteRefresh() async throws {
        await reachability.setReachable(false)
        let tech = DomainFixtures.technicianUser(id: UserID("tech-offline"), fullName: "Yerel Teknisyen")
        try await container.userRepository.save(tech)
        try await container.remoteUserRepository.save(
            DomainFixtures.technicianUser(id: UserID("tech-remote-only"), fullName: "Uzak")
        )

        let refresh = makeRefresh()
        await refresh.refreshTechnicians()

        let local = try await container.userRepository.list(role: .technician, isActive: true)
        XCTAssertEqual(local.map(\.id), [tech.id])
    }

    func testLocalTechnicianRemoteFailurePreservesLocalCache() async throws {
        await reachability.setReachable(true)
        let tech = DomainFixtures.technicianUser(id: UserID("tech-local"), fullName: "Korunan")
        try await container.userRepository.save(tech)

        let refresh = makeRefresh(remoteUsers: FailingListUserRepository())
        await refresh.refreshTechnicians()

        let local = try await container.userRepository.fetch(id: tech.id)
        XCTAssertEqual(local.fullName, "Korunan")
    }

    func testLocalEmptyOnlineRemotePopulatesLocalCache() async throws {
        await reachability.setReachable(true)
        let remoteTech = DomainFixtures.technicianUser(id: UserID("tech-new"), fullName: "Firestore Teknisyen")
        try await container.remoteUserRepository.save(remoteTech)

        let refresh = makeRefresh()
        await refresh.refreshTechnicians()

        let local = try await container.userRepository.list(role: .technician, isActive: true)
        XCTAssertEqual(local.map(\.id), [remoteTech.id])
    }

    func testLocalEmptyOfflineStaysEmpty() async throws {
        await reachability.setReachable(false)
        try await container.remoteUserRepository.save(
            DomainFixtures.technicianUser(id: UserID("tech-remote"), fullName: "Uzak")
        )

        let refresh = makeRefresh()
        await refresh.refreshTechnicians()

        let local = try await container.userRepository.list(role: .technician, isActive: true)
        XCTAssertTrue(local.isEmpty)
    }

    func testDuplicateTechnicianNotCreatedOnRepeatedRefresh() async throws {
        await reachability.setReachable(true)
        let tech = DomainFixtures.technicianUser(id: UserID("tech-dup"), fullName: "Tek")
        try await container.remoteUserRepository.save(tech)

        let refresh = makeRefresh()
        await refresh.refreshTechnicians()
        await refresh.refreshTechnicians()

        let local = try await container.userRepository.list(role: .technician, isActive: true)
        XCTAssertEqual(local.count, 1)
        XCTAssertEqual(local.first?.id, tech.id)
    }

    // MARK: - Customers

    func testLocalCustomerOnlineRemoteUpdatesLocalCache() async throws {
        await reachability.setReachable(true)
        let customerId = CustomerID("cust-remote-1")
        let operatorId = UserID("op-1")
        let stale = DomainFixtures.customer(id: customerId, name: "Eski Firma", createdByUserId: operatorId)
        let fresh = DomainFixtures.customer(id: customerId, name: "Güncel Firma", createdByUserId: operatorId)
        try await container.customerRepository.save(stale)
        try await container.remoteCustomerRepository.save(fresh)

        let refresh = makeRefresh()
        await refresh.refreshCustomers()

        let stored = try await container.customerRepository.fetch(id: customerId)
        XCTAssertEqual(stored.name, "Güncel Firma")
    }

    func testLocalCustomerOfflineSkipsRemoteRefresh() async throws {
        await reachability.setReachable(false)
        let operatorId = UserID("op-1")
        let local = DomainFixtures.customer(id: CustomerID("cust-local"), name: "Yerel", createdByUserId: operatorId)
        try await container.customerRepository.save(local)
        try await container.remoteCustomerRepository.save(
            DomainFixtures.customer(id: CustomerID("cust-remote"), name: "Uzak", createdByUserId: operatorId)
        )

        let refresh = makeRefresh()
        await refresh.refreshCustomers()

        let listed = try await container.customerRepository.list(searchText: nil)
        XCTAssertEqual(listed.map(\.id), [local.id])
    }

    func testLocalCustomerRemoteFailurePreservesLocalCache() async throws {
        await reachability.setReachable(true)
        let operatorId = UserID("op-1")
        let local = DomainFixtures.customer(id: CustomerID("cust-protected"), name: "Korunan", createdByUserId: operatorId)
        try await container.customerRepository.save(local)

        let refresh = makeRefresh(remoteCustomers: FailingListCustomerRepository())
        await refresh.refreshCustomers()

        let stored = try await container.customerRepository.fetch(id: local.id)
        XCTAssertEqual(stored.name, "Korunan")
    }

    func testLocalEmptyOnlineRemotePopulatesCustomerCache() async throws {
        await reachability.setReachable(true)
        let operatorId = UserID("op-1")
        let remote = DomainFixtures.customer(id: CustomerID("cust-new"), name: "Firestore Müşteri", createdByUserId: operatorId)
        try await container.remoteCustomerRepository.save(remote)

        let refresh = makeRefresh()
        await refresh.refreshCustomers()

        let local = try await container.customerRepository.list(searchText: nil)
        XCTAssertEqual(local.map(\.id), [remote.id])
    }

    func testDuplicateCustomerNotCreatedOnRepeatedRefresh() async throws {
        await reachability.setReachable(true)
        let operatorId = UserID("op-1")
        let customer = DomainFixtures.customer(id: CustomerID("cust-dup"), name: "Tek", createdByUserId: operatorId)
        try await container.remoteCustomerRepository.save(customer)

        let refresh = makeRefresh()
        await refresh.refreshCustomers()
        await refresh.refreshCustomers()

        let local = try await container.customerRepository.list(searchText: nil)
        XCTAssertEqual(local.count, 1)
        XCTAssertEqual(local.first?.id, customer.id)
    }

    func testPendingCustomerUpdateSkipsRemoteOverwrite() async throws {
        await reachability.setReachable(true)
        let operatorId = UserID("op-1")
        let customerId = CustomerID("cust-pending")
        var localEdited = DomainFixtures.customer(
            id: customerId,
            name: "Yerel Güncel Adres",
            createdByUserId: operatorId
        )
        localEdited.address = "Yeni Adres 99"
        var remoteStale = DomainFixtures.customer(
            id: customerId,
            name: "Firestore Eski",
            createdByUserId: operatorId
        )
        remoteStale.address = "Eski Adres 1"
        try await container.customerRepository.save(localEdited)
        try await container.remoteCustomerRepository.save(remoteStale)

        let pending = try SyncOperation.pending(
            entityType: .customer,
            entityId: customerId.rawValue,
            operationType: .update,
            createdAt: Date(),
            localVersion: 2,
            actorUserId: operatorId.rawValue
        )
        _ = try await container.syncOperationRepository.enqueue(pending)

        let refresh = makeRefresh()
        await refresh.refreshCustomers()

        let stored = try await container.customerRepository.fetch(id: customerId)
        XCTAssertEqual(stored.name, "Yerel Güncel Adres")
        XCTAssertEqual(stored.address, "Yeni Adres 99")
    }

    func testNoPendingCustomerUpdateAllowsRemoteOverwrite() async throws {
        await reachability.setReachable(true)
        let operatorId = UserID("op-1")
        let customerId = CustomerID("cust-no-pending")
        let localStale = DomainFixtures.customer(
            id: customerId,
            name: "Yerel Eski",
            createdByUserId: operatorId
        )
        let remoteFresh = DomainFixtures.customer(
            id: customerId,
            name: "Firestore Güncel",
            createdByUserId: operatorId
        )
        try await container.customerRepository.save(localStale)
        try await container.remoteCustomerRepository.save(remoteFresh)

        let refresh = makeRefresh()
        await refresh.refreshCustomers()

        let stored = try await container.customerRepository.fetch(id: customerId)
        XCTAssertEqual(stored.name, "Firestore Güncel")
    }

    // MARK: - Work orders

    func testRemoteNewWorkOrderInsertsIntoLocalCache() async throws {
        await reachability.setReachable(true)
        let remoteOrder = DomainFixtures.workOrder(
            id: WorkOrderID("wo-remote-new"),
            workOrderNumber: "WO-REMOTE-1"
        )
        try await container.remoteWorkOrderRepository.save(remoteOrder)

        let refresh = makeRefresh()
        await refresh.refreshWorkOrders()

        let local = try await container.workOrderRepository.fetch(id: remoteOrder.id)
        XCTAssertEqual(local.workOrderNumber, "WO-REMOTE-1")
    }

    func testWorkOrderOfflineSkipsRemoteRefresh() async throws {
        await reachability.setReachable(false)
        let localOrder = DomainFixtures.workOrder(id: WorkOrderID("wo-local-only"))
        try await container.workOrderRepository.save(localOrder)
        try await container.remoteWorkOrderRepository.save(
            DomainFixtures.workOrder(id: WorkOrderID("wo-remote-only"))
        )

        let refresh = makeRefresh()
        await refresh.refreshWorkOrders()

        let listed = try await container.workOrderRepository.list(filter: .all)
        XCTAssertEqual(listed.map(\.id), [localOrder.id])
    }

    func testWorkOrderRemoteFailurePreservesLocalCache() async throws {
        await reachability.setReachable(true)
        let localOrder = DomainFixtures.workOrder(
            id: WorkOrderID("wo-protected"),
            workOrderNumber: "WO-LOCAL"
        )
        try await container.workOrderRepository.save(localOrder)

        let refresh = makeRefresh(remoteWorkOrders: FailingListWorkOrderRepository())
        await refresh.refreshWorkOrders()

        let stored = try await container.workOrderRepository.fetch(id: localOrder.id)
        XCTAssertEqual(stored.workOrderNumber, "WO-LOCAL")
    }

    func testPendingAssignDoesNotOverwriteLocalWorkOrder() async throws {
        await reachability.setReachable(true)
        let orderId = WorkOrderID("wo-pending-assign")
        let techA = UserID("tech-a")
        let techB = UserID("tech-b")
        var localOrder = DomainFixtures.workOrder(
            id: orderId,
            assignedTechnicianId: techB
        )
        var remoteOrder = DomainFixtures.workOrder(
            id: orderId,
            assignedTechnicianId: techA
        )
        try await container.workOrderRepository.save(localOrder)
        try await container.remoteWorkOrderRepository.save(remoteOrder)

        let pending = try SyncOperation.pending(
            entityType: .workOrder,
            entityId: orderId.rawValue,
            operationType: .update,
            createdAt: Date(),
            localVersion: 2,
            workOrderStatus: localOrder.status,
            actorUserId: DomainFixtures.operatorUser().id.rawValue
        )
        _ = try await container.syncOperationRepository.enqueue(pending)

        let refresh = makeRefresh()
        await refresh.refreshWorkOrders()

        let stored = try await container.workOrderRepository.fetch(id: orderId)
        XCTAssertEqual(stored.assignedTechnicianId, techB)
    }

    func testLocalCompletedVersusRemoteInProgressPersistsConflict() async throws {
        await reachability.setReachable(true)
        let orderId = WorkOrderID("wo-completed-local")
        let now = DomainFixtures.referenceDate
        let localOrder = DomainFixtures.workOrder(
            id: orderId,
            status: .completed,
            completedAt: now
        )
        let remoteOrder = DomainFixtures.workOrder(
            id: orderId,
            status: .inProgress,
            completedAt: nil
        )
        try await container.workOrderRepository.save(localOrder)
        try await container.remoteWorkOrderRepository.save(remoteOrder)

        let refresh = makeRefresh()
        await refresh.refreshWorkOrders()

        let stored = try await container.workOrderRepository.fetch(id: orderId)
        XCTAssertEqual(stored.status, .completed)
        let conflicts = try await container.syncConflictRepository.listUnresolved()
        XCTAssertTrue(conflicts.contains { $0.entityId == orderId.rawValue })
    }

    func testLocalInProgressVersusRemoteCompletedPersistsConflict() async throws {
        await reachability.setReachable(true)
        let orderId = WorkOrderID("wo-completed-remote")
        let now = DomainFixtures.referenceDate
        let localOrder = DomainFixtures.workOrder(
            id: orderId,
            status: .inProgress,
            completedAt: nil
        )
        let remoteOrder = DomainFixtures.workOrder(
            id: orderId,
            status: .completed,
            completedAt: now
        )
        try await container.workOrderRepository.save(localOrder)
        try await container.remoteWorkOrderRepository.save(remoteOrder)

        let refresh = makeRefresh()
        await refresh.refreshWorkOrders()

        let stored = try await container.workOrderRepository.fetch(id: orderId)
        XCTAssertEqual(stored.status, .inProgress)
        let conflicts = try await container.syncConflictRepository.listUnresolved()
        XCTAssertTrue(conflicts.contains { $0.entityId == orderId.rawValue })
    }

    func testIdenticalLocalRemoteWorkOrderIsNoChange() async throws {
        await reachability.setReachable(true)
        let order = DomainFixtures.workOrder(id: WorkOrderID("wo-same"))
        try await container.workOrderRepository.save(order)
        try await container.remoteWorkOrderRepository.save(order)

        let refresh = makeRefresh()
        await refresh.refreshWorkOrders()

        let stored = try await container.workOrderRepository.fetch(id: order.id)
        XCTAssertEqual(stored, order)
        let conflicts = try await container.syncConflictRepository.listUnresolved()
        XCTAssertFalse(conflicts.contains { $0.entityId == order.id.rawValue })
    }

    func testPendingLocalCreateNotInRemoteListStaysLocal() async throws {
        await reachability.setReachable(true)
        let orderId = WorkOrderID("wo-pending-create")
        let localOrder = DomainFixtures.workOrder(id: orderId, workOrderNumber: "WO-PENDING")
        try await container.workOrderRepository.save(localOrder)

        let pending = try SyncOperation.pending(
            entityType: .workOrder,
            entityId: orderId.rawValue,
            operationType: .create,
            createdAt: Date(),
            localVersion: 1,
            actorUserId: DomainFixtures.operatorUser().id.rawValue
        )
        _ = try await container.syncOperationRepository.enqueue(pending)

        let refresh = makeRefresh()
        await refresh.refreshWorkOrders()

        let stored = try await container.workOrderRepository.fetch(id: orderId)
        XCTAssertEqual(stored.workOrderNumber, "WO-PENDING")
    }

    func testCustomerIdFilterOnlyReconcilesScopedWorkOrders() async throws {
        await reachability.setReachable(true)
        let customerA = CustomerID("cust-a")
        let customerB = CustomerID("cust-b")
        let orderA = DomainFixtures.workOrder(
            id: WorkOrderID("wo-cust-a"),
            workOrderNumber: "WO-A",
            customerId: customerA
        )
        let orderB = DomainFixtures.workOrder(
            id: WorkOrderID("wo-cust-b"),
            workOrderNumber: "WO-B",
            customerId: customerB
        )
        try await container.remoteWorkOrderRepository.save(orderA)
        try await container.remoteWorkOrderRepository.save(orderB)

        let refresh = makeRefresh()
        await refresh.refreshWorkOrders(filter: WorkOrderFilter(customerId: customerA))

        let local = try await container.workOrderRepository.list(filter: .all)
        XCTAssertEqual(local.map(\.id), [orderA.id])
    }

    private func makeRefresh(
        remoteUsers: UserRepository? = nil,
        remoteCustomers: CustomerRepository? = nil,
        remoteWorkOrders: WorkOrderRepository? = nil,
        reconciliationEngine: (any Reconciling)? = nil
    ) -> LocalDirectoryCacheRefresh {
        LocalDirectoryCacheRefresh(
            localUsers: container.userRepository,
            remoteUsers: remoteUsers ?? container.remoteUserRepository,
            localCustomers: container.customerRepository,
            remoteCustomers: remoteCustomers ?? container.remoteCustomerRepository,
            localWorkOrders: container.workOrderRepository,
            remoteWorkOrders: remoteWorkOrders ?? container.remoteWorkOrderRepository,
            localNotifications: container.notificationRepository,
            remoteNotifications: container.remoteNotificationRepository,
            localCustomerSatisfactions: container.customerSatisfactionRepository,
            remoteCustomerSatisfactions: container.remoteCustomerSatisfactionRepository,
            syncOperationRepository: container.syncOperationRepository,
            reconciliationEngine: reconciliationEngine ?? container.reconciliationEngine,
            networkReachability: reachability
        )
    }
}

@MainActor
final class OfflineFirstTechnicianPresentationTests: XCTestCase {

    func testWizardLoadSelectionsSurvivesRemoteRefreshFailure() async throws {
        let container = DIContainer.mock()
        let reachability = await container.networkReachability as! FakeNetworkReachability
        await reachability.setReachable(true)

        let operatorUser = DomainFixtures.operatorUser()
        let tech = DomainFixtures.technicianUser(id: UserID("tech-wizard"), fullName: "Wizard Tech")
        let deps = container.makeOperatorDependencies()
        try await deps.userRepository.save(operatorUser)
        try await deps.userRepository.save(tech)
        try await deps.customerRepository.save(
            DomainFixtures.customer(createdByUserId: operatorUser.id)
        )

        let failingDeps = operatorDependencies(
            from: deps,
            refresh: makeFailingTechnicianRefresh(container: container, reachability: reachability)
        )

        let vm = NewWorkOrderWizardViewModel(actor: operatorUser, dependencies: failingDeps)
        await vm.loadSelections()

        if case .error = vm.phase {
            XCTFail("Wizard should not enter error phase when local technicians exist")
        }
        XCTAssertEqual(vm.technicians.map(\.id), [tech.id])
    }

    func testAssignSheetStaysOpenWhenRemoteRefreshFails() async throws {
        let container = DIContainer.mock()
        let reachability = await container.networkReachability as! FakeNetworkReachability
        await reachability.setReachable(true)

        let operatorUser = DomainFixtures.operatorUser()
        let tech = DomainFixtures.technicianUser(id: UserID("tech-assign"), fullName: "Assign Tech")
        let customer = DomainFixtures.customer(createdByUserId: operatorUser.id)
        let order = DomainFixtures.workOrder(
            assignedTechnicianId: tech.id,
            customerId: customer.id
        )

        let deps = container.makeOperatorDependencies()
        try await deps.userRepository.save(operatorUser)
        try await deps.userRepository.save(tech)
        try await deps.customerRepository.save(customer)
        try await container.workOrderRepository.save(order)

        let failingDeps = operatorDependencies(
            from: deps,
            refresh: makeFailingTechnicianRefresh(container: container, reachability: reachability)
        )

        let vm = OperatorWorkOrderDetailViewModel(
            workOrderId: order.id,
            actor: operatorUser,
            dependencies: failingDeps
        )
        await vm.load()
        vm.attemptAssign()
        await vm.loadAssignableTechnicians()

        XCTAssertTrue(vm.showsAssignSheet)
        XCTAssertTrue(vm.assignableTechnicians.contains(where: { $0.id == tech.id }))
        XCTAssertNil(vm.assignmentError)
    }

    func testWorkOrderDetailRefreshesMissingDirectoryOnFirstLoad() async throws {
        let container = DIContainer.mock()
        let reachability = await container.networkReachability as! FakeNetworkReachability
        await reachability.setReachable(true)

        let operatorUser = DomainFixtures.operatorUser()
        let tech = DomainFixtures.technicianUser(id: UserID("tech-detail"), fullName: "Detail Tech")
        let customer = DomainFixtures.customer(
            id: CustomerID("cust-detail"),
            name: "Detail Müşteri",
            createdByUserId: operatorUser.id
        )
        let order = DomainFixtures.workOrder(
            id: WorkOrderID("wo-detail-first-open"),
            workOrderNumber: "WO-FIRST",
            assignedTechnicianId: tech.id,
            customerId: customer.id
        )

        let deps = container.makeOperatorDependencies()
        try await container.workOrderRepository.save(order)
        try await container.remoteUserRepository.save(operatorUser)
        try await container.remoteUserRepository.save(tech)
        try await container.remoteCustomerRepository.save(customer)

        let vm = OperatorWorkOrderDetailViewModel(
            workOrderId: order.id,
            actor: operatorUser,
            dependencies: deps
        )

        await vm.load()

        XCTAssertEqual(vm.phase, .loaded)
        XCTAssertEqual(vm.content?.workOrder.id, order.id)
        XCTAssertEqual(vm.content?.customer.id, customer.id)
        XCTAssertEqual(vm.content?.technicianName, tech.fullName)
    }

    private func makeFailingTechnicianRefresh(
        container: DIContainer,
        reachability: FakeNetworkReachability
    ) -> LocalDirectoryCacheRefresh {
        LocalDirectoryCacheRefresh(
            localUsers: container.userRepository,
            remoteUsers: FailingListUserRepository(),
            localCustomers: container.customerRepository,
            remoteCustomers: container.remoteCustomerRepository,
            localWorkOrders: container.workOrderRepository,
            remoteWorkOrders: container.remoteWorkOrderRepository,
            localNotifications: container.notificationRepository,
            remoteNotifications: container.remoteNotificationRepository,
            localCustomerSatisfactions: container.customerSatisfactionRepository,
            remoteCustomerSatisfactions: container.remoteCustomerSatisfactionRepository,
            syncOperationRepository: container.syncOperationRepository,
            reconciliationEngine: container.reconciliationEngine,
            networkReachability: reachability
        )
    }

    private func operatorDependencies(
        from base: OperatorDependencies,
        refresh: LocalDirectoryCacheRefresh
    ) -> OperatorDependencies {
        OperatorDependencies(
            getWorkOrders: base.getWorkOrders,
            getWorkOrder: base.getWorkOrder,
            workOrderService: base.workOrderService,
            customerService: base.customerService,
            workOrderTemplateService: base.workOrderTemplateService,
            customerRepository: base.customerRepository,
            userRepository: base.userRepository,
            localDirectoryCacheRefresh: refresh,
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
            networkReachability: base.networkReachability,
            profileAccountService: base.profileAccountService,
            storageDataSource: base.storageDataSource
        )
    }
}

@MainActor
final class OfflineFirstCustomerPresentationTests: XCTestCase {

    func testCustomerListSurvivesRemoteRefreshFailure() async throws {
        let container = DIContainer.mock()
        let reachability = await container.networkReachability as! FakeNetworkReachability
        await reachability.setReachable(true)

        let operatorUser = DomainFixtures.operatorUser()
        let customer = DomainFixtures.customer(
            id: CustomerID("cust-list"),
            name: "Liste Müşteri",
            createdByUserId: operatorUser.id
        )
        let deps = container.makeOperatorDependencies()
        try await deps.customerRepository.save(customer)

        let failingRefresh = LocalDirectoryCacheRefresh(
            localUsers: container.userRepository,
            remoteUsers: container.remoteUserRepository,
            localCustomers: container.customerRepository,
            remoteCustomers: FailingListCustomerRepository(),
            localWorkOrders: container.workOrderRepository,
            remoteWorkOrders: container.remoteWorkOrderRepository,
            localNotifications: container.notificationRepository,
            remoteNotifications: container.remoteNotificationRepository,
            localCustomerSatisfactions: container.customerSatisfactionRepository,
            remoteCustomerSatisfactions: container.remoteCustomerSatisfactionRepository,
            syncOperationRepository: container.syncOperationRepository,
            reconciliationEngine: container.reconciliationEngine,
            networkReachability: reachability
        )
        let testDeps = OperatorDependencies(
            getWorkOrders: deps.getWorkOrders,
            getWorkOrder: deps.getWorkOrder,
            workOrderService: deps.workOrderService,
            customerService: deps.customerService,
            workOrderTemplateService: deps.workOrderTemplateService,
            customerRepository: deps.customerRepository,
            userRepository: deps.userRepository,
            localDirectoryCacheRefresh: failingRefresh,
            workOrderNoteRepository: deps.workOrderNoteRepository,
            workOrderPhotoRepository: deps.workOrderPhotoRepository,
            workOrderLocationRepository: deps.workOrderLocationRepository,
            signatureRepository: deps.signatureRepository,
            statusHistoryRepository: deps.statusHistoryRepository,
            editRequestRepository: deps.editRequestRepository,
            editRequestService: deps.editRequestService,
            customerSatisfactionRepository: deps.customerSatisfactionRepository,
            customerSatisfactionService: deps.customerSatisfactionService,
            notificationRepository: deps.notificationRepository,
            syncOperationRepository: deps.syncOperationRepository,
            syncConflictRepository: deps.syncConflictRepository,
            conflictResolver: deps.conflictResolver,
            networkReachability: deps.networkReachability,
            profileAccountService: deps.profileAccountService,
            storageDataSource: deps.storageDataSource
        )

        let vm = OperatorCustomerListViewModel(actor: operatorUser, dependencies: testDeps)
        await vm.load()

        if case .error = vm.phase {
            XCTFail("Customer list should not error when local customers exist")
        }
        XCTAssertEqual(vm.rows.map(\.id), [customer.id])
    }

    func testWizardLoadSelectionsSurvivesCustomerRemoteRefreshFailure() async throws {
        let container = DIContainer.mock()
        let reachability = await container.networkReachability as! FakeNetworkReachability
        await reachability.setReachable(true)

        let operatorUser = DomainFixtures.operatorUser()
        let customer = DomainFixtures.customer(
            id: CustomerID("cust-wizard"),
            name: "Wizard Müşteri",
            createdByUserId: operatorUser.id
        )
        let deps = container.makeOperatorDependencies()
        try await deps.customerRepository.save(customer)

        let failingRefresh = LocalDirectoryCacheRefresh(
            localUsers: container.userRepository,
            remoteUsers: container.remoteUserRepository,
            localCustomers: container.customerRepository,
            remoteCustomers: FailingListCustomerRepository(),
            localWorkOrders: container.workOrderRepository,
            remoteWorkOrders: container.remoteWorkOrderRepository,
            localNotifications: container.notificationRepository,
            remoteNotifications: container.remoteNotificationRepository,
            localCustomerSatisfactions: container.customerSatisfactionRepository,
            remoteCustomerSatisfactions: container.remoteCustomerSatisfactionRepository,
            syncOperationRepository: container.syncOperationRepository,
            reconciliationEngine: container.reconciliationEngine,
            networkReachability: reachability
        )
        let testDeps = OperatorDependencies(
            getWorkOrders: deps.getWorkOrders,
            getWorkOrder: deps.getWorkOrder,
            workOrderService: deps.workOrderService,
            customerService: deps.customerService,
            workOrderTemplateService: deps.workOrderTemplateService,
            customerRepository: deps.customerRepository,
            userRepository: deps.userRepository,
            localDirectoryCacheRefresh: failingRefresh,
            workOrderNoteRepository: deps.workOrderNoteRepository,
            workOrderPhotoRepository: deps.workOrderPhotoRepository,
            workOrderLocationRepository: deps.workOrderLocationRepository,
            signatureRepository: deps.signatureRepository,
            statusHistoryRepository: deps.statusHistoryRepository,
            editRequestRepository: deps.editRequestRepository,
            editRequestService: deps.editRequestService,
            customerSatisfactionRepository: deps.customerSatisfactionRepository,
            customerSatisfactionService: deps.customerSatisfactionService,
            notificationRepository: deps.notificationRepository,
            syncOperationRepository: deps.syncOperationRepository,
            syncConflictRepository: deps.syncConflictRepository,
            conflictResolver: deps.conflictResolver,
            networkReachability: deps.networkReachability,
            profileAccountService: deps.profileAccountService,
            storageDataSource: deps.storageDataSource
        )

        let vm = NewWorkOrderWizardViewModel(actor: operatorUser, dependencies: testDeps)
        await vm.loadSelections()

        if case .error = vm.phase {
            XCTFail("Wizard should not error when local customers exist")
        }
        XCTAssertEqual(vm.customers.map(\.id), [customer.id])
    }
}

private struct FailingListUserRepository: UserRepository {
    func fetch(id: UserID) async throws -> User {
        throw DomainError.notFound(entity: "User", id: id.rawValue)
    }

    func findByEmail(_ email: String) async throws -> User? { nil }

    func list(role: UserRole?, isActive: Bool?) async throws -> [User] {
        throw DomainError.notFound(entity: "User", id: "remote-list")
    }

    func save(_ user: User) async throws {}

    func updateSelfServiceProfile(_ user: User) async throws {}

    func delete(id: UserID) async throws {}
}

private struct FailingListCustomerRepository: CustomerRepository {
    func fetch(id: CustomerID) async throws -> Customer {
        throw DomainError.notFound(entity: "Customer", id: id.rawValue)
    }

    func list(searchText: String?) async throws -> [Customer] {
        throw DomainError.notFound(entity: "Customer", id: "remote-list")
    }

    func save(_ customer: Customer) async throws {}

    func delete(id: CustomerID) async throws {}
}

private struct FailingListWorkOrderRepository: WorkOrderRepository {
    func fetch(id: WorkOrderID) async throws -> WorkOrder {
        throw DomainError.notFound(entity: "WorkOrder", id: id.rawValue)
    }

    func list(filter: WorkOrderFilter) async throws -> [WorkOrder] {
        throw DomainError.notFound(entity: "WorkOrder", id: "remote-list")
    }

    func save(_ workOrder: WorkOrder) async throws {}

    func delete(id: WorkOrderID) async throws {}
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

private actor CountingFetchWorkOrderRepository: WorkOrderRepository {
    let inner: any WorkOrderRepository
    private(set) var fetchCallCount = 0

    init(inner: any WorkOrderRepository) {
        self.inner = inner
    }

    func fetch(id: WorkOrderID) async throws -> WorkOrder {
        fetchCallCount += 1
        return try await inner.fetch(id: id)
    }

    func list(filter: WorkOrderFilter) async throws -> [WorkOrder] {
        try await inner.list(filter: filter)
    }

    func save(_ workOrder: WorkOrder) async throws {
        try await inner.save(workOrder)
    }

    func delete(id: WorkOrderID) async throws {
        try await inner.delete(id: id)
    }
}

private actor CountingFetchCustomerRepository: CustomerRepository {
    let inner: any CustomerRepository
    private(set) var fetchCallCount = 0

    init(inner: any CustomerRepository) {
        self.inner = inner
    }

    func fetch(id: CustomerID) async throws -> Customer {
        fetchCallCount += 1
        return try await inner.fetch(id: id)
    }

    func list(searchText: String?) async throws -> [Customer] {
        try await inner.list(searchText: searchText)
    }

    func save(_ customer: Customer) async throws {
        try await inner.save(customer)
    }

    func delete(id: CustomerID) async throws {
        try await inner.delete(id: id)
    }
}

private actor ConcurrentTrackingCustomerRepository: CustomerRepository {
    let inner: any CustomerRepository
    let delayNanoseconds: UInt64
    private(set) var fetchCallCount = 0
    private(set) var maxConcurrentObserved = 0
    private var inFlight = 0

    init(inner: any CustomerRepository, delayNanoseconds: UInt64) {
        self.inner = inner
        self.delayNanoseconds = delayNanoseconds
    }

    func fetch(id: CustomerID) async throws -> Customer {
        inFlight += 1
        fetchCallCount += 1
        maxConcurrentObserved = max(maxConcurrentObserved, inFlight)
        defer {
            inFlight -= 1
        }
        try await Task.sleep(nanoseconds: delayNanoseconds)
        return try await inner.fetch(id: id)
    }

    func list(searchText: String?) async throws -> [Customer] {
        try await inner.list(searchText: searchText)
    }

    func save(_ customer: Customer) async throws {
        try await inner.save(customer)
    }

    func delete(id: CustomerID) async throws {
        try await inner.delete(id: id)
    }
}
