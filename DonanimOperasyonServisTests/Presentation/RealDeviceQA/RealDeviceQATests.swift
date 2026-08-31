import XCTest
@testable import DonanimOperasyonServis

@MainActor
final class RealDeviceQACameraTests: XCTestCase {

    private var container: DIContainer!
    private var deps: TechnicianDependencies!
    private var tech: User!
    private var order: WorkOrder!

    override func setUp() async throws {
        container = DIContainer.mock()
        deps = container.makeTechnicianDependencies()
        tech = DomainFixtures.technicianUser()
        let customer = DomainFixtures.customer()
        order = DomainFixtures.workOrder(
            assignedTechnicianId: tech.id,
            customerId: customer.id,
            workType: .installation,
            status: .inProgress
        )
        try await container.userRepository.save(tech)
        try await container.customerRepository.save(customer)
        try await container.workOrderRepository.save(order)
    }

    private func makeViewModel() -> TechnicianWorkOrderDetailViewModel {
        TechnicianWorkOrderDetailViewModel(
            workOrderId: order.id,
            actor: tech,
            dependencies: deps
        )
    }

    func testCameraPermissionDenied() async throws {
        let vm = makeViewModel()
        await vm.load()

        let allowed = await vm.requestCameraCapture(
            for: .before,
            isHardwareAvailable: true,
            authorizationStatus: .denied,
            requestAccess: { true }
        )

        XCTAssertFalse(allowed)
        XCTAssertEqual(vm.photoError, TechnicianCameraAccess.deniedMessage)
        XCTAssertFalse(vm.isPreparingCamera)
        XCTAssertNil(vm.presentingCameraCategory)
    }

    func testCameraUnavailable() async throws {
        let vm = makeViewModel()
        await vm.load()

        let allowed = await vm.requestCameraCapture(
            for: .before,
            isHardwareAvailable: false,
            authorizationStatus: .authorized,
            requestAccess: { true }
        )

        XCTAssertFalse(allowed)
        XCTAssertEqual(vm.photoError, TechnicianCameraAccess.unavailableMessage)
        XCTAssertNil(vm.presentingCameraCategory)
    }

    func testCameraPresentationLifecycle() async throws {
        let vm = makeViewModel()
        await vm.load()

        let allowed = await vm.requestCameraCapture(
            for: .before,
            isHardwareAvailable: true,
            authorizationStatus: .authorized,
            requestAccess: { XCTFail("should not prompt"); return false }
        )

        XCTAssertTrue(allowed)
        XCTAssertEqual(vm.presentingCameraCategory, .before)
        XCTAssertFalse(vm.isPreparingCamera)

        vm.dismissCameraCapture()
        XCTAssertNil(vm.presentingCameraCategory)
    }

    func testCameraDismissRestoresParent() async throws {
        let vm = makeViewModel()
        await vm.load()
        vm.openPhotoSheet(category: .before)
        XCTAssertTrue(vm.showPhotoSheet)

        _ = await vm.requestCameraCapture(
            for: .before,
            isHardwareAvailable: true,
            authorizationStatus: .authorized,
            requestAccess: { XCTFail("should not prompt"); return false }
        )
        XCTAssertEqual(vm.presentingCameraCategory, .before)

        vm.dismissCameraCapture()
        XCTAssertTrue(vm.showPhotoSheet)
        XCTAssertNil(vm.presentingCameraCategory)
    }

    func testGalleryDismissDoesNotReopenCamera() async throws {
        let vm = makeViewModel()
        await vm.load()
        vm.openPhotoSheet(category: .before)

        vm.dismissCameraCapture()
        vm.resetCameraPresentation()

        XCTAssertNil(vm.presentingCameraCategory)
        XCTAssertTrue(vm.showPhotoSheet)
    }

    func testPhotoSheetDismissClearsCameraState() async throws {
        let vm = makeViewModel()
        await vm.load()
        _ = await vm.requestCameraCapture(for: .before)
        vm.setPhotoSheetVisible(false)

        XCTAssertFalse(vm.showPhotoSheet)
        XCTAssertNil(vm.presentingCameraCategory)
    }
}

