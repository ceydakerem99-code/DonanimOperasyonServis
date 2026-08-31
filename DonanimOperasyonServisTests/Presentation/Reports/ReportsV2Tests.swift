import XCTest
@testable import DonanimOperasyonServis

@MainActor
final class ReportsV2Tests: XCTestCase {

    private func makeDeps(from container: DIContainer) -> AdminDependencies {
        container.makeAdminDependencies()
    }

    func testSignatureReportOnlyReturnsSignatureRecords() async throws {
        let container = DIContainer.mock()
        let deps = makeDeps(from: container)
        let admin = DomainFixtures.adminUser()
        let customer = DomainFixtures.customer()
        let order = DomainFixtures.workOrder(customerId: customer.id, status: .completed)
        try await deps.userRepository.save(admin)
        try await deps.customerRepository.save(customer)
        try await container.workOrderRepository.save(order)
        try await deps.signatureRepository.save(
            DomainFixtures.signature(workOrderId: order.id, kind: .customer, signerName: "Ali Veli")
        )

        let vm = AdminReportDetailViewModel(kind: .signatures, actor: admin, dependencies: deps)
        await vm.load()

        XCTAssertEqual(vm.phase, .loaded)
        XCTAssertTrue(vm.payload.workOrderEntries.isEmpty)
        XCTAssertEqual(vm.payload.signatureEntries.count, 1)
        XCTAssertEqual(vm.payload.signatureEntries.first?.signerName, "Ali Veli")
        XCTAssertTrue(vm.payload.photoEntries.isEmpty)
    }

    func testPhotoReportOnlyReturnsPhotoRecords() async throws {
        let container = DIContainer.mock()
        let deps = makeDeps(from: container)
        let admin = DomainFixtures.adminUser()
        let customer = DomainFixtures.customer()
        let order = DomainFixtures.workOrder(customerId: customer.id, status: .assigned)
        try await deps.userRepository.save(admin)
        try await deps.customerRepository.save(customer)
        try await container.workOrderRepository.save(order)
        try await deps.workOrderPhotoRepository.save(
            DomainFixtures.photo(workOrderId: order.id, category: .before)
        )

        let vm = AdminReportDetailViewModel(kind: .photos, actor: admin, dependencies: deps)
        await vm.load()

        XCTAssertEqual(vm.phase, .loaded)
        XCTAssertEqual(vm.payload.photoEntries.count, 1)
        XCTAssertTrue(vm.payload.signatureEntries.isEmpty)
        XCTAssertTrue(vm.payload.workOrderEntries.isEmpty)
    }

    func testWaitingReportOnlyReturnsPausedRecords() async throws {
        let container = DIContainer.mock()
        let deps = makeDeps(from: container)
        let admin = DomainFixtures.adminUser()
        let customer = DomainFixtures.customer()
        let paused = DomainFixtures.workOrder(
            customerId: customer.id,
            status: .paused,
            currentPauseReason: .partWaiting
        )
        let assigned = DomainFixtures.workOrder(
            id: WorkOrderID("wo-assigned"),
            customerId: customer.id,
            status: .assigned
        )
        try await deps.userRepository.save(admin)
        try await deps.customerRepository.save(customer)
        try await container.workOrderRepository.save(paused)
        try await container.workOrderRepository.save(assigned)

        let vm = AdminReportDetailViewModel(kind: .pauseReasons, actor: admin, dependencies: deps)
        await vm.load()

        XCTAssertEqual(vm.phase, .loaded)
        XCTAssertFalse(vm.payload.pauseEntries.isEmpty)
        XCTAssertTrue(vm.payload.pauseEntries.allSatisfy { $0.pauseReason == .partWaiting || $0.isActive })
        XCTAssertTrue(vm.payload.workOrderEntries.isEmpty)
    }

