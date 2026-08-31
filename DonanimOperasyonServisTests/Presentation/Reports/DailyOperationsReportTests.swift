import XCTest
@testable import DonanimOperasyonServis

final class DailyOperationsAggregatorTests: XCTestCase {
    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Istanbul")!
        return cal
    }

    private let customer = CustomerID("cust-daily")
    private let techA = UserID("tech-a")
    private let techB = UserID("tech-b")
    private let reportDay = DateComponents(calendar: Calendar(identifier: .gregorian), year: 2026, month: 8, day: 26).date!

    private var customers: [CustomerID: Customer] {
        [customer: DomainFixtures.customer(id: customer, name: "ABC Market")]
    }

    private var technicians: [UserID: User] {
        [
            techA: DomainFixtures.technicianUser(id: techA, fullName: "Mehmet Kerem"),
            techB: DomainFixtures.technicianUser(id: techB, fullName: "Ahmet Yılmaz")
        ]
    }

    private var activeTechnicians: [User] {
        Array(technicians.values)
    }

    func testDailyReportCountsOpenedWorkOrders() {
        let day = reportDay
        let orders = [
            order(id: "wo-open-1", scheduled: day, created: day),
            order(id: "wo-open-2", scheduled: day, created: day),
            order(id: "wo-other", scheduled: previousDay(from: day), created: previousDay(from: day))
        ]

        let report = buildReport(day: day, orders: orders)
        XCTAssertEqual(report.kpis.openedCount, 2)
    }

    func testDailyReportCountsCompletedWorkOrders() {
        let day = reportDay
        let orders = [
            order(id: "wo-done-1", scheduled: day, created: day, status: .completed, completedAt: day),
            order(id: "wo-done-2", scheduled: day, created: day, status: .completed, completedAt: day),
            order(id: "wo-open", scheduled: day, created: day, status: .assigned)
        ]

        let report = buildReport(day: day, orders: orders)
        XCTAssertEqual(report.kpis.completedCount, 2)
    }

    func testDailyReportCountsPausedWorkOrders() {
        let day = reportDay
        let orders = [
            order(id: "wo-paused", scheduled: day, created: day, status: .paused, pauseReason: .partWaiting),
            order(id: "wo-active", scheduled: day, created: day, status: .inProgress)
        ]

        let report = buildReport(day: day, orders: orders)
        XCTAssertEqual(report.kpis.pausedCount, 1)
        XCTAssertEqual(report.kpis.inProgressCount, 1)
    }

    func testDailyReportCountsUrgentWorkOrders() {
        let day = reportDay
        let orders = [
            order(id: "wo-urgent", scheduled: day, created: day, priority: .urgent, status: .assigned),
            order(id: "wo-normal", scheduled: day, created: day, priority: .normal, status: .assigned),
            order(id: "wo-urgent-done", scheduled: day, created: day, priority: .urgent, status: .completed, completedAt: day)
        ]

        let report = buildReport(day: day, orders: orders)
        XCTAssertEqual(report.kpis.urgentCount, 1)
    }

    func testDailyReportTechnicianBreakdown() {
        let day = reportDay
        let orders = [
            order(id: "wo-a1", scheduled: day, created: day, tech: techA, status: .completed, completedAt: day),
            order(id: "wo-a2", scheduled: day, created: day, tech: techA, status: .inProgress),
            order(id: "wo-b1", scheduled: day, created: day, tech: techB, status: .assigned)
        ]

        let report = buildReport(day: day, orders: orders)
        XCTAssertEqual(report.technicianSummaries.count, 2)
        XCTAssertEqual(report.technicianSummaries[0].name, "Mehmet Kerem")
        XCTAssertEqual(report.technicianSummaries[0].completedCount, 1)
        XCTAssertEqual(report.technicianSummaries[0].assignedCount, 2)
        XCTAssertEqual(report.technicianSummaries[1].name, "Ahmet Yılmaz")
    }

    func testDailyReportCustomerCount() {
        let day = reportDay
        let customerB = CustomerID("cust-b")
        var customers = self.customers
        customers[customerB] = DomainFixtures.customer(id: customerB, name: "XYZ")

        let orders = [
            order(id: "wo-1", scheduled: day, created: day, customerId: customer),
            order(id: "wo-2", scheduled: day, created: day, customerId: customer),
            order(id: "wo-3", scheduled: day, created: day, customerId: customerB)
        ]

        let report = DailyOperationsAggregator.buildReport(
            selectedDay: day,
            orders: orders,
            customers: customers,
            technicians: technicians,
            activeTechnicians: activeTechnicians,
            statusHistories: [:],
            calendar: calendar
        )
        XCTAssertEqual(report.customerSummary.uniqueCustomerCount, 2)
    }

    func testDailyReportWorkTypeAggregation() {
        let day = reportDay
        let orders = [
            order(id: "wo-r1", scheduled: day, created: day, workType: .repair),
            order(id: "wo-r2", scheduled: day, created: day, workType: .repair),
            order(id: "wo-m1", scheduled: day, created: day, workType: .maintenance)
        ]

        let report = buildReport(day: day, orders: orders)
        XCTAssertEqual(report.customerSummary.workTypeCounts[.repair], 2)
        XCTAssertEqual(report.customerSummary.workTypeCounts[.maintenance], 1)
    }

    func testDailyReportDeviceAggregation() {
        let day = reportDay
        let orders = [
            order(id: "wo-p1", scheduled: day, created: day, deviceCategory: .pos),
            order(id: "wo-p2", scheduled: day, created: day, deviceCategory: .pos),
            order(id: "wo-pr1", scheduled: day, created: day, deviceCategory: .printer)
        ]

        let report = buildReport(day: day, orders: orders)
        XCTAssertEqual(report.customerSummary.deviceCategoryCounts[.pos], 2)
        XCTAssertEqual(report.customerSummary.deviceCategoryCounts[.printer], 1)
    }

    func testDailyReportChronologicalOrdering() {
        let day = reportDay
        let morning = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day)!
        let afternoon = calendar.date(bySettingHour: 14, minute: 0, second: 0, of: day)!
        let orders = [
            order(id: "wo-pm", scheduled: afternoon, created: day, workOrderNumber: "WO-PM"),
            order(id: "wo-am", scheduled: morning, created: day, workOrderNumber: "WO-AM")
        ]

        let report = buildReport(day: day, orders: orders)
        XCTAssertEqual(report.workflowEntries.map(\.workOrderNumber), ["WO-AM", "WO-PM"])
    }

    func testDailyReportUsesWorkOrderTimeStatusPolicy() {
        let day = calendar.startOfDay(for: DomainFixtures.referenceDate)
        let morning = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day)!
        let windowEnd = calendar.date(bySettingHour: 10, minute: 0, second: 0, of: day)!
        let range = ScheduledTimeRange(uncheckedStart: morning, end: windowEnd)
        let orders = [
            DomainFixtures.workOrder(
                id: WorkOrderID("wo-delayed"),
                workOrderNumber: "WO-DELAYED",
                assignedTechnicianId: techA,
                customerId: customer,
                scheduledDate: day,
                scheduledTimeRange: range,
                status: .assigned,
                createdAt: day,
                updatedAt: day
            ),
            order(id: "wo-ok", scheduled: day, created: day, status: .completed, completedAt: day)
        ]

        let report = buildReport(day: day, orders: orders)
        XCTAssertEqual(report.kpis.delayedCount, 1)
        XCTAssertEqual(report.delayedEntries.first?.workOrderNumber, "WO-DELAYED")
    }

    func testDailyReportDateBoundary() {
        let dayStart = calendar.startOfDay(for: reportDay)
        let justBefore = dayStart.addingTimeInterval(-1)
        let justAfter = dayStart.addingTimeInterval(60)

        let orders = [
            order(id: "wo-before", scheduled: justBefore, created: justBefore),
            order(id: "wo-after", scheduled: justAfter, created: justAfter)
        ]

        let report = buildReport(day: reportDay, orders: orders)
        XCTAssertEqual(report.kpis.openedCount, 1)
        XCTAssertEqual(report.workflowEntries.count, 1)
        XCTAssertEqual(report.workflowEntries.first?.workOrderNumber, "WO-AFTER")
    }

    func testDailyReportRejectedCountUsesDomainSemantics() {
        let day = reportDay
        let orders = [
            order(id: "wo-rej", scheduled: day, created: day, status: .rejected, updatedAt: day),
            order(id: "wo-ok", scheduled: day, created: day, status: .completed, completedAt: day)
        ]

        let report = buildReport(day: day, orders: orders)
        XCTAssertEqual(report.kpis.rejectedCount, 1)
    }

    private func buildReport(day: Date, orders: [WorkOrder]) -> DailyOperationsReport {
        DailyOperationsAggregator.buildReport(
            selectedDay: day,
            orders: orders,
            customers: customers,
            technicians: technicians,
            activeTechnicians: activeTechnicians,
            statusHistories: [:],
            calendar: calendar
        )
    }

    private func previousDay(from day: Date) -> Date {
        calendar.date(byAdding: .day, value: -1, to: day)!
    }

    private func order(
        id: String,
        scheduled: Date,
        created: Date,
        workOrderNumber: String? = nil,
        customerId: CustomerID? = nil,
        tech: UserID? = nil,
        workType: WorkType = .repair,
        deviceCategory: DeviceCategory = .pos,
        priority: WorkOrderPriority = .normal,
        status: WorkOrderStatus = .assigned,
        completedAt: Date? = nil,
        updatedAt: Date? = nil,
        pauseReason: PauseReason? = nil
    ) -> WorkOrder {
        DomainFixtures.workOrder(
            id: WorkOrderID(id),
            workOrderNumber: workOrderNumber ?? id.replacingOccurrences(of: "wo-", with: "WO-").uppercased(),
            assignedTechnicianId: tech ?? techA,
            customerId: customerId ?? customer,
            workType: workType,
            deviceCategory: deviceCategory,
            priority: priority,
            scheduledDate: scheduled,
            scheduledTimeRange: nil,
            status: status,
            currentPauseReason: pauseReason,
            createdAt: created,
            updatedAt: updatedAt ?? created,
            completedAt: completedAt
        )
    }
}

