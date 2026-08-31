import XCTest
@testable import DonanimOperasyonServis

@MainActor
final class Faz12DTechnicianAssignmentTests: XCTestCase {

    private var container: DIContainer!
    private var deps: OperatorDependencies!
    private var operatorUser: User = DomainFixtures.operatorUser()
    private var customer: Customer = DomainFixtures.customer()
    private var techA: User = DomainFixtures.technicianUser(id: UserID("tech-a"))
    private var techB: User = DomainFixtures.technicianUser(id: UserID("tech-b"))

    override func setUp() async throws {
        container = DIContainer.mock()
        deps = container.makeOperatorDependencies()
        operatorUser = DomainFixtures.operatorUser()
        customer = DomainFixtures.customer(createdByUserId: operatorUser.id)
        techA = DomainFixtures.technicianUser(
            id: UserID("tech-a"),
            email: "a@example.com",
            fullName: "Teknisyen A"
        )
        techB = DomainFixtures.technicianUser(
            id: UserID("tech-b"),
            email: "b@example.com",
            fullName: "Teknisyen B"
        )
        try await deps.userRepository.save(operatorUser)
        try await deps.userRepository.save(techA)
        try await deps.userRepository.save(techB)
        try await deps.customerRepository.save(customer)
    }

    func testOperatorAuthorizedAssignment() async throws {
        XCTAssertTrue(RoleAccessPolicy.can(.assignWorkOrder, as: operatorUser.role))

        let order = DomainFixtures.workOrder(
            assignedTechnicianId: techA.id,
            customerId: customer.id,
            status: .assigned
        )
        try await container.workOrderRepository.save(order)

        let updated = try await deps.workOrderService.assignWithSync(
            actor: operatorUser,
            orderId: order.id,
            newTechnicianId: techB.id
        )
        XCTAssertEqual(updated.assignedTechnicianId, techB.id)
    }

    func testTechnicianSelectionListsActiveTechnicians() async throws {
        let order = DomainFixtures.workOrder(
            assignedTechnicianId: techA.id,
            customerId: customer.id
        )
        try await container.workOrderRepository.save(order)

        let vm = OperatorWorkOrderDetailViewModel(
            workOrderId: order.id,
            actor: operatorUser,
            dependencies: deps
        )
        await vm.load()
        XCTAssertTrue(vm.canAssignTechnician)

        vm.attemptAssign()
        XCTAssertTrue(vm.showsAssignSheet)
        await vm.loadAssignableTechnicians()

        let ids = Set(vm.assignableTechnicians.map(\.id))
        XCTAssertTrue(ids.contains(techA.id))
        XCTAssertTrue(ids.contains(techB.id))
        XCTAssertEqual(vm.selectedTechnicianId, techA.id)
    }

    func testTechnicianReassignmentPersistsAndRefreshesDetail() async throws {
        let order = DomainFixtures.workOrder(
            assignedTechnicianId: techA.id,
            customerId: customer.id,
            status: .enRoute
        )
        try await container.workOrderRepository.save(order)

        let vm = OperatorWorkOrderDetailViewModel(
            workOrderId: order.id,
            actor: operatorUser,
            dependencies: deps
        )
        await vm.load()
        XCTAssertEqual(vm.content?.technicianName, techA.fullName)

        vm.attemptAssign()
        await vm.loadAssignableTechnicians()
        vm.selectTechnicianForAssign(techB)
        await vm.confirmAssignment()

        XCTAssertFalse(vm.isAssigning)
        XCTAssertFalse(vm.showsAssignSheet)
        XCTAssertNil(vm.assignmentError)
        XCTAssertEqual(vm.phase, .loaded)
        XCTAssertEqual(vm.content?.workOrder.assignedTechnicianId, techB.id)
        XCTAssertEqual(vm.content?.technicianName, techB.fullName)

        let stored = try await container.workOrderRepository.fetch(id: order.id)
        XCTAssertEqual(stored.assignedTechnicianId, techB.id)
    }

    func testCreateWorkOrderPersistsSelectedTechnician() async throws {
        let vm = NewWorkOrderWizardViewModel(actor: operatorUser, dependencies: deps)
        vm.selectWorkType(.installation)
        vm.selectCustomer(customer)
        vm.draft.deviceBrand = "Ingenico"
        vm.draft.deviceModel = "DX8000"
        vm.draft.serialNumber = "SN-ASSIGN-1"
        vm.selectTechnician(techB)

        await vm.submit()
        guard case .success(let id) = vm.phase else {
            return XCTFail("expected create success, got \(vm.phase)")
        }

        let stored = try await container.workOrderRepository.fetch(id: id)
        XCTAssertEqual(stored.assignedTechnicianId, techB.id)

        let detail = OperatorWorkOrderDetailViewModel(
            workOrderId: id,
            actor: operatorUser,
            dependencies: deps
        )
        await detail.load()
        XCTAssertEqual(detail.content?.technicianName, techB.fullName)
    }

