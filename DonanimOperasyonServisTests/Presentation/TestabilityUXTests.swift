import XCTest
@testable import DonanimOperasyonServis

#if DEBUG
@MainActor
final class DemoDataSeederTests: XCTestCase {

    private let demoCustomerIds = [
        "demo-cust-abc", "demo-cust-xyz", "demo-cust-def",
        "demo-cust-ghi", "demo-cust-jkl"
    ]

    private let demoActiveTechnicianIds = [
        "demo-technician", "demo-technician-2", "demo-technician-3",
        "demo-technician-4", "demo-technician-5"
    ]

    private let demoWorkOrderIds = [
        "demo-wo-assigned", "demo-wo-progress", "demo-wo-done"
    ]

    func testSeedIsIdempotent() async throws {
        let container = DIContainer.mock()
        await DemoDataSeeder.seedIfNeeded(container: container)
        let first = try await container.workOrderRepository.list(filter: .all).count
        await DemoDataSeeder.seedIfNeeded(container: container)
        let second = try await container.workOrderRepository.list(filter: .all).count
        XCTAssertEqual(first, second)

        let demoOrders = try await container.workOrderRepository.list(filter: .all)
            .filter { $0.id.rawValue.hasPrefix("demo-wo-") }
        XCTAssertEqual(demoOrders.count, 3)
    }

    func testTechnicianOnlySeesOwnOrders() async throws {
        let container = DIContainer.mock()
        await DemoDataSeeder.loadDemoData(container: container)
        let tech = try await container.userRepository.fetch(id: UserID("demo-technician"))
        let deps = container.makeTechnicianDependencies()
        let mine = try await deps.getWorkOrders.execute(
            actor: tech,
            filter: WorkOrderFilter(assignedTechnicianId: tech.id)
        )
        XCTAssertFalse(mine.isEmpty)
        XCTAssertTrue(mine.allSatisfy { $0.assignedTechnicianId == tech.id })
        XCTAssertFalse(mine.contains(where: { $0.id.rawValue == "demo-wo-progress" }))
    }

    func testClearRemovesDemoMarker() async throws {
        let container = DIContainer.mock()
        await DemoDataSeeder.loadDemoData(container: container)
        _ = await DemoDataSeeder.clearDemoData(container: container)
        let marker = try? await container.customerRepository.fetch(id: CustomerID("demo-cust-abc"))
        XCTAssertNil(marker)
    }

    func testClearPreservesProductionRecords() async throws {
        let container = DIContainer.mock()
        let productionCustomer = DomainFixtures.customer(id: CustomerID("prod-cust-1"))
        let productionOrder = DomainFixtures.workOrder(
            id: WorkOrderID("prod-wo-1"),
            customerId: productionCustomer.id
        )
        try await container.customerRepository.save(productionCustomer)
        try await container.workOrderRepository.save(productionOrder)

        await DemoDataSeeder.loadDemoData(container: container)
        _ = await DemoDataSeeder.clearDemoData(container: container)

        _ = try await container.customerRepository.fetch(id: productionCustomer.id)
        _ = try await container.workOrderRepository.fetch(id: productionOrder.id)
    }

    func testLoadCreatesExpectedWorkOrderStatuses() async throws {
        let container = DIContainer.mock()
        await DemoDataSeeder.loadDemoData(container: container)
        let statuses: [WorkOrderStatus] = [.assigned, .inProgress, .completed]
        for status in statuses {
            let found = try await container.workOrderRepository.list(filter: WorkOrderFilter(status: status))
            XCTAssertFalse(
                found.filter { $0.id.rawValue.hasPrefix("demo-wo-") }.isEmpty,
                "missing \(status)"
            )
        }
    }

    func testPersistDemoUsersDoesNotRequireFakeAuth() async throws {
        let container = DIContainer.mock()
        let errors = await DemoDataSeeder.persistDemoUsers(
            to: container.userRepository,
            fakeAuth: nil
        )
        XCTAssertTrue(errors.isEmpty, errors.joined(separator: "; "))
        for id in [
            "demo-admin", "demo-operator",
            "demo-technician", "demo-technician-2", "demo-technician-3",
            "demo-technician-4", "demo-technician-5",
            "demo-technician-inactive", "demo-operator-2"
        ] {
            _ = try await container.userRepository.fetch(id: UserID(id))
        }
    }