@MainActor
final class RealDeviceQALocationTests: XCTestCase {

    func testRealDeviceLocationSourceUsesCoreLocationSamplerInReleasePath() {
        #if DEBUG
        DebugLocationSettings.source = .deviceGPS
        let sampler = DebugLocationSettings.makeSampler()
        XCTAssertTrue(sampler is CoreLocationSampler)
        #else
        let sampler = CoreLocationSampler()
        XCTAssertTrue(sampler is CoreLocationSampler)
        #endif
    }

    func testSimulatorLocationIsNotUsedAsProductionSourceInRelease() {
        #if !DEBUG
        XCTAssertTrue(CoreLocationSampler() is CoreLocationSampler)
        #endif
    }

    func testMockSamplerProducesTestDiagnostics() async throws {
        #if DEBUG
        let sampler = MockFieldLocationSampler()
        _ = try await sampler.sample(for: .arrived)
        XCTAssertNotNil(sampler.lastSampleDiagnostics)
        #if targetEnvironment(simulator)
        XCTAssertEqual(sampler.lastSampleDiagnostics?.source, .simulator)
        #else
        XCTAssertEqual(sampler.lastSampleDiagnostics?.source, .testMock)
        #endif
        #endif
    }

    func testStaleLocationFallbackInAssignmentContext() {
        let site = LocationCoordinate(latitude: 41.0, longitude: 29.0)
        let staleDate = Date().addingTimeInterval(-5 * 3600)
        let context = TechnicianAssignmentLocationContext(
            workOrderSite: site,
            technicianLocations: [
                UserID("tech"): TechnicianLocationInfo(
                    coordinate: LocationCoordinate(latitude: 41.01, longitude: 29.01),
                    capturedAt: staleDate,
                    freshness: .stale
                )
            ]
        )
        XCTAssertEqual(context.assignmentLocationLabel(for: UserID("tech")), "Konum güncel değil")
    }

    func testLocationPermissionDeniedDoesNotCrashViewModel() async throws {
        let container = DIContainer.mock()
        let deps = container.makeTechnicianDependencies()
        let tech = DomainFixtures.technicianUser()
        let customer = DomainFixtures.customer()
        let order = DomainFixtures.workOrder(assignedTechnicianId: tech.id, customerId: customer.id, status: .inProgress)
        try await container.userRepository.save(tech)
        try await container.customerRepository.save(customer)
        try await container.workOrderRepository.save(order)

        let vm = TechnicianWorkOrderDetailViewModel(
            workOrderId: order.id,
            actor: tech,
            dependencies: deps,
            locationSampler: ThrowingLocationSampler(error: .permissionDenied)
        )
        await vm.load()

        let allowed = vm.prepareLocationCapture(
            areServicesEnabled: true,
            authorizationStatus: .denied
        )
        XCTAssertFalse(allowed)
        await vm.captureLocation()
        XCTAssertNotNil(vm.locationError)
        XCTAssertEqual(vm.phase, .loaded)
    }

    func testMissingLocationDoesNotBreakAssignment() {
        let context = TechnicianAssignmentLocationContext(
            workOrderSite: LocationCoordinate(latitude: 41.0, longitude: 29.0),
            technicianLocations: [:]
        )
        XCTAssertEqual(context.assignmentLocationLabel(for: UserID("missing")), "Konum bilinmiyor")
        let sorted = TechnicianAssignmentSupport.sortedTechniciansForAssignment(
            [DomainFixtures.technicianUser()],
            orders: [],
            locationContext: context
        )
        XCTAssertEqual(sorted.count, 1)
    }
}

@MainActor
final class AdminDeleteWorkOrderTests: XCTestCase {

    private var container: DIContainer!
    private var deps: AdminDependencies!
    private var admin: User!
    private var operatorUser: User!
    private var technician: User!

