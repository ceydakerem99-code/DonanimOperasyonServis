import XCTest
@testable import DonanimOperasyonServis

final class FaultRecurrenceAggregatorTests: XCTestCase {
    private let customerA = CustomerID("cust-a")
    private let customerB = CustomerID("cust-b")
    private let techA = UserID("tech-a")
    private let techB = UserID("tech-b")

    private var customers: [CustomerID: Customer] {
        [
            customerA: DomainFixtures.customer(id: customerA, name: "ABC Müşterisi"),
            customerB: DomainFixtures.customer(id: customerB, name: "XYZ Market")
        ]
    }

    private var technicians: [UserID: User] {
        [
            techA: DomainFixtures.technicianUser(id: techA, fullName: "Mehmet Kerem"),
            techB: DomainFixtures.technicianUser(id: techB, fullName: "Ahmet Yılmaz")
        ]
    }

    func testSameCustomerAndDeviceCountsRepairRecurrence() {
        let orders = [
            repairOrder(id: "wo-1", customerId: customerA, serial: "POS-01", tech: techA, issue: "Bağlantı problemi", date: date(2026, 8, 20)),
            repairOrder(id: "wo-2", customerId: customerA, serial: "POS-01", tech: techB, issue: "Bağlantı problemi", date: date(2026, 8, 24)),
            repairOrder(id: "wo-3", customerId: customerA, serial: "POS-01", tech: techA, issue: "Ekran donması", date: date(2026, 8, 26))
        ]

        let entries = FaultRecurrenceAggregator.deviceEntries(
            orders: orders,
            customers: customers,
            technicians: technicians
        )

        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].recurrenceCount, 3)
        XCTAssertEqual(entries[0].customerName, "ABC Müşterisi")
        XCTAssertEqual(entries[0].serialNumber, "POS-01")
        XCTAssertEqual(entries[0].issueLabel, "Ekran donması")
        XCTAssertEqual(entries[0].technicianNames, ["Ahmet Yılmaz", "Mehmet Kerem"])
    }

    func testSameDeviceDifferentIssueStillGroupsByCustomerAndSerial() {
        let orders = [
            repairOrder(id: "wo-1", customerId: customerA, serial: "POS-01", tech: techA, issue: "Bağlantı", date: date(2026, 8, 10)),
            repairOrder(id: "wo-2", customerId: customerA, serial: "POS-01", tech: techA, issue: "Yazıcı", date: date(2026, 8, 12))
        ]

        let entries = FaultRecurrenceAggregator.deviceEntries(
            orders: orders,
            customers: customers,
            technicians: technicians
        )

        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].recurrenceCount, 2)
        XCTAssertEqual(entries[0].issueLabel, "Yazıcı")
    }

    func testDifferentCustomersDoNotMix() {
        let orders = [
            repairOrder(id: "wo-1", customerId: customerA, serial: "POS-01", tech: techA, issue: "A", date: date(2026, 8, 10)),
            repairOrder(id: "wo-2", customerId: customerA, serial: "POS-01", tech: techA, issue: "B", date: date(2026, 8, 11)),
            repairOrder(id: "wo-3", customerId: customerB, serial: "POS-01", tech: techB, issue: "C", date: date(2026, 8, 12)),
            repairOrder(id: "wo-4", customerId: customerB, serial: "POS-01", tech: techB, issue: "D", date: date(2026, 8, 13))
        ]

        let entries = FaultRecurrenceAggregator.deviceEntries(
            orders: orders,
            customers: customers,
            technicians: technicians
        )

        XCTAssertEqual(entries.count, 2)
        XCTAssertTrue(entries.allSatisfy { Set([customerA, customerB]).contains($0.customerId) })
    }

    func testSameDeviceDifferentSerialCreatesSeparateGroups() {
        let orders = [
            repairOrder(id: "wo-1", customerId: customerA, serial: "POS-01", tech: techA, issue: "A", date: date(2026, 8, 10)),
            repairOrder(id: "wo-2", customerId: customerA, serial: "POS-01", tech: techA, issue: "B", date: date(2026, 8, 11)),
            repairOrder(id: "wo-3", customerId: customerA, serial: "POS-02", tech: techA, issue: "C", date: date(2026, 8, 12)),
            repairOrder(id: "wo-4", customerId: customerA, serial: "POS-02", tech: techA, issue: "D", date: date(2026, 8, 13))
        ]

        let entries = FaultRecurrenceAggregator.deviceEntries(
            orders: orders,
            customers: customers,
            technicians: technicians
        )

        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(Set(entries.map(\.serialNumber)), Set(["POS-01", "POS-02"]))
    }

    func testDuplicateWorkOrderIsNotCountedTwice() {
        let order = repairOrder(id: "wo-1", customerId: customerA, serial: "POS-01", tech: techA, issue: "A", date: date(2026, 8, 10))
        let orders = [order, order, order]

        let entries = FaultRecurrenceAggregator.deviceEntries(
            orders: orders,
            customers: customers,
            technicians: technicians
        )

        XCTAssertTrue(entries.isEmpty)
    }

    func testRejectedRepairOrdersAreExcluded() {
        let orders = [
            repairOrder(id: "wo-1", customerId: customerA, serial: "POS-01", tech: techA, issue: "A", date: date(2026, 8, 10)),
            repairOrder(id: "wo-2", customerId: customerA, serial: "POS-01", tech: techA, issue: "B", date: date(2026, 8, 11), status: .rejected),
            repairOrder(id: "wo-3", customerId: customerA, serial: "POS-01", tech: techA, issue: "C", date: date(2026, 8, 12))
        ]

        let entries = FaultRecurrenceAggregator.deviceEntries(
            orders: orders,
            customers: customers,
            technicians: technicians
        )

        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].recurrenceCount, 2)
    }

    func testNonRepairWorkOrdersAreExcluded() {
        let orders = [
            repairOrder(id: "wo-1", customerId: customerA, serial: "POS-01", tech: techA, issue: "A", date: date(2026, 8, 10)),
            DomainFixtures.workOrder(
                id: WorkOrderID("wo-maint-1"),
                customerId: customerA,
                workType: .maintenance,
                serialNumber: "POS-01",
                status: .completed,
                completedAt: date(2026, 8, 11)
            ),
            repairOrder(id: "wo-2", customerId: customerA, serial: "POS-01", tech: techA, issue: "B", date: date(2026, 8, 12))
        ]

        let entries = FaultRecurrenceAggregator.deviceEntries(
            orders: orders,
            customers: customers,
            technicians: technicians
        )

        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].recurrenceCount, 2)
    }

    func testSortingUsesRecurrenceThenLatestDate() {
        let orders = [
            repairOrder(id: "wo-a1", customerId: customerA, serial: "POS-A", tech: techA, issue: "A", date: date(2026, 8, 20)),
            repairOrder(id: "wo-a2", customerId: customerA, serial: "POS-A", tech: techA, issue: "B", date: date(2026, 8, 21)),
            repairOrder(id: "wo-b1", customerId: customerA, serial: "POS-B", tech: techA, issue: "C", date: date(2026, 8, 26)),
            repairOrder(id: "wo-b2", customerId: customerA, serial: "POS-B", tech: techA, issue: "D", date: date(2026, 8, 25)),
            repairOrder(id: "wo-b3", customerId: customerA, serial: "POS-B", tech: techA, issue: "E", date: date(2026, 8, 24)),
            repairOrder(id: "wo-c1", customerId: customerA, serial: "POS-C", tech: techA, issue: "F", date: date(2026, 8, 27)),
            repairOrder(id: "wo-c2", customerId: customerA, serial: "POS-C", tech: techA, issue: "G", date: date(2026, 8, 27))
        ]

        let entries = FaultRecurrenceAggregator.deviceEntries(
            orders: orders,
            customers: customers,
            technicians: technicians
        )

        XCTAssertEqual(entries.map(\.serialNumber), ["POS-B", "POS-C", "POS-A"])
        XCTAssertEqual(entries[0].recurrenceCount, 3)
        XCTAssertEqual(entries[1].recurrenceCount, 2)
    }

    func testDetailRowsIncludeTechnicianAndDates() {
        let orders = [
            repairOrder(id: "wo-1", customerId: customerA, serial: "POS-01", tech: techA, issue: "Bağlantı", date: date(2026, 8, 20)),
            repairOrder(id: "wo-2", customerId: customerA, serial: "POS-01", tech: techB, issue: "Yazıcı", date: date(2026, 8, 26))
        ]
        let entries = FaultRecurrenceAggregator.deviceEntries(
            orders: orders,
            customers: customers,
            technicians: technicians
        )
        let rows = FaultRecurrenceAggregator.detailRows(
            for: entries[0],
            orders: orders,
            technicians: technicians
        )

        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0].workOrderNumber, orders[1].workOrderNumber)
        XCTAssertEqual(rows[0].technicianName, "Ahmet Yılmaz")
        XCTAssertEqual(rows[1].technicianName, "Mehmet Kerem")
    }

    func testSearchFilterMatchesCustomerDeviceTechnicianAndIssue() {
        let entry = FaultRecurrenceEntry(
            id: "1",
            customerId: customerA,
            customerName: "ABC Müşterisi",
            workplace: "ABC · İstanbul",
            serialNumber: "POS-01",
            deviceLabel: "POS · POS-01",
            workType: .repair,
            issueLabel: "Bağlantı problemi",
            recurrenceCount: 4,
            lastOccurrenceDate: date(2026, 8, 26),
            technicianNames: ["Mehmet Kerem"],
            workOrderIds: []
        )

        XCTAssertEqual(
            ReportSearchFilters.filterFaultRecurrenceEntries([entry], query: "mehmet", workType: nil, dateFrom: nil, dateTo: nil).count,
            1
        )
        XCTAssertEqual(
            ReportSearchFilters.filterFaultRecurrenceEntries([entry], query: "POS-01", workType: nil, dateFrom: nil, dateTo: nil).count,
            1
        )
        XCTAssertTrue(
            ReportSearchFilters.filterFaultRecurrenceEntries([entry], query: "xyz", workType: nil, dateFrom: nil, dateTo: nil).isEmpty
        )
    }

    func testDateRangeFilterUsesLastOccurrenceDate() {
        let entry = FaultRecurrenceEntry(
            id: "1",
            customerId: customerA,
            customerName: "ABC",
            workplace: "ABC",
            serialNumber: "POS-01",
            deviceLabel: "POS · POS-01",
            workType: .repair,
            issueLabel: "A",
            recurrenceCount: 2,
            lastOccurrenceDate: date(2026, 8, 26),
            technicianNames: [],
            workOrderIds: []
        )

        let filtered = ReportSearchFilters.filterFaultRecurrenceEntries(
            [entry],
            query: "",
            workType: nil,
            dateFrom: date(2026, 8, 25),
            dateTo: date(2026, 8, 27)
        )
        XCTAssertEqual(filtered.count, 1)

        let outOfRange = ReportSearchFilters.filterFaultRecurrenceEntries(
            [entry],
            query: "",
            workType: nil,
            dateFrom: date(2026, 8, 1),
            dateTo: date(2026, 8, 20)
        )
        XCTAssertTrue(outOfRange.isEmpty)
    }

    private func repairOrder(
        id: String,
        customerId: CustomerID,
        serial: String,
        tech: UserID,
        issue: String,
        date: Date,
        status: WorkOrderStatus = .completed
    ) -> WorkOrder {
        DomainFixtures.workOrder(
            id: WorkOrderID(id),
            workOrderNumber: id.uppercased(),
            assignedTechnicianId: tech,
            customerId: customerId,
            workType: .repair,
            serialNumber: serial,
            issueDescription: issue,
            scheduledDate: date,
            status: status,
            completedAt: status == .completed ? date : nil
        )
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day))!
    }
}

