import XCTest
@testable import DonanimOperasyonServis

@MainActor
final class Faz12DCreateListVisibilityTests: XCTestCase {

    private var container: DIContainer!
    private var deps: OperatorDependencies!
    private var operatorUser: User!
    private var customer: Customer!
    private var technician: User!

    override func setUp() async throws {
        container = DIContainer.mock()
        deps = container.makeOperatorDependencies()
        operatorUser = DomainFixtures.operatorUser()
        customer = DomainFixtures.customer(
            id: CustomerID("cust-xyz"),
            name: "XYZ Mağaza",
            createdByUserId: operatorUser.id
        )
        technician = DomainFixtures.technicianUser(
            id: UserID("tech-ayse"),
            email: "ayse@example.com",
            fullName: "Ayşe Demir"
        )
        try await deps.userRepository.save(operatorUser)
        try await deps.userRepository.save(technician)
        try await deps.customerRepository.save(customer)
    }

    func testCreateWithSyncIsVisibleToGetWorkOrderAndGetWorkOrders() async throws {
        let created = try await deps.workOrderService.createWithSync(
            actor: operatorUser,
            request: DomainFixtures.newWorkOrderRequest(
                id: WorkOrderID("wo-created-1"),
                workOrderNumber: "WO-144896",
                assignedTechnicianId: technician.id,
                customerId: customer.id
            )
        )

        let fetched = try await deps.getWorkOrder.execute(actor: operatorUser, id: created.id)
        XCTAssertEqual(fetched.id, created.id)

        let listed = try await deps.getWorkOrders.execute(actor: operatorUser, filter: .all)
        XCTAssertTrue(listed.contains(where: { $0.id == created.id }))
    }

    func testCreatedWorkOrderAppearsInDefaultAllListPresentation() async throws {
        let created = try await deps.workOrderService.createWithSync(
            actor: operatorUser,
            request: NewWorkOrderRequest(
                id: WorkOrderID("wo-high-1"),
                workOrderNumber: "WO-144896",
                assignedTechnicianId: technician.id,
                customerId: customer.id,
                workType: .installation,
                deviceCategory: .pos,
                deviceBrand: "Ingenico",
                deviceModel: "DX8000",
                serialNumber: "SN-144896",
                priority: .high,
                scheduledDate: Date(),
                scheduledTimeRange: nil
            )
        )

        let listVM = OperatorWorkOrderListViewModel(actor: operatorUser, dependencies: deps)
        await listVM.resetToDefaultListingAndLoad()

        XCTAssertEqual(listVM.selectedFilter, .all)
        XCTAssertNil(listVM.priorityFilter)
        XCTAssertEqual(listVM.phase, .loaded)
        XCTAssertTrue(listVM.cards.contains(where: { $0.id == created.id.rawValue }))
        XCTAssertEqual(
            listVM.cards.first(where: { $0.id == created.id.rawValue })?.technicianName,
            technician.fullName
        )
        XCTAssertEqual(
            listVM.cards.first(where: { $0.id == created.id.rawValue })?.priority,
            .high
        )
    }

    func testPendingSyncWorkOrderStillAppearsInList() async throws {
        let created = try await deps.workOrderService.createWithSync(
            actor: operatorUser,
            request: DomainFixtures.newWorkOrderRequest(
                id: WorkOrderID("wo-pending-sync"),
                assignedTechnicianId: technician.id,
                customerId: customer.id
            )
        )

        let ops = try await deps.syncOperationRepository.list(
            entityType: .workOrder,
            entityId: created.id.rawValue
        )
        XCTAssertTrue(ops.contains { $0.status == .pending || $0.operationType == .create })

        let listVM = OperatorWorkOrderListViewModel(actor: operatorUser, dependencies: deps)
        await listVM.load()
        XCTAssertTrue(listVM.cards.contains(where: { $0.id == created.id.rawValue }))
    }

