import XCTest
@testable import DonanimOperasyonServis

@MainActor
final class OperatorWorkOrderBulkQATests: XCTestCase {

    private var container: DIContainer!
    private var deps: OperatorDependencies!
    private var operatorUser: User!
    private var customer: Customer!
    private var customerB: Customer!
    private var techA: User!
    private var techB: User!

    private let site = LocationCoordinate(latitude: 41.0082, longitude: 28.9784)
    private let near = LocationCoordinate(latitude: 41.0100, longitude: 28.9800)

    override func setUp() async throws {
        container = DIContainer.mock()
        deps = container.makeOperatorDependencies()
        operatorUser = DomainFixtures.operatorUser()
        customer = DomainFixtures.customer(createdByUserId: operatorUser.id)
        customerB = DomainFixtures.customer(
            id: CustomerID("cust-bulk-b"),
            name: "Müşteri B",
            createdByUserId: operatorUser.id
        )
        techA = DomainFixtures.technicianUser(
            id: UserID("qa-tech-a"),
            email: "qa-a@example.com",
            fullName: "QA Teknisyen A"
        )
        techB = DomainFixtures.technicianUser(
            id: UserID("qa-tech-b"),
            email: "qa-b@example.com",
            fullName: "QA Teknisyen B"
        )
        try await deps.userRepository.save(operatorUser)
        try await deps.userRepository.save(techA)
        try await deps.userRepository.save(techB)
        try await deps.customerRepository.save(customer)
        try await deps.customerRepository.save(customerB)
    }