    func testWorkOrderReportShowsCustomerName() async throws {
        let container = DIContainer.mock()
        let deps = makeDeps(from: container)
        let admin = DomainFixtures.adminUser()
        let customer = DomainFixtures.customer(name: "Ceka Market")
        let order = DomainFixtures.workOrder(customerId: customer.id, status: .assigned)
        try await deps.userRepository.save(admin)
        try await deps.customerRepository.save(customer)
        try await container.workOrderRepository.save(order)

        let vm = AdminReportDetailViewModel(kind: .workOrders, actor: admin, dependencies: deps)
        await vm.load()

        XCTAssertEqual(vm.displayedWorkOrderEntries.first?.customerName, "Ceka Market")
        XCTAssertFalse(vm.displayedWorkOrderEntries.first?.workOrderNumber.isEmpty ?? true)
    }

    func testTechnicianPerformanceShowsWorkload() async throws {
        let container = DIContainer.mock()
        let deps = makeDeps(from: container)
        let admin = DomainFixtures.adminUser()
        let tech = DomainFixtures.technicianUser(fullName: "Mehmet Kerem")
        let customer = DomainFixtures.customer()
        try await deps.userRepository.save(admin)
        try await deps.userRepository.save(tech)
        try await deps.customerRepository.save(customer)
        try await container.workOrderRepository.save(
            DomainFixtures.workOrder(
                assignedTechnicianId: tech.id,
                customerId: customer.id,
                priority: .urgent,
                status: .assigned
            )
        )

        let vm = AdminReportDetailViewModel(kind: .technicianPerformance, actor: admin, dependencies: deps)
        await vm.load()

        let entry = vm.displayedTechnicianEntries.first
        XCTAssertEqual(entry?.name, "Mehmet Kerem")
        XCTAssertEqual(entry?.totalAssigned, 1)
        XCTAssertEqual(entry?.urgent, 1)
    }

    func testCustomerAnalyticsVisitCountAndNoDuplicateWorkOrders() async throws {
        let customer = DomainFixtures.customer()
        let orders = [
            DomainFixtures.workOrder(id: WorkOrderID("wo-1"), customerId: customer.id, status: .completed),
            DomainFixtures.workOrder(id: WorkOrderID("wo-2"), customerId: customer.id, status: .completed),
            DomainFixtures.workOrder(id: WorkOrderID("wo-3"), customerId: customer.id, status: .rejected)
        ]

        let summary = CustomerAnalyticsAggregator.summary(customer: customer, orders: orders)
        XCTAssertEqual(summary.totalVisits, 2)
        XCTAssertEqual(summary.completedVisits, 2)
        XCTAssertEqual(summary.totalOrders, 3)
    }

    func testCustomerAnalyticsTechnicianHistoryAggregation() {
        let tech = DomainFixtures.technicianUser(fullName: "Mehmet Kerem")
        let customer = DomainFixtures.customer()
        let orders = [
            DomainFixtures.workOrder(
                id: WorkOrderID("wo-1"),
                assignedTechnicianId: tech.id,
                customerId: customer.id,
                status: .completed
            ),
            DomainFixtures.workOrder(
                id: WorkOrderID("wo-2"),
                assignedTechnicianId: tech.id,
                customerId: customer.id,
                status: .completed
            )
        ]

        let history = CustomerAnalyticsAggregator.technicianHistory(
            orders: orders,
            technicians: [tech.id: tech]
        )
        XCTAssertEqual(history.first?.visitCount, 2)
        XCTAssertEqual(history.first?.technicianName, "Mehmet Kerem")
    }

    func testCustomerAnalyticsOperationAndDeviceAggregation() {
        let customer = DomainFixtures.customer()
        let orders = [
            DomainFixtures.workOrder(customerId: customer.id, workType: .repair, deviceCategory: .pos),
            DomainFixtures.workOrder(
                id: WorkOrderID("wo-2"),
                customerId: customer.id,
                workType: .repair,
                deviceCategory: .tablet
            )
        ]

        let operations = CustomerAnalyticsAggregator.operationHistory(orders: orders)
        let devices = CustomerAnalyticsAggregator.deviceHistory(orders: orders)

        XCTAssertEqual(operations.first(where: { $0.workType == .repair })?.count, 2)
        XCTAssertEqual(devices.first(where: { $0.deviceCategory == .pos })?.count, 1)
    }