@MainActor
final class FaultRecurrenceAnalysisViewModelTests: XCTestCase {
    func testLoadBuildsRecurrenceEntriesFromSingleDataset() async throws {
        let container = DIContainer.mock()
        let deps = container.makeAdminDependencies()
        let admin = DomainFixtures.adminUser()
        let customer = DomainFixtures.customer(name: "ABC Müşterisi")
        let techA = DomainFixtures.technicianUser(fullName: "Mehmet Kerem")
        let techB = DomainFixtures.technicianUser(id: UserID("tech-b"), fullName: "Ahmet Yılmaz")

        try await deps.userRepository.save(admin)
        try await deps.userRepository.save(techA)
        try await deps.userRepository.save(techB)
        try await deps.customerRepository.save(customer)

        let baseDate = DomainFixtures.referenceDate
        for index in 0..<3 {
            try await container.workOrderRepository.save(
                DomainFixtures.workOrder(
                    id: WorkOrderID("wo-repeat-\(index)"),
                    workOrderNumber: "WO-R-\(index)",
                    assignedTechnicianId: index.isMultiple(of: 2) ? techA.id : techB.id,
                    customerId: customer.id,
                    workType: .repair,
                    serialNumber: "POS-01",
                    issueDescription: "Bağlantı problemi",
                    scheduledDate: baseDate.addingTimeInterval(Double(index) * 86400),
                    status: .completed,
                    completedAt: baseDate.addingTimeInterval(Double(index) * 86400)
                )
            )
        }

        let vm = FaultRecurrenceAnalysisViewModel(actor: admin, dependencies: deps)
        await vm.load()

        XCTAssertEqual(vm.phase, .ready)
        XCTAssertEqual(vm.entries.count, 1)
        XCTAssertEqual(vm.entries[0].recurrenceCount, 3)
        XCTAssertEqual(vm.entries[0].technicianNames.count, 2)
        XCTAssertEqual(vm.kpis?.recurringFaultCount, 1)
    }