    func testLoadCreatesUsersCustomersAndConsistentWorkOrders() async throws {
        let container = DIContainer.mock()
        let outcome = await DemoDataSeeder.loadDemoData(container: container)
        XCTAssertTrue(outcome.isSuccess, outcome.message)

        for id in demoCustomerIds {
            _ = try await container.customerRepository.fetch(id: CustomerID(id))
        }
        XCTAssertEqual(demoCustomerIds.count, 5)

        let activeTechnicians = try await container.userRepository.list(role: .technician, isActive: true)
            .filter { $0.id.rawValue.hasPrefix("demo-technician") && $0.id.rawValue != "demo-technician-inactive" }
        XCTAssertEqual(activeTechnicians.count, 5)
        for id in demoActiveTechnicianIds {
            _ = try await container.userRepository.fetch(id: UserID(id))
        }

        let demoOrders = try await container.workOrderRepository.list(filter: .all)
            .filter { $0.id.rawValue.hasPrefix("demo-wo-") }
        XCTAssertEqual(demoOrders.count, 3)
        let allowedCustomers = Set(demoCustomerIds)
        for order in demoOrders {
            XCTAssertTrue(demoWorkOrderIds.contains(order.id.rawValue))
            XCTAssertTrue(
                allowedCustomers.contains(order.customerId.rawValue),
                "WorkOrder \(order.id.rawValue) customerId \(order.customerId.rawValue) is not a demo customer"
            )
        }
    }

    func testAllDemoIdsUseDemoPrefix() async throws {
        let container = DIContainer.mock()
        await DemoDataSeeder.loadDemoData(container: container)

        for id in demoCustomerIds + demoActiveTechnicianIds + demoWorkOrderIds {
            XCTAssertTrue(id.hasPrefix("demo-"), "expected demo- prefix for \(id)")
        }

        let customers = try await container.customerRepository.list(searchText: nil)
            .filter { $0.id.rawValue.hasPrefix("demo-") }
        XCTAssertTrue(customers.allSatisfy { $0.id.rawValue.hasPrefix("demo-cust-") })

        let orders = try await container.workOrderRepository.list(filter: .all)
            .filter { $0.id.rawValue.hasPrefix("demo-wo-") }
        XCTAssertTrue(orders.allSatisfy { $0.id.rawValue.hasPrefix("demo-wo-") })
    }

    func testSeedDoesNotEnqueueSyncOperations() async throws {
        let container = DIContainer.mock()
        await DemoDataSeeder.seedIfNeeded(container: container)
        await DemoDataSeeder.loadDemoData(container: container)

        let demoEntityIds = demoCustomerIds + demoActiveTechnicianIds + demoWorkOrderIds
        for entityId in demoEntityIds {
            for entityType in [SyncEntityType.user, .customer, .workOrder] {
                let ops = try await container.syncOperationRepository.list(
                    entityType: entityType,
                    entityId: entityId
                )
                XCTAssertTrue(
                    ops.isEmpty,
                    "unexpected sync op for \(entityType) \(entityId)"
                )
            }
        }
    }

    func testLoadReportsFailureInsteadOfFalseSuccess() async throws {
        let container = DIContainer.mock()
        let outcome = await DemoDataSeeder.loadDemoData(container: container)
        XCTAssertTrue(outcome.isSuccess)
        XCTAssertTrue(outcome.message.contains("Demo veriler yüklendi."))
        XCTAssertFalse(outcome.message.contains("başarısız"))
        XCTAssertFalse(outcome.message.contains("Firebase"))
    }
}

final class MockFieldLocationSamplerTests: XCTestCase {

    func testMockSamplerReturnsValidCoordinatesPerEvent() async throws {
        let sampler = MockFieldLocationSampler()
        for event in LocationEvent.allCases {
            let coordinate = try await sampler.sample(for: event)
            XCTAssertTrue(coordinate.isValid)
        }
        let a = try await sampler.sample(for: .enRoute)
        let b = try await sampler.sample(for: .arrived)
        let c = try await sampler.sample(for: .completed)
        XCTAssertNotEqual(a, b)
        XCTAssertNotEqual(b, c)
    }

    func testDebugLocationSettingsMakeSampler() {
        let previous = DebugLocationSettings.source
        defer { DebugLocationSettings.source = previous }

        DebugLocationSettings.source = .testLocation
        XCTAssertTrue(DebugLocationSettings.makeSampler() is MockFieldLocationSampler)

        DebugLocationSettings.source = .deviceGPS
        XCTAssertTrue(DebugLocationSettings.makeSampler() is CoreLocationSampler)
    }
}
#endif

@MainActor
final class DualSignatureFlowTests: XCTestCase {