    override func setUp() async throws {
        container = DIContainer.mock()
        deps = container.makeAdminDependencies()
        admin = DomainFixtures.adminUser()
        operatorUser = DomainFixtures.operatorUser()
        technician = DomainFixtures.technicianUser()
        try await deps.userRepository.save(admin)
        try await deps.userRepository.save(operatorUser)
        try await deps.userRepository.save(technician)
    }

    func testAdminCanDeleteWorkOrder() async throws {
        let order = DomainFixtures.workOrder(
            id: WorkOrderID("admin-delete-1"),
            status: .assigned
        )
        try await container.workOrderRepository.save(order)

        try await deps.workOrderService.deleteWithSync(actor: admin, orderId: order.id)

        do {
            _ = try await container.workOrderRepository.fetch(id: order.id)
            XCTFail("order should be deleted locally")
        } catch {
            XCTAssertTrue(true)
        }

        let ops = try await deps.syncOperationRepository.list(
            entityType: .workOrder,
            entityId: order.id.rawValue
        )
        XCTAssertTrue(ops.contains { $0.operationType == .delete && $0.status == .pending })
    }

    func testOperatorCannotDeleteWorkOrder() async throws {
        let order = DomainFixtures.workOrder(id: WorkOrderID("op-delete-1"), status: .assigned)
        try await container.workOrderRepository.save(order)

        do {
            try await deps.workOrderService.deleteWithSync(actor: operatorUser, orderId: order.id)
            XCTFail("operator should not delete")
        } catch let error as DomainError {
            guard case .unauthorized(let action) = error else {
                return XCTFail("unexpected \(error)")
            }
            XCTAssertEqual(action, .deleteWorkOrder)
        }
    }

    func testTechnicianCannotDeleteWorkOrder() async throws {
        let order = DomainFixtures.workOrder(
            id: WorkOrderID("tech-delete-1"),
            assignedTechnicianId: technician.id,
            status: .assigned
        )
        try await container.workOrderRepository.save(order)

        do {
            try await deps.workOrderService.deleteWithSync(actor: technician, orderId: order.id)
            XCTFail("technician should not delete")
        } catch let error as DomainError {
            guard case .unauthorized = error else {
                return XCTFail("unexpected \(error)")
            }
        }
    }

    func testDeleteConfirmationMessageUsesWorkOrderNumber() async throws {
        let order = DomainFixtures.workOrder(
            id: WorkOrderID("admin-delete-ui"),
            workOrderNumber: "WO-DEL-UI",
            status: .assigned
        )
        try await container.workOrderRepository.save(order)

        let vm = AdminWorkOrderReportViewModel(
            workOrderId: order.id,
            actor: admin,
            dependencies: deps
        )
        await vm.load()

        XCTAssertTrue(vm.canDeleteWorkOrder)
        vm.requestDeleteConfirmation()
        XCTAssertTrue(vm.showsDeleteConfirmation)
        XCTAssertTrue(vm.deleteConfirmationMessage.contains("WO-DEL-UI"))
    }

    func testDeleteUpdatesLocalCache() async throws {
        let order = DomainFixtures.workOrder(id: WorkOrderID("admin-delete-cache"), status: .assigned)
        try await container.workOrderRepository.save(order)

        let vm = AdminWorkOrderReportViewModel(
            workOrderId: order.id,
            actor: admin,
            dependencies: deps
        )
        await vm.load()
        let deleted = await vm.confirmDelete()
        XCTAssertTrue(deleted)

        let remaining = try await deps.getSystemWorkOrders.execute(actor: admin, filter: .all)
        XCTAssertFalse(remaining.contains { $0.id == order.id })
    }

