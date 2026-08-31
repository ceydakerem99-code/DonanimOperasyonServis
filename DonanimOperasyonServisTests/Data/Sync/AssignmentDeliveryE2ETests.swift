import XCTest
@testable import DonanimOperasyonServis

/// End-to-end: operator assign → sync queue → remote → technician cache + notifications.
final class AssignmentDeliveryE2ETests: XCTestCase {

    private var container: DIContainer!
    private var reachability: FakeNetworkReachability!

    override func setUp() async throws {
        container = DIContainer.mock()
        reachability = await container.networkReachability as? FakeNetworkReachability
    }

    private func signInAsOperator(_ operatorUser: User) {
        guard let auth = container.authService as? FakeFirebaseAuthService else { return }
        auth.register(email: operatorUser.email, uid: operatorUser.id.rawValue)
        auth.setUID(operatorUser.id.rawValue, email: operatorUser.email)
    }

    func testAssignmentEnqueuesWorkOrderUpdateAndNotificationSync() async throws {
        await reachability.setReachable(true)
        let operatorUser = DomainFixtures.operatorUser()
        let techA = DomainFixtures.technicianUser(id: UserID("tech-a"), email: "a@example.com")
        let mehmet = DomainFixtures.mehmetTechnician()
        let customer = DomainFixtures.customer(createdByUserId: operatorUser.id)
        let order = DomainFixtures.workOrder(
            id: WorkOrderID("wo-assign-e2e"),
            assignedTechnicianId: techA.id,
            customerId: customer.id,
            status: .assigned
        )

        let deps = container.makeOperatorDependencies()
        try await deps.userRepository.save(operatorUser)
        try await deps.userRepository.save(techA)
        try await deps.userRepository.save(mehmet)
        try await deps.customerRepository.save(customer)
        try await container.workOrderRepository.save(order)
        signInAsOperator(operatorUser)

        _ = try await deps.workOrderService.assignWithSync(
            actor: operatorUser,
            orderId: order.id,
            newTechnicianId: mehmet.id
        )

        // assignWithSync auto-drains when online; drain prunes succeeded rows via
        // deleteCompleted(), so assert remote/local outcomes — not queue row presence.
        let remoteOrder = try await container.remoteWorkOrderRepository.fetch(id: order.id)
        XCTAssertEqual(remoteOrder.assignedTechnicianId, mehmet.id)

        let localNotifications = try await deps.notificationRepository.list(
            for: mehmet.id,
            unreadOnly: false
        )
        let assignmentNotif = try XCTUnwrap(
            localNotifications.first { $0.type == .workOrderAssigned && $0.relatedWorkOrderId == order.id }
        )

        let remoteNotifications = try await container.remoteNotificationRepository.list(
            for: mehmet.id,
            unreadOnly: false
        )
        XCTAssertTrue(remoteNotifications.contains { $0.id == assignmentNotif.id })

        let pending = try await deps.syncOperationRepository.fetchPending(now: Date())
        XCTAssertTrue(pending.isEmpty)
    }

    func testOperatorAssignSyncsToRemoteAndMehmetSeesWorkOrder() async throws {
        await reachability.setReachable(true)
        let operatorUser = DomainFixtures.operatorUser()
        let techA = DomainFixtures.technicianUser(id: UserID("tech-a"), email: "a@example.com")
        let mehmet = DomainFixtures.mehmetTechnician()
        let customer = DomainFixtures.customer(
            id: CustomerID("cust-assign-e2e"),
            createdByUserId: operatorUser.id
        )
        let order = DomainFixtures.workOrder(
            id: WorkOrderID("wo-mehmet-visible"),
            assignedTechnicianId: techA.id,
            customerId: customer.id,
            status: .assigned
        )

        let operatorDeps = container.makeOperatorDependencies()
        try await operatorDeps.userRepository.save(operatorUser)
        try await operatorDeps.userRepository.save(techA)
        try await operatorDeps.userRepository.save(mehmet)
        try await operatorDeps.customerRepository.save(customer)
        try await container.workOrderRepository.save(order)
        signInAsOperator(operatorUser)

        _ = try await operatorDeps.workOrderService.assignWithSync(
            actor: operatorUser,
            orderId: order.id,
            newTechnicianId: mehmet.id
        )

        let remoteOrder = try await container.remoteWorkOrderRepository.fetch(id: order.id)
        XCTAssertEqual(remoteOrder.assignedTechnicianId, mehmet.id)

        let refresh = container.localDirectoryCacheRefresh
        await refresh.refreshTechnicianAssignments(technicianId: mehmet.id)

        let mehmetOrders = try await container.workOrderRepository.list(
            filter: WorkOrderFilter(assignedTechnicianId: mehmet.id)
        )
        XCTAssertTrue(mehmetOrders.contains { $0.id == order.id })
    }

