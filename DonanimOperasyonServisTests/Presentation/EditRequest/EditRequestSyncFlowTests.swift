import XCTest
@testable import DonanimOperasyonServis

@MainActor
final class TechnicianEditRequestFlowTests: XCTestCase {

    private var container: DIContainer!
    private var deps: TechnicianDependencies!
    private var tech: User!
    private var customer: Customer!
    private var completedOrder: WorkOrder!

    override func setUp() async throws {
        container = DIContainer.mock()
        deps = container.makeTechnicianDependencies()
        tech = DomainFixtures.technicianUser()
        customer = DomainFixtures.customer()
        completedOrder = DomainFixtures.workOrder(
            assignedTechnicianId: tech.id,
            customerId: customer.id,
            issueDescription: "Eski açıklama",
            status: .completed,
            completedAt: DomainFixtures.referenceDate
        )
        try await deps.customerRepository.save(customer)
        try await container.workOrderRepository.save(completedOrder)
    }

    func testCreateEditRequestFromDetailPersistsPendingRequest() async throws {
        let vm = TechnicianWorkOrderDetailViewModel(
            workOrderId: completedOrder.id,
            actor: tech,
            dependencies: deps
        )
        await vm.load()
        XCTAssertTrue(vm.canCreateEditRequest)

        await vm.submitEditRequest(requestedValue: "Yeni açıklama", reason: "Yanlış yazılmış")

        XCTAssertNil(vm.editRequestError)
        XCTAssertFalse(vm.showEditRequestSheet)
        let stored = try await container.editRequestRepository.list(for: completedOrder.id)
        XCTAssertEqual(stored.count, 1)
        XCTAssertEqual(stored.first?.status, .pending)
        XCTAssertEqual(stored.first?.requestedValue, "Yeni açıklama")
    }

    func testCreateEditRequestEnqueuesSyncCreate() async throws {
        let request = try await deps.editRequestService.createWithSync(
            actor: tech,
            orderId: completedOrder.id,
            field: .issueDescription,
            currentValue: "Eski açıklama",
            requestedValue: "Yeni açıklama",
            reason: "Düzeltme"
        )
        let ops = try await deps.syncOperationRepository.list(
            entityType: .editRequest,
            entityId: request.id.rawValue
        )
        XCTAssertTrue(ops.contains { $0.operationType == .create && $0.status == .pending })
    }

    func testCreateEditRequestRejectsNoChange() async throws {
        let vm = TechnicianWorkOrderDetailViewModel(
            workOrderId: completedOrder.id,
            actor: tech,
            dependencies: deps
        )
        await vm.load()
        await vm.submitEditRequest(requestedValue: "Eski açıklama", reason: "Aynı")

        XCTAssertNotNil(vm.editRequestError)
        let stored = try await container.editRequestRepository.list(for: completedOrder.id)
        XCTAssertTrue(stored.isEmpty)
    }

    func testCreateEditRequestRejectsEmptyReason() async throws {
        do {
            _ = try await deps.editRequestService.createWithSync(
                actor: tech,
                orderId: completedOrder.id,
                field: .issueDescription,
                currentValue: "Eski",
                requestedValue: "Yeni",
                reason: "   "
            )
            XCTFail("Expected empty reason to fail")
        } catch let error as DomainError {
            XCTAssertEqual(error, .invalidData(reason: "editRequest.reasonEmpty"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testCreateEditRequestBlockedOnNonCompletedOrder() async throws {
        let open = DomainFixtures.workOrder(
            assignedTechnicianId: tech.id,
            customerId: customer.id,
            status: .inProgress
        )
        try await container.workOrderRepository.save(open)
        let vm = TechnicianWorkOrderDetailViewModel(
            workOrderId: open.id,
            actor: tech,
            dependencies: deps
        )
        await vm.load()
        XCTAssertFalse(vm.canCreateEditRequest)
    }
}

@MainActor
final class OperatorEditRequestSyncTests: XCTestCase {

    private var container: DIContainer!
    private var deps: OperatorDependencies!
    private var tech: User!
    private var operatorUser: User!
    private var completedOrder: WorkOrder!
    private var pendingRequest: EditRequest!

    override func setUp() async throws {
        container = DIContainer.mock()
        deps = container.makeOperatorDependencies()
        tech = DomainFixtures.technicianUser()
        operatorUser = DomainFixtures.operatorUser()
        completedOrder = DomainFixtures.workOrder(
            assignedTechnicianId: tech.id,
            issueDescription: "Eski açıklama",
            status: .completed,
            completedAt: DomainFixtures.referenceDate
        )
        pendingRequest = DomainFixtures.editRequest(
            workOrderId: completedOrder.id,
            requestedByUserId: tech.id,
            field: .issueDescription,
            currentValue: "Eski açıklama",
            requestedValue: "Yeni açıklama"
        )
        try await deps.userRepository.save(tech)
        try await deps.userRepository.save(operatorUser)
        try await container.workOrderRepository.save(completedOrder)
        try await deps.editRequestRepository.save(pendingRequest)
    }

    func testApproveEnqueuesEditRequestSyncUpdate() async throws {
        _ = try await deps.editRequestService.approveWithSync(
            actor: operatorUser,
            requestId: pendingRequest.id
        )
        let ops = try await deps.syncOperationRepository.list(
            entityType: .editRequest,
            entityId: pendingRequest.id.rawValue
        )
        XCTAssertTrue(ops.contains { $0.operationType == .update && $0.status == .pending })

        let stored = try await deps.editRequestRepository.fetch(id: pendingRequest.id)
        XCTAssertEqual(stored.status, .approved)
        let order = try await container.workOrderRepository.fetch(id: completedOrder.id)
        XCTAssertEqual(order.issueDescription, "Yeni açıklama")
    }

    func testRejectEnqueuesEditRequestSyncUpdate() async throws {
        _ = try await deps.editRequestService.rejectWithSync(
            actor: operatorUser,
            requestId: pendingRequest.id
        )
        let ops = try await deps.syncOperationRepository.list(
            entityType: .editRequest,
            entityId: pendingRequest.id.rawValue
        )
        XCTAssertTrue(ops.contains { $0.operationType == .update && $0.status == .pending })

        let stored = try await deps.editRequestRepository.fetch(id: pendingRequest.id)
        XCTAssertEqual(stored.status, .rejected)
        let order = try await container.workOrderRepository.fetch(id: completedOrder.id)
        XCTAssertEqual(order.issueDescription, "Eski açıklama")
    }

    func testApproveViaDetailViewModelEnqueuesSync() async throws {
        let vm = OperatorEditRequestDetailViewModel(
            requestId: pendingRequest.id,
            actor: operatorUser,
            dependencies: deps
        )
        await vm.load()
        await vm.approve()

        XCTAssertEqual(vm.phase, .loaded)
        XCTAssertEqual(vm.request?.status, .approved)
        let ops = try await deps.syncOperationRepository.list(
            entityType: .editRequest,
            entityId: pendingRequest.id.rawValue
        )
        XCTAssertTrue(ops.contains { $0.operationType == .update && $0.status == .pending })
    }
}