    func testUnauthorizedAssignmentBlocked() async throws {
        let technicianActor = techA
        let order = DomainFixtures.workOrder(
            assignedTechnicianId: techA.id,
            customerId: customer.id
        )
        try await container.workOrderRepository.save(order)

        do {
            _ = try await deps.workOrderService.assignWithSync(
                actor: technicianActor,
                orderId: order.id,
                newTechnicianId: techB.id
            )
            XCTFail("expected unauthorized")
        } catch let error as DomainError {
            guard case .unauthorized = error else {
                return XCTFail("expected unauthorized, got \(error)")
            }
        }

        let vm = OperatorWorkOrderDetailViewModel(
            workOrderId: order.id,
            actor: technicianActor,
            dependencies: deps
        )
        await vm.load()
        XCTAssertFalse(vm.canAssignTechnician)
        vm.attemptAssign()
        XCTAssertFalse(vm.showsAssignSheet)
        XCTAssertNotNil(vm.assignmentError)
    }

    func testTerminalWorkOrderAssignmentBlocked() async throws {
        let order = DomainFixtures.workOrder(
            assignedTechnicianId: techA.id,
            customerId: customer.id,
            status: .completed
        )
        try await container.workOrderRepository.save(order)

        let vm = OperatorWorkOrderDetailViewModel(
            workOrderId: order.id,
            actor: operatorUser,
            dependencies: deps
        )
        await vm.load()
        XCTAssertTrue(vm.canAssignTechnician)

        vm.attemptAssign()
        XCTAssertFalse(vm.showsAssignSheet)
        XCTAssertEqual(
            vm.assignmentError,
            DomainError.workOrderLocked(order.id).operatorMessage
        )

        let unchanged = try await container.workOrderRepository.fetch(id: order.id)
        XCTAssertEqual(unchanged.assignedTechnicianId, techA.id)
    }

    func testMutationFailureKeepsPriorTechnician() async throws {
        let order = DomainFixtures.workOrder(
            assignedTechnicianId: techA.id,
            customerId: customer.id,
            status: .completed
        )
        try await container.workOrderRepository.save(order)

        let vm = OperatorWorkOrderDetailViewModel(
            workOrderId: order.id,
            actor: operatorUser,
            dependencies: deps
        )
        await vm.load()
        let priorName = vm.content?.technicianName

        await vm.confirmAssignment()

        XCTAssertFalse(vm.isAssigning)
        XCTAssertNotNil(vm.assignmentError)
        XCTAssertEqual(vm.content?.technicianName, priorName)
        XCTAssertEqual(vm.content?.workOrder.assignedTechnicianId, techA.id)
        XCTAssertNotEqual(vm.phase, .loading)
    }

    func testCancellationDuringDetailLoadSettlesAwayFromSpinner() async throws {
        let order = DomainFixtures.workOrder(
            assignedTechnicianId: techA.id,
            customerId: customer.id
        )
        try await container.workOrderRepository.save(order)

        let vm = OperatorWorkOrderDetailViewModel(
            workOrderId: order.id,
            actor: operatorUser,
            dependencies: deps
        )
        let task = Task { await vm.load() }
        task.cancel()
        await task.value
        XCTAssertNotEqual(vm.phase, .loading)
    }

    func testDuplicateAssignmentTapDoesNotLeaveLoading() async throws {
        let order = DomainFixtures.workOrder(
            assignedTechnicianId: techA.id,
            customerId: customer.id,
            status: .assigned
        )
        try await container.workOrderRepository.save(order)

        let vm = OperatorWorkOrderDetailViewModel(
            workOrderId: order.id,
            actor: operatorUser,
            dependencies: deps
        )
        await vm.load()
        vm.attemptAssign()
        await vm.loadAssignableTechnicians()
        vm.selectTechnicianForAssign(techB)

        await vm.confirmAssignment()
        await vm.confirmAssignment()

        XCTAssertFalse(vm.isAssigning)
        XCTAssertEqual(vm.phase, .loaded)
        XCTAssertEqual(vm.content?.workOrder.assignedTechnicianId, techB.id)
    }