@MainActor
final class DailyOperationsReportViewModelTests: XCTestCase {
    func testDailyReportUsesLocalCacheOffline() async throws {
        let container = DIContainer.mock()
        let deps = container.makeAdminDependencies()
        let admin = DomainFixtures.adminUser()
        let customer = DomainFixtures.customer()
        let tech = DomainFixtures.technicianUser()
        let day = Calendar.current.startOfDay(for: DomainFixtures.referenceDate)

        try await deps.userRepository.save(admin)
        try await deps.userRepository.save(tech)
        try await deps.customerRepository.save(customer)
        try await container.workOrderRepository.save(
            DomainFixtures.workOrder(
                id: WorkOrderID("wo-cache-day"),
                assignedTechnicianId: tech.id,
                customerId: customer.id,
                scheduledDate: day,
                status: .assigned,
                createdAt: day
            )
        )

        let vm = DailyOperationsReportViewModel(actor: admin, dependencies: deps)
        vm.selectedDay = day
        await vm.load()
        XCTAssertEqual(vm.phase, .ready)
        let firstCount = vm.report?.kpis.openedCount

        vm.selectPreviousDay()
        XCTAssertNotEqual(vm.phase, .loading)
        XCTAssertEqual(vm.remoteLoadCount, 1)

        vm.selectNextDay()
        XCTAssertEqual(vm.report?.kpis.openedCount, firstCount)
        XCTAssertEqual(vm.remoteLoadCount, 1)
    }