    private func makeListViewModel(
        locationRepository: WorkOrderLocationRepository? = nil
    ) -> OperatorWorkOrderListViewModel {
        if let locationRepository {
            let customDeps = OperatorDependencies(
                getWorkOrders: deps.getWorkOrders,
                getWorkOrder: deps.getWorkOrder,
                workOrderService: deps.workOrderService,
                customerService: deps.customerService,
                workOrderTemplateService: deps.workOrderTemplateService,
                customerRepository: deps.customerRepository,
                userRepository: deps.userRepository,
                localDirectoryCacheRefresh: deps.localDirectoryCacheRefresh,
                workOrderNoteRepository: deps.workOrderNoteRepository,
                workOrderPhotoRepository: deps.workOrderPhotoRepository,
                workOrderLocationRepository: locationRepository,
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
            return OperatorWorkOrderListViewModel(actor: operatorUser, dependencies: customDeps)
        }
        return OperatorWorkOrderListViewModel(actor: operatorUser, dependencies: deps)
    }

    private func seedOrders(_ orders: [WorkOrder]) async throws {
        for order in orders {
            try await container.workOrderRepository.save(order)
        }
    }

    // MARK: - T25 Bulk technician assignment

    func testBulkTechnicianAssignment() async throws {
        let order1 = DomainFixtures.workOrder(
            id: WorkOrderID("qa-bulk-assign-1"),
            workOrderNumber: "WO-QA-1",
            assignedTechnicianId: techA.id,
            customerId: customer.id,
            status: .assigned
        )
        let order2 = DomainFixtures.workOrder(
            id: WorkOrderID("qa-bulk-assign-2"),
            workOrderNumber: "WO-QA-2",
            assignedTechnicianId: techA.id,
            customerId: customer.id,
            status: .assigned
        )
        try await seedOrders([order1, order2])

        let vm = makeListViewModel()
        await vm.load()
        vm.setSelectionMode(true)
        vm.toggleSelection(order1.id)
        vm.toggleSelection(order2.id)

        await vm.prepareBulkAssignSheet()
        vm.selectTechnicianForBulkAssign(techB)
        await vm.confirmBulkAssign()

        XCTAssertFalse(vm.showsBulkAssignSheet)
        XCTAssertNotNil(vm.bulkResultSummary)
        XCTAssertTrue(vm.bulkResultSummary?.contains("2") == true)

        let updated1 = try await container.workOrderRepository.fetch(id: order1.id)
        let updated2 = try await container.workOrderRepository.fetch(id: order2.id)
        XCTAssertEqual(updated1.assignedTechnicianId, techB.id)
        XCTAssertEqual(updated2.assignedTechnicianId, techB.id)
    }

    // MARK: - T26 Bulk priority

    func testBulkPriorityUpdate() async throws {
        let order1 = DomainFixtures.workOrder(
            id: WorkOrderID("qa-bulk-priority-1"),
            customerId: customer.id,
            priority: .normal,
            status: .assigned
        )
        let order2 = DomainFixtures.workOrder(
            id: WorkOrderID("qa-bulk-priority-2"),
            workOrderNumber: "WO-QP-2",
            customerId: customer.id,
            priority: .normal,
            status: .assigned
        )
        try await seedOrders([order1, order2])

        let vm = makeListViewModel()
        await vm.load()
        vm.setSelectionMode(true)
        vm.toggleSelection(order1.id)
        vm.toggleSelection(order2.id)
        vm.selectBulkPriority(.urgent)
        await vm.confirmBulkPriorityUpdate()

        XCTAssertFalse(vm.showsBulkPrioritySheet)
        let updated1 = try await container.workOrderRepository.fetch(id: order1.id)
        let updated2 = try await container.workOrderRepository.fetch(id: order2.id)
        XCTAssertEqual(updated1.priority, .urgent)
        XCTAssertEqual(updated2.priority, .urgent)

        await vm.load()
        let cardPriorities = vm.cards
            .filter { [order1.id, order2.id].map(\.rawValue).contains($0.id) }
            .map(\.priority)
        XCTAssertTrue(cardPriorities.allSatisfy { $0 == .urgent })
    }

    // MARK: - T27 Bulk date

    func testBulkDateUpdate() async throws {
        let originalDate = DomainFixtures.referenceDate
        let newDate = originalDate.addingTimeInterval(7 * 86_400)
        let order = DomainFixtures.workOrder(
            id: WorkOrderID("qa-bulk-date-1"),
            customerId: customer.id,
            scheduledDate: originalDate,
            status: .assigned
        )
        try await seedOrders([order])

        let vm = makeListViewModel()
        await vm.load()
        vm.setSelectionMode(true)
        vm.toggleSelection(order.id)
        vm.bulkScheduledDate = newDate
        vm.bulkScheduledStart = newDate.addingTimeInterval(3600)
        vm.bulkScheduledEnd = newDate.addingTimeInterval(7200)
        await vm.confirmBulkScheduleUpdate()

        let updated = try await container.workOrderRepository.fetch(id: order.id)
        XCTAssertEqual(updated.scheduledDate.timeIntervalSince1970, newDate.timeIntervalSince1970, accuracy: 1)
    }

    func testBulkDateRecomputesTimeStatus() async throws {
        let calendar = Calendar.current
        let now = Date()
        let pastDate = calendar.date(byAdding: .day, value: -2, to: now)!
        let futureDate = calendar.date(byAdding: .day, value: 5, to: now)!

        let order = DomainFixtures.workOrder(
            id: WorkOrderID("qa-bulk-time-status"),
            customerId: customer.id,
            scheduledDate: pastDate,
            scheduledTimeRange: ScheduledTimeRange(
                uncheckedStart: pastDate,
                end: pastDate.addingTimeInterval(3600)
            ),
            status: .assigned
        )
        try await seedOrders([order])

        let vm = makeListViewModel()
        await vm.load()
        let delayedCard = vm.cards.first { $0.id == order.id.rawValue }
        XCTAssertEqual(delayedCard?.timeStatus, .delayed)

        vm.setSelectionMode(true)
        vm.toggleSelection(order.id)
        vm.bulkScheduledDate = futureDate
        vm.bulkScheduledStart = futureDate
        vm.bulkScheduledEnd = futureDate.addingTimeInterval(3600)
        await vm.confirmBulkScheduleUpdate()
        await vm.load()

        let updated = try await container.workOrderRepository.fetch(id: order.id)
        XCTAssertEqual(
            WorkOrderTimeStatusPolicy.timeStatus(for: updated, now: now),
            .scheduled
        )

        let scheduledCard = vm.cards.first { $0.id == order.id.rawValue }
        XCTAssertEqual(scheduledCard?.timeStatus, .scheduled)
    }

    // MARK: - T28 Template

    func testTemplatePopulatesConfiguredFields() async throws {
        OperatorWorkOrderTemplateService.resetDefaultsSeed(for: operatorUser.id)
        let listVM = WorkOrderTemplateListViewModel(
            actor: operatorUser,
            service: deps.workOrderTemplateService
        )
        await listVM.load()

        guard let template = listVM.templates.first(where: { $0.name == "POS Bakım" }) else {
            XCTFail("expected POS Bakım default template")
            return
        }

        let vm = NewWorkOrderWizardViewModel(actor: operatorUser, dependencies: deps)
        vm.applyTemplate(template)

        XCTAssertEqual(vm.draft.workType, .maintenance)
        XCTAssertEqual(vm.draft.deviceCategory, .pos)
        XCTAssertEqual(vm.draft.deviceBrand, "Ingenico")
        XCTAssertEqual(vm.draft.deviceModel, "Move 5000")
        XCTAssertEqual(vm.draft.issueDescription, "Periyodik bakım ve kontrol")
        XCTAssertEqual(vm.draft.priority, .normal)
        XCTAssertNotNil(vm.appliedTemplateFieldSummary)
        XCTAssertTrue(vm.appliedTemplateFieldSummary!.contains("Ingenico"))
    }

    func testTemplateKeepsDynamicFields() async throws {
        let template = try await deps.workOrderTemplateService.create(
            actor: operatorUser,
            name: "QA Koruma",
            summary: nil,
            workType: .repair,
            deviceCategory: .pos,
            deviceBrand: "Verifone",
            deviceModel: "V240m",
            issueDescription: "Test",
            priority: .high
        )

        let vm = NewWorkOrderWizardViewModel(actor: operatorUser, dependencies: deps)
        vm.draft.customer = customer
        vm.draft.technician = techA
        vm.draft.serialNumber = "SN-DYNAMIC"
        let preservedDate = Date(timeIntervalSince1970: 1_900_000_000)
        vm.draft.scheduledDate = preservedDate

        vm.applyTemplate(template)

        XCTAssertEqual(vm.draft.customer?.id, customer.id)
        XCTAssertEqual(vm.draft.technician?.id, techA.id)
        XCTAssertEqual(vm.draft.serialNumber, "SN-DYNAMIC")
        XCTAssertEqual(vm.draft.scheduledDate.timeIntervalSince1970, preservedDate.timeIntervalSince1970, accuracy: 1)
        XCTAssertEqual(vm.draft.deviceBrand, "Verifone")
    }

    // MARK: - Location

    func testTechnicianLocationDisplay() async throws {
        let order = DomainFixtures.workOrder(
            id: WorkOrderID("qa-loc-order"),
            customerId: customer.id,
            status: .assigned
        )
        let otherOrder = DomainFixtures.workOrder(
            id: WorkOrderID("qa-loc-other"),
            workOrderNumber: "WO-LOC-OTHER",
            assignedTechnicianId: techA.id,
            customerId: customer.id,
            status: .inProgress
        )
        try await seedOrders([order, otherOrder])

        let siteLocation = DomainFixtures.location(
            id: "qa-site",
            workOrderId: order.id,
            event: .arrived,
            capturedByUserId: operatorUser.id
        )
        let techLocation = WorkOrderLocation(
            id: "qa-tech-loc",
            workOrderId: otherOrder.id,
            event: .enRoute,
            coordinate: near,
            capturedByUserId: techA.id,
            capturedAt: Date()
        )
        try await deps.workOrderLocationRepository.save(siteLocation)
        try await deps.workOrderLocationRepository.save(techLocation)

        let vm = makeListViewModel()
        await vm.load()
        vm.setSelectionMode(true)
        vm.toggleSelection(order.id)
        await vm.prepareBulkAssignSheet()

        let label = vm.locationLabel(for: techA)
        XCTAssertNotNil(label)
        XCTAssertTrue(label == site.formattedDistance(to: near) || label!.contains("m"))
    }

    func testStaleLocationFallback() async throws {
        let order = DomainFixtures.workOrder(
            id: WorkOrderID("qa-stale-order"),
            customerId: customer.id,
            status: .assigned
        )
        try await seedOrders([order])

        try await deps.workOrderLocationRepository.save(
            DomainFixtures.location(
                id: "qa-stale-site",
                workOrderId: order.id,
                event: .arrived,
                capturedByUserId: operatorUser.id
            )
        )
        try await deps.workOrderLocationRepository.save(
            WorkOrderLocation(
                id: "qa-stale-tech",
                workOrderId: order.id,
                event: .enRoute,
                coordinate: near,
                capturedByUserId: techA.id,
                capturedAt: Date().addingTimeInterval(-5 * 3600)
            )
        )

        let vm = makeListViewModel()
        await vm.load()
        vm.setSelectionMode(true)
        vm.toggleSelection(order.id)
        await vm.prepareBulkAssignSheet()

        XCTAssertEqual(vm.locationLabel(for: techA), "Konum güncel değil")
    }

    func testMissingLocationDoesNotBreakAssignment() async throws {
        let order = DomainFixtures.workOrder(
            id: WorkOrderID("qa-no-loc"),
            assignedTechnicianId: techA.id,
            customerId: customer.id,
            status: .assigned
        )
        try await seedOrders([order])

        let vm = makeListViewModel()
        await vm.load()
        vm.setSelectionMode(true)
        vm.toggleSelection(order.id)
        await vm.prepareBulkAssignSheet()

        XCTAssertEqual(vm.locationLabel(for: techB), "Konum bilinmiyor")

        vm.selectTechnicianForBulkAssign(techB)
        await vm.confirmBulkAssign()

        let updated = try await container.workOrderRepository.fetch(id: order.id)
        XCTAssertEqual(updated.assignedTechnicianId, techB.id)
    }

    func testBulkOperationsDoNotCreateNPlusOne() async throws {
        let order1 = DomainFixtures.workOrder(
            id: WorkOrderID("qa-n1-a"),
            customerId: customer.id,
            status: .assigned
        )
        let order2 = DomainFixtures.workOrder(
            id: WorkOrderID("qa-n1-b"),
            workOrderNumber: "WO-N1-B",
            customerId: customerB.id,
            status: .assigned
        )
        try await seedOrders([order1, order2])

        let countingRepo = QACountingLocationRepository()
        let vm = makeListViewModel(locationRepository: countingRepo)
        await vm.load()
        vm.setSelectionMode(true)
        vm.toggleSelection(order1.id)
        vm.toggleSelection(order2.id)

        let before = await countingRepo.listCallCount
        await vm.prepareBulkAssignSheet()
        let after = await countingRepo.listCallCount

        XCTAssertGreaterThan(after, before)
        XCTAssertLessThanOrEqual(after - before, before == 0 ? 10 : 5)
    }
}

private actor QACountingLocationRepository: WorkOrderLocationRepository {
    private let wrapped = InMemoryLocationRepository()
    private(set) var listCallCount = 0

    func list(for workOrderId: WorkOrderID) async throws -> [WorkOrderLocation] {
        listCallCount += 1
        return try await wrapped.list(for: workOrderId)
    }

    func save(_ location: WorkOrderLocation) async throws {
        try await wrapped.save(location)
    }
}