    func testListAndDetailRefreshAfterAssignment() async throws {
        let order = DomainFixtures.workOrder(
            id: WorkOrderID("wo-refresh"),
            assignedTechnicianId: techA.id,
            customerId: customer.id,
            status: .accepted
        )
        try await container.workOrderRepository.save(order)

        let listVM = OperatorWorkOrderListViewModel(actor: operatorUser, dependencies: deps)
        await listVM.load()
        XCTAssertEqual(
            listVM.cards.first(where: { $0.id == order.id.rawValue })?.technicianName,
            techA.fullName
        )

        let detailVM = OperatorWorkOrderDetailViewModel(
            workOrderId: order.id,
            actor: operatorUser,
            dependencies: deps
        )
        await detailVM.load()
        detailVM.attemptAssign()
        await detailVM.loadAssignableTechnicians()
        detailVM.selectTechnicianForAssign(techB)
        await detailVM.confirmAssignment()

        await listVM.load()
        XCTAssertEqual(detailVM.content?.technicianName, techB.fullName)
        XCTAssertEqual(
            listVM.cards.first(where: { $0.id == order.id.rawValue })?.technicianName,
            techB.fullName
        )
    }

    func testAssignmentDoesNotAppendStatusHistory() async throws {
        let order = DomainFixtures.workOrder(
            assignedTechnicianId: techA.id,
            customerId: customer.id,
            status: .inProgress
        )
        try await container.workOrderRepository.save(order)
        let before = try await deps.statusHistoryRepository.list(for: order.id)

        _ = try await deps.workOrderService.assignWithSync(
            actor: operatorUser,
            orderId: order.id,
            newTechnicianId: techB.id
        )

        let after = try await deps.statusHistoryRepository.list(for: order.id)
        XCTAssertEqual(after.count, before.count)
    }

    func testAssignmentEnqueuesWorkOrderUpdateSync() async throws {
        let order = DomainFixtures.workOrder(
            assignedTechnicianId: techA.id,
            customerId: customer.id
        )
        try await container.workOrderRepository.save(order)

        _ = try await deps.workOrderService.assignWithSync(
            actor: operatorUser,
            orderId: order.id,
            newTechnicianId: techB.id
        )

        let ops = try await deps.syncOperationRepository.list(
            entityType: .workOrder,
            entityId: order.id.rawValue
        )
        XCTAssertTrue(ops.contains { $0.operationType == .update })

        let pending = try await deps.syncOperationRepository.fetchPending(now: Date())
        let notificationOps = pending.filter {
            $0.entityType == .notification && $0.payloadReference == techB.id.rawValue
        }
        XCTAssertEqual(notificationOps.count, 1)
    }

    func testWizardTechnicianSelectionRegression() {
        let vm = NewWorkOrderWizardViewModel(actor: operatorUser, dependencies: deps)
        vm.selectTechnician(techA)
        XCTAssertEqual(vm.draft.technician?.id, techA.id)
        vm.selectTechnician(techB)
        XCTAssertEqual(vm.draft.technician?.id, techB.id)
        XCTAssertNil(vm.fieldErrors[.technician])
    }

    func testRecommendationDoesNotAutoAssignInWizard() async throws {
        let order = DomainFixtures.workOrder(
            assignedTechnicianId: techA.id,
            customerId: customer.id,
            status: .inProgress
        )
        try await container.workOrderRepository.save(order)

        let vm = NewWorkOrderWizardViewModel(actor: operatorUser, dependencies: deps)
        await vm.loadSelections()

        XCTAssertNil(vm.draft.technician)
        XCTAssertTrue(vm.isRecommended(techB))
        XCTAssertEqual(vm.filteredTechnicians.first?.id, techB.id)
    }

    func testRecommendationUsesCachedDataOffline() async throws {
        let order = DomainFixtures.workOrder(
            assignedTechnicianId: techA.id,
            customerId: customer.id,
            status: .inProgress
        )
        try await container.workOrderRepository.save(order)

        let reachability = FakeNetworkReachability(isReachable: false)
        let baseDeps = container.makeOperatorDependencies()
        let offlineDeps = OperatorDependencies(
            getWorkOrders: baseDeps.getWorkOrders,
            getWorkOrder: baseDeps.getWorkOrder,
            workOrderService: baseDeps.workOrderService,
            customerService: baseDeps.customerService,
            workOrderTemplateService: baseDeps.workOrderTemplateService,
            customerRepository: baseDeps.customerRepository,
            userRepository: baseDeps.userRepository,
            localDirectoryCacheRefresh: baseDeps.localDirectoryCacheRefresh,
            workOrderNoteRepository: baseDeps.workOrderNoteRepository,
            workOrderPhotoRepository: baseDeps.workOrderPhotoRepository,
            workOrderLocationRepository: baseDeps.workOrderLocationRepository,
            signatureRepository: baseDeps.signatureRepository,
            statusHistoryRepository: baseDeps.statusHistoryRepository,
            editRequestRepository: baseDeps.editRequestRepository,
            editRequestService: baseDeps.editRequestService,
            customerSatisfactionRepository: baseDeps.customerSatisfactionRepository,
            customerSatisfactionService: baseDeps.customerSatisfactionService,
            notificationRepository: baseDeps.notificationRepository,
            syncOperationRepository: baseDeps.syncOperationRepository,
            syncConflictRepository: baseDeps.syncConflictRepository,
            conflictResolver: baseDeps.conflictResolver,
            networkReachability: reachability,
            profileAccountService: baseDeps.profileAccountService,
            storageDataSource: baseDeps.storageDataSource
        )

        let vm = NewWorkOrderWizardViewModel(actor: operatorUser, dependencies: offlineDeps)
        await vm.loadSelections()

        XCTAssertTrue(vm.isRecommended(techB))
        XCTAssertEqual(vm.filteredTechnicians.first?.id, techB.id)
    }