    func testMehmetReceivesAssignmentNotificationAfterRemoteRefresh() async throws {
        await reachability.setReachable(true)
        let operatorUser = DomainFixtures.operatorUser()
        let mehmet = DomainFixtures.mehmetTechnician()
        let customer = DomainFixtures.customer(createdByUserId: operatorUser.id)
        let order = DomainFixtures.workOrder(
            id: WorkOrderID("wo-mehmet-notif"),
            assignedTechnicianId: mehmet.id,
            customerId: customer.id,
            status: .assigned
        )
        let notification = DomainFixtures.notification(
            id: NotificationID("notif-mehmet-assign"),
            recipientUserId: mehmet.id,
            type: .workOrderAssigned,
            relatedWorkOrderId: order.id
        )

        try await container.remoteWorkOrderRepository.save(order)
        try await container.remoteNotificationRepository.save(notification)

        let refresh = container.localDirectoryCacheRefresh
        await refresh.refreshNotifications(recipientUserId: mehmet.id)

        let local = try await container.notificationRepository.list(for: mehmet.id, unreadOnly: false)
        XCTAssertTrue(local.contains { $0.id == notification.id })
    }

    func testOfflineAssignmentDrainsWhenOperatorComesOnline() async throws {
        await reachability.setReachable(false)
        let operatorUser = DomainFixtures.operatorUser()
        let techA = DomainFixtures.technicianUser(id: UserID("tech-a"), email: "a@example.com")
        let mehmet = DomainFixtures.mehmetTechnician()
        let customer = DomainFixtures.customer(createdByUserId: operatorUser.id)
        let order = DomainFixtures.workOrder(
            id: WorkOrderID("wo-offline-assign"),
            assignedTechnicianId: techA.id,
            customerId: customer.id
        )

        let operatorDeps = container.makeOperatorDependencies()
        try await operatorDeps.userRepository.save(operatorUser)
        try await operatorDeps.userRepository.save(techA)
        try await operatorDeps.userRepository.save(mehmet)
        try await operatorDeps.customerRepository.save(customer)
        try await container.workOrderRepository.save(order)
        signInAsOperator(operatorUser)

        _ = try await operatorDeps.workOrderService.assignWithSync(
            actor: operatorUser,
            orderId: order.id,
            newTechnicianId: mehmet.id
        )

        let pendingBefore = try await operatorDeps.syncOperationRepository.fetchPending(now: Date())
        XCTAssertFalse(pendingBefore.isEmpty)

        await reachability.setReachable(true)
        _ = try await container.syncManager.syncPending()

        let remoteOrder = try await container.remoteWorkOrderRepository.fetch(id: order.id)
        XCTAssertEqual(remoteOrder.assignedTechnicianId, mehmet.id)
    }

    func testNotificationRefreshDoesNotDuplicateExistingRows() async throws {
        await reachability.setReachable(true)
        let mehmet = DomainFixtures.mehmetTechnician()
        let notification = DomainFixtures.notification(
            id: NotificationID("notif-dedupe"),
            recipientUserId: mehmet.id,
            type: .workOrderAssigned
        )

        try await container.notificationRepository.save(notification)
        try await container.remoteNotificationRepository.save(notification)

        let refresh = container.localDirectoryCacheRefresh
        await refresh.refreshNotifications(recipientUserId: mehmet.id)
        await refresh.refreshNotifications(recipientUserId: mehmet.id)

        let local = try await container.notificationRepository.list(for: mehmet.id, unreadOnly: false)
        XCTAssertEqual(local.filter { $0.id == notification.id }.count, 1)
    }

    @MainActor
    func testTechnicianNotificationListLoadsAfterRemoteRefresh() async throws {
        await reachability.setReachable(true)
        let mehmet = DomainFixtures.mehmetTechnician()
        let order = DomainFixtures.workOrder(
            id: WorkOrderID("wo-notif-list"),
            assignedTechnicianId: mehmet.id
        )
        let notification = DomainFixtures.notification(
            id: NotificationID("notif-list"),
            recipientUserId: mehmet.id,
            type: .workOrderAssigned,
            relatedWorkOrderId: order.id
        )

        try await container.userRepository.save(mehmet)
        try await container.remoteNotificationRepository.save(notification)

        let deps = container.makeTechnicianDependencies()
        let vm = TechnicianNotificationListViewModel(actor: mehmet, dependencies: deps)
        await vm.load()

        XCTAssertEqual(vm.phase, .loaded)
        XCTAssertEqual(vm.notifications.count, 1)
        XCTAssertEqual(vm.notifications.first?.relatedWorkOrderId, order.id)
    }
}