    func testTechnicianThenCustomerSignatureOnSameOrder() async throws {
        let container = DIContainer.mock()
        let deps = container.makeTechnicianDependencies()
        let tech = DomainFixtures.technicianUser()
        let customer = DomainFixtures.customer()
        let order = DomainFixtures.workOrder(
            assignedTechnicianId: tech.id,
            customerId: customer.id,
            status: .inProgress
        )
        try await deps.customerRepository.save(customer)
        try await container.workOrderRepository.save(order)

        let vm = TechnicianWorkOrderDetailViewModel(
            workOrderId: order.id,
            actor: tech,
            dependencies: deps,
            locationSampler: FixedLocationSampler(
                coordinate: LocationCoordinate(latitude: 41.01, longitude: 28.97, accuracy: 5)
            )
        )
        await vm.load()
        XCTAssertFalse(vm.hasTechnicianSignature)
        XCTAssertFalse(vm.hasCustomerSignature)

        await vm.captureSignature(
            imageData: TechnicianPlaceholderImage.pngData,
            kind: .technician,
            dismissOnSuccess: false
        )
        XCTAssertNil(vm.signatureError)
        XCTAssertTrue(vm.hasTechnicianSignature)
        XCTAssertFalse(vm.hasCustomerSignature)
        XCTAssertEqual(vm.selectedSignatureKind, .customer)

        await vm.captureSignature(
            imageData: TechnicianPlaceholderImage.pngData,
            kind: .customer,
            signerName: "Müşteri",
            dismissOnSuccess: false
        )
        XCTAssertNil(vm.signatureError)
        XCTAssertTrue(vm.areBothSignaturesComplete)

        await vm.load()
        XCTAssertTrue(vm.hasTechnicianSignature)
        XCTAssertTrue(vm.hasCustomerSignature)
    }

    func testCompletionStillRequiresBothSignatures() async throws {
        let container = DIContainer.mock()
        let deps = container.makeTechnicianDependencies()
        let tech = DomainFixtures.technicianUser()
        let customer = DomainFixtures.customer()
        let order = DomainFixtures.workOrder(
            assignedTechnicianId: tech.id,
            customerId: customer.id,
            status: .inProgress
        )
        try await deps.customerRepository.save(customer)
        try await container.workOrderRepository.save(order)

        _ = try await deps.workOrderService.recordSignature(
            actor: tech,
            orderId: order.id,
            kind: .technician,
            imageData: TechnicianPlaceholderImage.pngData,
            signerName: nil
        )

        let signatures = try await deps.signatureRepository.list(for: order.id)
        let result = CompletionRequirements.check(
            CompletionContext(workType: order.workType, signatures: signatures)
        )
        guard case .failure(let missing) = result else {
            return XCTFail("expected missing customer signature")
        }
        XCTAssertTrue(missing.items.contains(.missingCustomerSignature))
    }
}

final class SyncDrainReportTests: XCTestCase {

    func testDrainReportCountsSuccessAndHeld() async throws {
        let container = DIContainer.mock()
        let now = Date()
        let reportBefore = await container.syncManager.lastDrainReport()
        XCTAssertNil(reportBefore)

        _ = try await container.syncManager.syncPending(now: now)
        let report = await container.syncManager.lastDrainReport()
        XCTAssertNotNil(report)
        XCTAssertEqual(report?.deferredOffline, false)
        XCTAssertGreaterThanOrEqual(report?.totalDuration ?? -1, 0)
    }

    func testSummaryLines() {
        let empty = SyncDrainReport(
            startedAt: Date(),
            finishedAt: Date(),
            pendingAtStart: 0,
            succeeded: 0,
            failed: 0,
            retried: 0,
            held: 0,
            conflicts: 0,
            operations: [],
            deferredOffline: false,
            activeFailedCount: 0,
            retryableFailedCount: 0
        )
        XCTAssertEqual(empty.summaryLine, "Senkronize edilecek işlem yok")

        let ok = SyncDrainReport(
            startedAt: Date(),
            finishedAt: Date().addingTimeInterval(1),
            pendingAtStart: 3,
            succeeded: 3,
            failed: 0,
            retried: 0,
            held: 0,
            conflicts: 0,
            operations: [],
            deferredOffline: false,
            activeFailedCount: 0,
            retryableFailedCount: 0
        )
        XCTAssertEqual(ok.summaryLine, "3 işlem senkronize edildi")

        let heldOnly = SyncDrainReport(
            startedAt: Date(),
            finishedAt: Date(),
            pendingAtStart: 2,
            succeeded: 1,
            failed: 0,
            retried: 1,
            held: 1,
            conflicts: 0,
            operations: [],
            deferredOffline: false,
            activeFailedCount: 0,
            retryableFailedCount: 0
        )
        XCTAssertEqual(heldOnly.summaryLine, "1 işlem senkronize edildi")

        let waiting = SyncDrainReport(
            startedAt: Date(),
            finishedAt: Date(),
            pendingAtStart: 2,
            succeeded: 1,
            failed: 0,
            retried: 0,
            held: 0,
            conflicts: 0,
            operations: [],
            deferredOffline: false,
            activeFailedCount: 0,
            retryableFailedCount: 1
        )
        XCTAssertEqual(waiting.summaryLine, "1 işlem senkronizasyon için bekliyor")

        let failed = SyncDrainReport(
            startedAt: Date(),
            finishedAt: Date(),
            pendingAtStart: 1,
            succeeded: 0,
            failed: 1,
            retried: 1,
            held: 0,
            conflicts: 0,
            operations: [],
            deferredOffline: false,
            activeFailedCount: 1,
            retryableFailedCount: 0
        )
        XCTAssertEqual(failed.summaryLine, "1 işlem senkronizasyon hatası")
    }
}
