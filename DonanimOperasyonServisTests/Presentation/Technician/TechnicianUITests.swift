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
            _ = try await deps.workOrderService.complete(actor: tech, orderId: order.id)
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
}