    func testEmptyStateWhenNoRecurrence() async throws {
        let container = DIContainer.mock()
        let deps = container.makeAdminDependencies()
        let admin = DomainFixtures.adminUser()
        let customer = DomainFixtures.customer()
        try await deps.userRepository.save(admin)
        try await deps.customerRepository.save(customer)
        try await container.workOrderRepository.save(
            DomainFixtures.workOrder(customerId: customer.id, workType: .repair, status: .completed)
        )

        let vm = FaultRecurrenceAnalysisViewModel(actor: admin, dependencies: deps)
        await vm.load()

        XCTAssertEqual(vm.phase, .empty)
        XCTAssertTrue(vm.entries.isEmpty)
    }

    func testCacheSurvivesReloadAndDetailRowsUseCachedOrders() async throws {
        let container = DIContainer.mock()
        let deps = container.makeAdminDependencies()
        let admin = DomainFixtures.adminUser()
        let customer = DomainFixtures.customer()
        let tech = DomainFixtures.technicianUser()
        try await deps.userRepository.save(admin)
        try await deps.userRepository.save(tech)
        try await deps.customerRepository.save(customer)

        for index in 0..<2 {
            try await container.workOrderRepository.save(
                DomainFixtures.workOrder(
                    id: WorkOrderID("wo-cache-\(index)"),
                    assignedTechnicianId: tech.id,
                    customerId: customer.id,
                    workType: .repair,
                    serialNumber: "SN-CACHE",
                    status: .completed,
                    completedAt: DomainFixtures.referenceDate.addingTimeInterval(Double(index))
                )
            )
        }

        let cache = FaultRecurrenceAnalysisViewModelCache(actor: admin, dependencies: deps)
        let first = cache.viewModel()
        await first.load()
        let entry = try XCTUnwrap(first.entries.first)
        let rowsBefore = first.detailRows(for: entry)

        await first.load()
        let second = cache.viewModel()
        XCTAssertTrue(first === second)
        XCTAssertEqual(second.detailRows(for: entry).map(\.id), rowsBefore.map(\.id))
    }

    func testFaultRecurrenceReportKindReturnsEmptyGenericPayload() async throws {
        let container = DIContainer.mock()
        let deps = container.makeAdminDependencies()
        let admin = DomainFixtures.adminUser()
        try await deps.userRepository.save(admin)

        let vm = AdminReportDetailViewModel(kind: .faultRecurrence, actor: admin, dependencies: deps)
        await vm.load()
        XCTAssertNotEqual(vm.phase, .loading)
        XCTAssertTrue(vm.payload.isEmpty)
    }
}
