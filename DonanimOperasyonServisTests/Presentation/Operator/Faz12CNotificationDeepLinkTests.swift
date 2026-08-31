import XCTest
@testable import DonanimOperasyonServis

@MainActor
final class Faz12CNotificationDeepLinkTests: XCTestCase {

    private var container: DIContainer!
    private var deps: OperatorDependencies!
    private var operatorUser: User!

    override func setUp() async throws {
        container = DIContainer.mock()
        deps = container.makeOperatorDependencies()
        operatorUser = DomainFixtures.operatorUser()
        try await deps.userRepository.save(operatorUser)
    }

    func testWorkOrderNotificationOpensCorrectWorkOrderDetail() async throws {
        let order = DomainFixtures.workOrder(id: WorkOrderID("wo-deeplink-1"))
        try await container.workOrderRepository.save(order)
        try await deps.notificationRepository.save(
            DomainFixtures.notification(
                id: NotificationID("n-wo"),
                recipientUserId: operatorUser.id,
                type: .workOrderAssigned,
                relatedWorkOrderId: order.id
            )
        )

        let vm = OperatorNotificationListViewModel(actor: operatorUser, dependencies: deps)
        await vm.load()

        let outcome = await vm.open(NotificationID("n-wo"))
        XCTAssertEqual(outcome, .workOrderDetail(order.id))
        XCTAssertNil(vm.fallbackMessage)
    }

    func testEditRequestNotificationOpensCorrectEditRequestDetail() async throws {
        let order = DomainFixtures.workOrder(status: .completed)
        let technician = DomainFixtures.technicianUser()
        try await deps.userRepository.save(technician)
        try await container.workOrderRepository.save(order)

        let request = DomainFixtures.editRequest(
            id: EditRequestID("er-deeplink-1"),
            workOrderId: order.id,
            requestedByUserId: technician.id
        )
        try await deps.editRequestRepository.save(request)
        try await deps.notificationRepository.save(
            DomainFixtures.notification(
                id: NotificationID("n-er"),
                recipientUserId: operatorUser.id,
                type: .editRequestCreated,
                relatedEditRequestId: request.id
            )
        )

        let vm = OperatorNotificationListViewModel(actor: operatorUser, dependencies: deps)
        await vm.load()

        let outcome = await vm.open(NotificationID("n-er"))
        XCTAssertEqual(outcome, .editRequestDetail(request.id))
        XCTAssertNil(vm.fallbackMessage)
    }

    func testOpenMarksNotificationAsRead() async throws {
        let order = DomainFixtures.workOrder()
        try await container.workOrderRepository.save(order)
        try await deps.notificationRepository.save(
            DomainFixtures.notification(
                id: NotificationID("n-read"),
                recipientUserId: operatorUser.id,
                type: .workOrderStatusChanged,
                relatedWorkOrderId: order.id,
                isRead: false
            )
        )

        let vm = OperatorNotificationListViewModel(actor: operatorUser, dependencies: deps)
        await vm.load()
        XCTAssertFalse(vm.notifications[0].isRead)

        _ = await vm.open(NotificationID("n-read"))

        XCTAssertTrue(vm.notifications[0].isRead)
        let stored = try await deps.notificationRepository.list(for: operatorUser.id, unreadOnly: false)
        XCTAssertEqual(stored.first?.isRead, true)
    }

    func testMissingRelatedWorkOrderShowsFallback() async throws {
        try await deps.notificationRepository.save(
            DomainFixtures.notification(
                id: NotificationID("n-missing-wo"),
                recipientUserId: operatorUser.id,
                type: .workOrderCompleted,
                relatedWorkOrderId: WorkOrderID("wo-does-not-exist")
            )
        )

        let vm = OperatorNotificationListViewModel(actor: operatorUser, dependencies: deps)
        await vm.load()

        let outcome = await vm.open(NotificationID("n-missing-wo"))
        XCTAssertEqual(outcome, .missingRelated)
        XCTAssertEqual(vm.fallbackMessage, "İlişkili kayıt bulunamadı.")
        XCTAssertEqual(vm.phase, .loaded)
    }

    func testMissingRelatedEditRequestShowsFallback() async throws {
        try await deps.notificationRepository.save(
            DomainFixtures.notification(
                id: NotificationID("n-missing-er"),
                recipientUserId: operatorUser.id,
                type: .editRequestApproved,
                relatedEditRequestId: EditRequestID("er-does-not-exist")
            )
        )

        let vm = OperatorNotificationListViewModel(actor: operatorUser, dependencies: deps)
        await vm.load()

        let outcome = await vm.open(NotificationID("n-missing-er"))
        XCTAssertEqual(outcome, .missingRelated)
        XCTAssertEqual(vm.fallbackMessage, "İlişkili kayıt bulunamadı.")
        XCTAssertEqual(vm.phase, .loaded)
    }