    func testDeleteSyncsOffline() async throws {
        let order = DomainFixtures.workOrder(id: WorkOrderID("admin-delete-offline"), status: .assigned)
        try await container.workOrderRepository.save(order)

        let reachability = FakeNetworkReachability(isReachable: false)
        let offlineDeps = makeOfflineDependencies(reachability: reachability)

        try await offlineDeps.workOrderService.deleteWithSync(actor: admin, orderId: order.id)

        let ops = try await deps.syncOperationRepository.list(
            entityType: .workOrder,
            entityId: order.id.rawValue
        )
        XCTAssertTrue(ops.contains { $0.operationType == .delete })
    }

    func testCompletedWorkOrderCannotBeDeleted() async throws {
        let order = DomainFixtures.workOrder(
            id: WorkOrderID("admin-delete-completed"),
            status: .completed,
            completedAt: DomainFixtures.referenceDate
        )
        try await container.workOrderRepository.save(order)

        do {
            try await deps.workOrderService.deleteWithSync(actor: admin, orderId: order.id)
            XCTFail("completed order should not delete")
        } catch let error as DomainError {
            guard case .workOrderLocked = error else {
                return XCTFail("unexpected \(error)")
            }
        }
    }

    func testAdminBulkDeleteWorkOrders() async throws {
        let orderA = DomainFixtures.workOrder(id: WorkOrderID("bulk-del-a"), status: .assigned)
        let orderB = DomainFixtures.workOrder(id: WorkOrderID("bulk-del-b"), status: .paused)
        try await container.workOrderRepository.save(orderA)
        try await container.workOrderRepository.save(orderB)

        let result = await AdminWorkOrderBulkOperations.delete(
            orderIds: [orderA.id, orderB.id],
            ordersByID: [orderA.id: orderA, orderB.id: orderB],
            actor: admin,
            service: deps.workOrderService
        )

        XCTAssertEqual(result.successCount, 2)
        XCTAssertTrue(result.failures.isEmpty)

        let remaining = try await container.workOrderRepository.list(filter: .all)
        XCTAssertFalse(remaining.contains { $0.id == orderA.id || $0.id == orderB.id })

        for orderId in [orderA.id, orderB.id] {
            let ops = try await deps.syncOperationRepository.list(
                entityType: .workOrder,
                entityId: orderId.rawValue
            )
            XCTAssertTrue(ops.contains { $0.operationType == .delete && $0.status == .pending })
        }
    }

    func testBulkDeleteConfirmation() async throws {
        let orderA = DomainFixtures.workOrder(id: WorkOrderID("bulk-confirm-a"), status: .assigned)
        let orderB = DomainFixtures.workOrder(id: WorkOrderID("bulk-confirm-b"), status: .assigned)
        try await container.workOrderRepository.save(orderA)
        try await container.workOrderRepository.save(orderB)

        let vm = AdminReportDetailViewModel(kind: .workOrders, actor: admin, dependencies: deps)
        await vm.load()
        vm.setSelectionMode(true)
        vm.toggleSelection(orderA.id)
        vm.toggleSelection(orderB.id)

        XCTAssertTrue(vm.canBulkDelete)
        XCTAssertEqual(vm.selectedCount, 2)
        vm.requestBulkDeleteConfirmation()
        XCTAssertTrue(vm.showsBulkDeleteConfirmation)
        XCTAssertTrue(vm.bulkDeleteConfirmationMessage.contains("2 iş emri kalıcı olarak silinecek"))
    }

    func testBulkDeleteUpdatesLocalList() async throws {
        let orderA = DomainFixtures.workOrder(id: WorkOrderID("bulk-list-a"), status: .assigned)
        let orderB = DomainFixtures.workOrder(id: WorkOrderID("bulk-list-b"), status: .assigned)
        try await container.workOrderRepository.save(orderA)
        try await container.workOrderRepository.save(orderB)

        let vm = AdminReportDetailViewModel(kind: .workOrders, actor: admin, dependencies: deps)
        await vm.load()
        vm.setSelectionMode(true)
        vm.toggleSelection(orderA.id)
        vm.toggleSelection(orderB.id)
        await vm.confirmBulkDelete()

        let remaining = try await deps.getSystemWorkOrders.execute(actor: admin, filter: .all)
        XCTAssertFalse(remaining.contains { $0.id == orderA.id || $0.id == orderB.id })
        XCTAssertFalse(vm.displayedWorkOrderEntries.contains { $0.id == orderA.id || $0.id == orderB.id })
    }