    func testRecommendationDoesNotCreateNPlusOneFetches() async throws {
        let order = DomainFixtures.workOrder(
            assignedTechnicianId: techA.id,
            customerId: customer.id,
            status: .inProgress
        )
        try await container.workOrderRepository.save(order)

        let countingUsers = CountingTechnicianAssignmentUserRepository(inner: container.userRepository)
        let countingWorkOrders = CountingTechnicianAssignmentWorkOrderRepository(inner: container.workOrderRepository)
        let baseDeps = container.makeOperatorDependencies()
        let deps = OperatorDependencies(
            getWorkOrders: GetWorkOrdersUseCase(workOrderRepository: countingWorkOrders),
            getWorkOrder: baseDeps.getWorkOrder,
            workOrderService: baseDeps.workOrderService,
            customerService: baseDeps.customerService,
            workOrderTemplateService: baseDeps.workOrderTemplateService,
            customerRepository: baseDeps.customerRepository,
            userRepository: countingUsers,
            localDirectoryCacheRefresh: baseDeps.localDirectoryCacheRefresh,
            workOrderNoteRepository: baseDeps.workOrderNoteRepository,
            workOrderPhotoRepository: baseDeps.workOrderPhotoRepository,
            workOrderLocationRepository: baseDeps.workOrderLocationRepository,
            signatureRepository: baseDeps.signatureRepository,
            statusHistoryRepository: baseDeps.statusHistoryRepository,
            editRequestRepository: baseDeps.editRequestRepository,
            editRequestService: baseDeps.editRequestService,
            customerSatisfactionRepository: baseDeps.customerSatisfactionRepository,
            customerSatisfactionService: baseDeps.customerSatisfactionService,
            notificationRepository: baseDeps.notificationRepository,
            syncOperationRepository: baseDeps.syncOperationRepository,
            syncConflictRepository: baseDeps.syncConflictRepository,
            conflictResolver: baseDeps.conflictResolver,
            networkReachability: FakeNetworkReachability(isReachable: false),
            profileAccountService: baseDeps.profileAccountService,
            storageDataSource: baseDeps.storageDataSource
        )

        let vm = NewWorkOrderWizardViewModel(actor: operatorUser, dependencies: deps)
        await vm.loadSelections()
        _ = vm.filteredTechnicians.map { vm.isRecommended($0) }

        let workOrderListCount = await countingWorkOrders.listCallCount
        let technicianListCount = await countingUsers.listCallCount
        XCTAssertEqual(workOrderListCount, 1)
        XCTAssertLessThanOrEqual(technicianListCount, 2)
    }
}

private actor CountingTechnicianAssignmentWorkOrderRepository: WorkOrderRepository {
    let inner: any WorkOrderRepository
    private(set) var listCallCount = 0

    init(inner: any WorkOrderRepository) { self.inner = inner }

    func list(filter: WorkOrderFilter) async throws -> [WorkOrder] {
        listCallCount += 1
        return try await inner.list(filter: filter)
    }

    func fetch(id: WorkOrderID) async throws -> WorkOrder { try await inner.fetch(id: id) }
    func save(_ workOrder: WorkOrder) async throws { try await inner.save(workOrder) }
    func delete(id: WorkOrderID) async throws { try await inner.delete(id: id) }
}

private actor CountingTechnicianAssignmentUserRepository: UserRepository {
    let inner: any UserRepository
    private(set) var listCallCount = 0

    init(inner: any UserRepository) { self.inner = inner }

    func list(role: UserRole?, isActive: Bool?) async throws -> [User] {
        listCallCount += 1
        return try await inner.list(role: role, isActive: isActive)
    }

    func fetch(id: UserID) async throws -> User { try await inner.fetch(id: id) }
    func findByEmail(_ email: String) async throws -> User? { try await inner.findByEmail(email) }
    func save(_ user: User) async throws { try await inner.save(user) }
    func updateSelfServiceProfile(_ user: User) async throws { try await inner.updateSelfServiceProfile(user) }
    func delete(id: UserID) async throws { try await inner.delete(id: id) }
}