    func testSystemNotificationMarksReadOnly() async throws {
        try await deps.notificationRepository.save(
            DomainFixtures.notification(
                id: NotificationID("n-system"),
                recipientUserId: operatorUser.id,
                type: .system,
                isRead: false
            )
        )

        let vm = OperatorNotificationListViewModel(actor: operatorUser, dependencies: deps)
        await vm.load()

        let outcome = await vm.open(NotificationID("n-system"))
        XCTAssertEqual(outcome, .markedReadOnly)
        XCTAssertNil(vm.fallbackMessage)
        XCTAssertTrue(vm.notifications[0].isRead)
        XCTAssertEqual(vm.phase, .loaded)
    }

    func testDuplicateTapRemainsStableAndNavigable() async throws {
        let order = DomainFixtures.workOrder(id: WorkOrderID("wo-dup"))
        try await container.workOrderRepository.save(order)
        try await deps.notificationRepository.save(
            DomainFixtures.notification(
                id: NotificationID("n-dup"),
                recipientUserId: operatorUser.id,
                type: .workOrderAssigned,
                relatedWorkOrderId: order.id
            )
        )

        let vm = OperatorNotificationListViewModel(actor: operatorUser, dependencies: deps)
        await vm.load()

        let first = await vm.open(NotificationID("n-dup"))
        let second = await vm.open(NotificationID("n-dup"))

        XCTAssertEqual(first, .workOrderDetail(order.id))
        XCTAssertEqual(second, .workOrderDetail(order.id))
        XCTAssertEqual(vm.phase, .loaded)
        XCTAssertTrue(vm.notifications[0].isRead)
    }

    func testOpenDoesNotLeaveLoadingState() async throws {
        let order = DomainFixtures.workOrder()
        try await container.workOrderRepository.save(order)
        try await deps.notificationRepository.save(
            DomainFixtures.notification(
                id: NotificationID("n-noload"),
                recipientUserId: operatorUser.id,
                relatedWorkOrderId: order.id
            )
        )

        let vm = OperatorNotificationListViewModel(actor: operatorUser, dependencies: deps)
        await vm.load()
        XCTAssertEqual(vm.phase, .loaded)

        _ = await vm.open(NotificationID("n-noload"))
        XCTAssertNotEqual(vm.phase, .loading)
        XCTAssertEqual(vm.phase, .loaded)
    }

    func testCancellationDuringLoadDoesNotLeaveLoading() async throws {
        let vm = OperatorNotificationListViewModel(actor: operatorUser, dependencies: deps)
        let task = Task { await vm.load() }
        task.cancel()
        await task.value
        XCTAssertNotEqual(vm.phase, .loading)
    }

    func testEmptyLoadedAndErrorLifecycleRemainIntact() async throws {
        let emptyVM = OperatorNotificationListViewModel(actor: operatorUser, dependencies: deps)
        await emptyVM.load()
        XCTAssertEqual(emptyVM.phase, .empty)

        try await deps.notificationRepository.save(
            DomainFixtures.notification(recipientUserId: operatorUser.id)
        )
        await emptyVM.load()
        XCTAssertEqual(emptyVM.phase, .loaded)
        XCTAssertFalse(emptyVM.notifications.isEmpty)
    }

    func testWorkOrderIdTakesPriorityOverEditRequestId() async throws {
        let order = DomainFixtures.workOrder(id: WorkOrderID("wo-priority"))
        let technician = DomainFixtures.technicianUser()
        try await deps.userRepository.save(technician)
        try await container.workOrderRepository.save(order)

        let request = DomainFixtures.editRequest(
            id: EditRequestID("er-priority"),
            workOrderId: order.id,
            requestedByUserId: technician.id
        )
        try await deps.editRequestRepository.save(request)

        try await deps.notificationRepository.save(
            DomainFixtures.notification(
                id: NotificationID("n-both"),
                recipientUserId: operatorUser.id,
                type: .editRequestCreated,
                relatedWorkOrderId: order.id,
                relatedEditRequestId: request.id
            )
        )

        let vm = OperatorNotificationListViewModel(actor: operatorUser, dependencies: deps)
        await vm.load()

        let outcome = await vm.open(NotificationID("n-both"))
        XCTAssertEqual(outcome, .workOrderDetail(order.id))
    }
}