    func testCustomerAnalyticsLatestVisitDate() {
        let customer = DomainFixtures.customer()
        let older = DomainFixtures.referenceDate.addingTimeInterval(-86_400)
        let newer = DomainFixtures.referenceDate
        let orders = [
            DomainFixtures.workOrder(
                id: WorkOrderID("wo-old"),
                customerId: customer.id,
                status: .completed,
                completedAt: older
            ),
            DomainFixtures.workOrder(
                id: WorkOrderID("wo-new"),
                customerId: customer.id,
                status: .completed,
                completedAt: newer
            )
        ]

        let summary = CustomerAnalyticsAggregator.summary(customer: customer, orders: orders)
        XCTAssertEqual(summary.lastVisitDate, newer)
    }

    func testReportSearchFiltersAreLocalOnly() {
        let entries = [
            SignatureReportEntry(
                id: "sig-1",
                signature: DomainFixtures.signature(workOrderId: WorkOrderID("wo-1"), kind: .customer, signerName: "Mehmet"),
                workOrderId: WorkOrderID("wo-1"),
                workOrderNumber: "WO-123",
                customerName: "ABC Market",
                workplace: "ABC · İstanbul",
                technicianName: "Mehmet Kerem",
                signerName: "Mehmet",
                capturedAt: DomainFixtures.referenceDate,
                statusLabel: "İmzalı"
            )
        ]

        let filtered = ReportSearchFilters.filterSignatures(entries, query: "ABC")
        XCTAssertEqual(filtered.count, 1)
        XCTAssertEqual(filtered.first?.customerName, "ABC Market")
    }

    func testCustomerAnalyticsViewModelUsesCachedOrdersWithoutRepeatedFetch() async throws {
        let container = DIContainer.mock()
        let deps = makeDeps(from: container)
        let admin = DomainFixtures.adminUser()
        let customer = DomainFixtures.customer(name: "Cached Customer")
        try await deps.userRepository.save(admin)
        try await deps.customerRepository.save(customer)
        try await container.workOrderRepository.save(
            DomainFixtures.workOrder(customerId: customer.id, status: .completed)
        )

        let vm = CustomerAnalyticsViewModel(actor: admin, dependencies: deps)
        await vm.load()
        vm.selectCustomer(customer)

        XCTAssertEqual(vm.summary?.customerName, "Cached Customer")
        XCTAssertEqual(vm.summary?.totalVisits, 1)

        vm.customerSearchText = "Cached"
        XCTAssertEqual(vm.filteredCustomers.count, 1)
    }

    func testReportNavigationCachePreservesLoadedPanel() async throws {
        let container = DIContainer.mock()
        let deps = makeDeps(from: container)
        let admin = DomainFixtures.adminUser()
        let customer = DomainFixtures.customer()
        try await deps.userRepository.save(admin)
        try await deps.customerRepository.save(customer)
        let order = DomainFixtures.workOrder(customerId: customer.id, status: .completed)
        try await container.workOrderRepository.save(order)
        try await deps.signatureRepository.save(
            DomainFixtures.signature(workOrderId: order.id, kind: .customer)
        )

        let cache = AdminReportDetailViewModelCache(actor: admin, dependencies: deps)
        let signatures = cache.viewModel(for: .signatures)
        await signatures.load()
        let photos = cache.viewModel(for: .photos)
        await photos.load()

        XCTAssertEqual(signatures.phase, .loaded)
        XCTAssertFalse(signatures.payload.signatureEntries.isEmpty)
        XCTAssertTrue(signatures === cache.viewModel(for: .signatures))
        XCTAssertTrue(photos === cache.viewModel(for: .photos))
    }
}