    func testDailyReportDoesNotCreateNPlusOne() async throws {
        let container = DIContainer.mock()
        let deps = container.makeAdminDependencies()
        let admin = DomainFixtures.adminUser()
        let customer = DomainFixtures.customer()
        try await deps.userRepository.save(admin)
        try await deps.customerRepository.save(customer)

        for index in 0..<3 {
            try await container.workOrderRepository.save(
                DomainFixtures.workOrder(
                    id: WorkOrderID("wo-nplus-\(index)"),
                    customerId: customer.id,
                    scheduledDate: DomainFixtures.referenceDate,
                    createdAt: DomainFixtures.referenceDate
                )
            )
        }

        let vm = DailyOperationsReportViewModel(actor: admin, dependencies: deps)
        vm.selectedDay = Calendar.current.startOfDay(for: DomainFixtures.referenceDate)
        await vm.load()
        XCTAssertEqual(vm.remoteLoadCount, 1)

        vm.selectPreviousDay()
        vm.selectNextDay()
        vm.selectDay(DomainFixtures.referenceDate)
        XCTAssertEqual(vm.remoteLoadCount, 1)
    }

    func testDailyReportNavigationBackIsStable() async throws {
        let container = DIContainer.mock()
        let deps = container.makeAdminDependencies()
        let admin = DomainFixtures.adminUser()
        let customer = DomainFixtures.customer()
        try await deps.userRepository.save(admin)
        try await deps.customerRepository.save(customer)
        try await container.workOrderRepository.save(
            DomainFixtures.workOrder(
                customerId: customer.id,
                scheduledDate: DomainFixtures.referenceDate,
                status: .completed,
                completedAt: DomainFixtures.referenceDate
            )
        )

        let cache = DailyOperationsReportViewModelCache(actor: admin, dependencies: deps)
        let first = cache.viewModel()
        first.selectedDay = Calendar.current.startOfDay(for: DomainFixtures.referenceDate)
        await first.load()
        XCTAssertEqual(first.phase, .ready)
        let metricsBefore = first.report?.kpis.completedCount

        let cancelled = Task { await first.load() }
        cancelled.cancel()
        await cancelled.value
        XCTAssertNotEqual(first.phase, .loading)

        let second = cache.viewModel()
        XCTAssertTrue(first === second)
        XCTAssertEqual(second.report?.kpis.completedCount, metricsBefore)
    }

    func testDailyOperationsReportKindReturnsEmptyGenericPayload() async throws {
        let container = DIContainer.mock()
        let deps = container.makeAdminDependencies()
        let admin = DomainFixtures.adminUser()
        try await deps.userRepository.save(admin)

        let vm = AdminReportDetailViewModel(kind: .dailyOperations, actor: admin, dependencies: deps)
        await vm.load()
        XCTAssertNotEqual(vm.phase, .loading)
        XCTAssertTrue(vm.payload.isEmpty)
    }
}