    func testStickyUrgentPriorityFilterHidesHighPriorityUntilReset() async throws {
        let high = try await deps.workOrderService.createWithSync(
            actor: operatorUser,
            request: NewWorkOrderRequest(
                id: WorkOrderID("wo-high-sticky"),
                workOrderNumber: "WO-HIGH",
                assignedTechnicianId: technician.id,
                customerId: customer.id,
                workType: .repair,
                deviceCategory: .pos,
                deviceBrand: "Brand",
                deviceModel: "Model",
                serialNumber: "SN-H",
                priority: .high,
                scheduledDate: Date(),
                scheduledTimeRange: nil
            )
        )
        _ = try await deps.workOrderService.createWithSync(
            actor: operatorUser,
            request: NewWorkOrderRequest(
                id: WorkOrderID("wo-urgent-sticky"),
                workOrderNumber: "WO-URG",
                assignedTechnicianId: technician.id,
                customerId: customer.id,
                workType: .repair,
                deviceCategory: .pos,
                deviceBrand: "Brand",
                deviceModel: "Model",
                serialNumber: "SN-U",
                priority: .urgent,
                scheduledDate: Date(),
                scheduledTimeRange: nil
            )
        )

        let listVM = OperatorWorkOrderListViewModel(actor: operatorUser, dependencies: deps)
        await listVM.showUrgentPriorityOnly()
        XCTAssertEqual(listVM.selectedFilter, .all)
        XCTAssertEqual(listVM.priorityFilter, .urgent)
        XCTAssertFalse(listVM.cards.contains(where: { $0.id == high.id.rawValue }))

        await listVM.resetToDefaultListingAndLoad()
        XCTAssertNil(listVM.priorityFilter)
        XCTAssertTrue(listVM.cards.contains(where: { $0.id == high.id.rawValue }))
    }

    func testSelectingAllFilterClearsUrgentPriorityScope() async throws {
        let high = try await deps.workOrderService.createWithSync(
            actor: operatorUser,
            request: NewWorkOrderRequest(
                id: WorkOrderID("wo-high-clear"),
                workOrderNumber: "WO-HC",
                assignedTechnicianId: technician.id,
                customerId: customer.id,
                workType: .installation,
                deviceCategory: .pos,
                deviceBrand: "Brand",
                deviceModel: "Model",
                serialNumber: "SN-HC",
                priority: .high,
                scheduledDate: Date(),
                scheduledTimeRange: nil
            )
        )

        let listVM = OperatorWorkOrderListViewModel(actor: operatorUser, dependencies: deps)
        await listVM.showUrgentPriorityOnly()
        XCTAssertFalse(listVM.cards.contains(where: { $0.id == high.id.rawValue }))

        await listVM.selectFilter(.all)
        XCTAssertNil(listVM.priorityFilter)
        XCTAssertTrue(listVM.cards.contains(where: { $0.id == high.id.rawValue }))
    }

    func testCreateThenListRefreshShowsAssignedTechnicianAndPriority() async throws {
        let wizard = NewWorkOrderWizardViewModel(actor: operatorUser, dependencies: deps)
        wizard.selectWorkType(.installation)
        wizard.selectCustomer(customer)
        wizard.draft.deviceBrand = "Ingenico"
        wizard.draft.deviceModel = "DX8000"
        wizard.draft.serialNumber = "SN-REG"
        wizard.draft.priority = .high
        wizard.selectTechnician(technician)
        await wizard.submit()

        guard case .success(let id) = wizard.phase else {
            return XCTFail("expected create success")
        }

        let listVM = OperatorWorkOrderListViewModel(actor: operatorUser, dependencies: deps)
        await listVM.resetToDefaultListingAndLoad()

        let card = listVM.cards.first(where: { $0.id == id.rawValue })
        XCTAssertNotNil(card)
        XCTAssertEqual(card?.technicianName, "Ayşe Demir")
        XCTAssertEqual(card?.priority, .high)
    }

    func testExistingWorkOrdersRemainVisibleAfterCreate() async throws {
        let existing = DomainFixtures.workOrder(
            id: WorkOrderID("wo-existing"),
            workOrderNumber: "WO-EXIST",
            assignedTechnicianId: technician.id,
            customerId: customer.id,
            priority: .normal,
            status: .assigned
        )
        try await container.workOrderRepository.save(existing)

        let created = try await deps.workOrderService.createWithSync(
            actor: operatorUser,
            request: DomainFixtures.newWorkOrderRequest(
                id: WorkOrderID("wo-new-after"),
                assignedTechnicianId: technician.id,
                customerId: customer.id
            )
        )

        let listVM = OperatorWorkOrderListViewModel(actor: operatorUser, dependencies: deps)
        await listVM.load()

        XCTAssertTrue(listVM.cards.contains(where: { $0.id == existing.id.rawValue }))
        XCTAssertTrue(listVM.cards.contains(where: { $0.id == created.id.rawValue }))
    }

    func testListCancellationSettlesAwayFromSpinner() async throws {
        let listVM = OperatorWorkOrderListViewModel(actor: operatorUser, dependencies: deps)
        let task = Task { await listVM.load() }
        task.cancel()
        await task.value
        XCTAssertNotEqual(listVM.phase, .loading)
    }
}