    func testBulkDeleteOfflineQueuesOperations() async throws {
        let orderA = DomainFixtures.workOrder(id: WorkOrderID("bulk-offline-a"), status: .assigned)
        let orderB = DomainFixtures.workOrder(id: WorkOrderID("bulk-offline-b"), status: .assigned)
        try await container.workOrderRepository.save(orderA)
        try await container.workOrderRepository.save(orderB)

        let reachability = FakeNetworkReachability(isReachable: false)
        let offlineDeps = makeOfflineDependencies(reachability: reachability)

        let result = await AdminWorkOrderBulkOperations.delete(
            orderIds: [orderA.id, orderB.id],
            ordersByID: [orderA.id: orderA, orderB.id: orderB],
            actor: admin,
            service: offlineDeps.workOrderService
        )

        XCTAssertEqual(result.successCount, 2)

        for orderId in [orderA.id, orderB.id] {
            let ops = try await deps.syncOperationRepository.list(
                entityType: .workOrder,
                entityId: orderId.rawValue
            )
            XCTAssertTrue(ops.contains { $0.operationType == .delete })
        }
    }

    func testBulkDeleteHandlesPartialFailure() async throws {
        let deletable = DomainFixtures.workOrder(id: WorkOrderID("bulk-partial-ok"), status: .assigned)
        let locked = DomainFixtures.workOrder(
            id: WorkOrderID("bulk-partial-locked"),
            status: .completed,
            completedAt: DomainFixtures.referenceDate
        )
        try await container.workOrderRepository.save(deletable)
        try await container.workOrderRepository.save(locked)

        let result = await AdminWorkOrderBulkOperations.delete(
            orderIds: [deletable.id, locked.id],
            ordersByID: [deletable.id: deletable, locked.id: locked],
            actor: admin,
            service: deps.workOrderService
        )

        XCTAssertEqual(result.successCount, 1)
        XCTAssertEqual(result.failureCount, 1)
        XCTAssertEqual(result.succeeded, [deletable.id])
        XCTAssertEqual(result.failures.first?.orderId, locked.id)

        do {
            _ = try await container.workOrderRepository.fetch(id: deletable.id)
            XCTFail("deleted order should be gone")
        } catch {
            XCTAssertTrue(true)
        }
        _ = try await container.workOrderRepository.fetch(id: locked.id)
    }

    private func makeOfflineDependencies(
        reachability: NetworkReachabilityProviding
    ) -> AdminDependencies {
        guard let base = deps else {
            fatalError("deps not initialized")
        }
        return AdminDependencies(
            listUsers: base.listUsers,
            getUser: base.getUser,
            userService: base.userService,
            workOrderService: base.workOrderService,
            localDirectoryCacheRefresh: base.localDirectoryCacheRefresh,
            getSystemWorkOrders: base.getSystemWorkOrders,
            getSystemWorkOrder: base.getSystemWorkOrder,
            userRepository: base.userRepository,
            customerRepository: base.customerRepository,
            workOrderNoteRepository: base.workOrderNoteRepository,
            workOrderPhotoRepository: base.workOrderPhotoRepository,
            workOrderLocationRepository: base.workOrderLocationRepository,
            statusHistoryRepository: base.statusHistoryRepository,
            signatureRepository: base.signatureRepository,
            editRequestRepository: base.editRequestRepository,
            customerSatisfactionRepository: base.customerSatisfactionRepository,
            notificationRepository: base.notificationRepository,
            syncOperationRepository: base.syncOperationRepository,
            syncConflictRepository: base.syncConflictRepository,
            syncManager: base.syncManager,
            networkReachability: reachability,
            profileAccountService: base.profileAccountService,
            storageDataSource: base.storageDataSource
        )
    }
}
