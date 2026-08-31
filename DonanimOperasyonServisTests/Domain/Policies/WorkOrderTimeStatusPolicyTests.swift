import XCTest
@testable import DonanimOperasyonServis

final class WorkOrderTimeStatusPolicyTests: XCTestCase {

    private var calendar: Calendar!
    private let referenceDate = Date(timeIntervalSince1970: 1_720_000_000) // 2024-07-03 12:26:40 UTC

    override func setUp() {
        super.setUp()
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 3 * 3600)!
        calendar = cal
    }

    private func makeOrder(
        id: String = "wo-1",
        scheduledDate: Date,
        scheduledTimeRange: ScheduledTimeRange? = nil,
        status: WorkOrderStatus = .assigned
    ) -> WorkOrder {
        DomainFixtures.workOrder(
            id: WorkOrderID(id),
            scheduledDate: scheduledDate,
            scheduledTimeRange: scheduledTimeRange,
            status: status
        )
    }

    private func dayStart(offset: Int) -> Date {
        let base = calendar.startOfDay(for: referenceDate)
        return calendar.date(byAdding: .day, value: offset, to: base)!
    }

    func testPastActiveJobIsDelayed() {
        let order = makeOrder(scheduledDate: dayStart(offset: -1))
        let status = WorkOrderTimeStatusPolicy.timeStatus(
            for: order,
            now: referenceDate,
            calendar: calendar
        )
        XCTAssertEqual(status, .delayed)
        XCTAssertTrue(WorkOrderTimeStatusPolicy.isOverdue(order, now: referenceDate, calendar: calendar))
    }

    func testTodayActiveJobBeforeWindowEndIsToday() {
        let start = calendar.date(byAdding: .hour, value: -1, to: referenceDate)!
        let end = calendar.date(byAdding: .hour, value: 2, to: referenceDate)!
        let order = makeOrder(
            scheduledDate: start,
            scheduledTimeRange: ScheduledTimeRange(start: start, end: end)
        )
        let status = WorkOrderTimeStatusPolicy.timeStatus(
            for: order,
            now: referenceDate,
            calendar: calendar
        )
        XCTAssertEqual(status, .today)
        XCTAssertFalse(WorkOrderTimeStatusPolicy.isOverdue(order, now: referenceDate, calendar: calendar))
    }

    func testTodayJobAfterWindowEndIsWindowPassed() {
        let start = calendar.date(byAdding: .hour, value: -4, to: referenceDate)!
        let end = calendar.date(byAdding: .hour, value: -1, to: referenceDate)!
        let order = makeOrder(
            scheduledDate: start,
            scheduledTimeRange: ScheduledTimeRange(start: start, end: end)
        )
        let status = WorkOrderTimeStatusPolicy.timeStatus(
            for: order,
            now: referenceDate,
            calendar: calendar
        )
        XCTAssertEqual(status, .windowPassed)
        XCTAssertTrue(WorkOrderTimeStatusPolicy.isOverdue(order, now: referenceDate, calendar: calendar))
    }

    func testTomorrowJobIsApproaching() {
        let tomorrow = dayStart(offset: 1).addingTimeInterval(10_800)
        let order = makeOrder(scheduledDate: tomorrow)
        let status = WorkOrderTimeStatusPolicy.timeStatus(
            for: order,
            now: referenceDate,
            calendar: calendar
        )
        XCTAssertEqual(status, .approaching)
    }

    func testFutureJobIsScheduled() {
        let future = dayStart(offset: 5)
        let order = makeOrder(scheduledDate: future)
        let status = WorkOrderTimeStatusPolicy.timeStatus(
            for: order,
            now: referenceDate,
            calendar: calendar
        )
        XCTAssertEqual(status, .scheduled)
    }

    func testCompletedJobHasNoTimeStatus() {
        let order = makeOrder(scheduledDate: dayStart(offset: -2), status: .completed)
        XCTAssertNil(
            WorkOrderTimeStatusPolicy.timeStatus(for: order, now: referenceDate, calendar: calendar)
        )
        XCTAssertFalse(WorkOrderTimeStatusPolicy.isOverdue(order, now: referenceDate, calendar: calendar))
    }

    func testRejectedJobHasNoTimeStatus() {
        let order = makeOrder(scheduledDate: dayStart(offset: -2), status: .rejected)
        XCTAssertNil(
            WorkOrderTimeStatusPolicy.timeStatus(for: order, now: referenceDate, calendar: calendar)
        )
    }

    func testTodayWithoutTimeRangeBeforeDayEndIsToday() {
        let order = makeOrder(scheduledDate: referenceDate, scheduledTimeRange: nil)
        let status = WorkOrderTimeStatusPolicy.timeStatus(
            for: order,
            now: referenceDate,
            calendar: calendar
        )
        XCTAssertEqual(status, .today)
        XCTAssertFalse(WorkOrderTimeStatusPolicy.isOverdue(order, now: referenceDate, calendar: calendar))
    }

    func testYesterdayWithoutTimeRangeIsDelayedAtDayBoundary() {
        let order = makeOrder(scheduledDate: dayStart(offset: -1), scheduledTimeRange: nil)
        let now = dayStart(offset: 0).addingTimeInterval(60)
        XCTAssertEqual(
            WorkOrderTimeStatusPolicy.timeStatus(for: order, now: now, calendar: calendar),
            .delayed
        )
    }

    func testTimezoneBoundaryUsesCalendarDay() {
        var utcCalendar = Calendar(identifier: .gregorian)
        utcCalendar.timeZone = TimeZone(secondsFromGMT: 0)!

        var trCalendar = Calendar(identifier: .gregorian)
        trCalendar.timeZone = TimeZone(secondsFromGMT: 3 * 3600)!

        let instant = Date(timeIntervalSince1970: 1_719_993_600) // 2024-07-02 21:00 UTC = 2024-07-03 00:00 TR
        let order = makeOrder(scheduledDate: instant, scheduledTimeRange: nil)

        let trStatus = WorkOrderTimeStatusPolicy.timeStatus(for: order, now: instant, calendar: trCalendar)
        let utcStatus = WorkOrderTimeStatusPolicy.timeStatus(
            for: order,
            now: instant.addingTimeInterval(3600),
            calendar: utcCalendar
        )

        XCTAssertEqual(trStatus, .today)
        XCTAssertEqual(utcStatus, .today)
    }

    func testDashboardOverdueMatchesDelayedAndWindowPassed() {
        let delayed = makeOrder(scheduledDate: dayStart(offset: -1))
        let start = calendar.date(byAdding: .hour, value: -3, to: referenceDate)!
        let end = calendar.date(byAdding: .hour, value: -1, to: referenceDate)!
        let windowPassed = makeOrder(
            id: "wo-window",
            scheduledDate: start,
            scheduledTimeRange: ScheduledTimeRange(start: start, end: end)
        )
        let today = makeOrder(scheduledDate: referenceDate, scheduledTimeRange: nil)

        let orders = [delayed, windowPassed, today]
        let overdueFilter = WorkOrderTimeStatusPolicy.filterDashboardOverdue(
            orders,
            now: referenceDate,
            calendar: calendar
        )
        let kpiCount = orders.filter {
            OperatorDashboardOperations.isOverdue($0, now: referenceDate, calendar: calendar)
        }.count

        XCTAssertEqual(overdueFilter.count, 2)
        XCTAssertEqual(kpiCount, 2)
        XCTAssertEqual(
            WorkOrderTimeStatusPolicy.timeStatus(for: delayed, now: referenceDate, calendar: calendar)?.countsAsDashboardOverdue,
            true
        )
        XCTAssertEqual(
            WorkOrderTimeStatusPolicy.timeStatus(for: windowPassed, now: referenceDate, calendar: calendar)?.countsAsDashboardOverdue,
            true
        )
        XCTAssertEqual(
            WorkOrderTimeStatusPolicy.timeStatus(for: today, now: referenceDate, calendar: calendar)?.countsAsDashboardOverdue,
            false
        )
    }

    func testOperatorAndTechnicianMappingProduceSameStatus() {
        let order = makeOrder(scheduledDate: dayStart(offset: -1))
        let operatorStatus = WorkOrderPresentationMapping.timeStatus(
            for: order,
            now: referenceDate,
            calendar: calendar
        )
        let technicianStatus = WorkOrderPresentationMapping.timeStatus(
            for: order,
            now: referenceDate,
            calendar: calendar
        )
        XCTAssertEqual(operatorStatus, technicianStatus)
        XCTAssertEqual(operatorStatus, .delayed)
    }

    func testTimeStatusFilterUsesLocalDataset() {
        let delayed = makeOrder(id: "wo-delayed", scheduledDate: dayStart(offset: -1))
        let scheduled = makeOrder(id: "wo-future", scheduledDate: dayStart(offset: 4))
        let orders = [delayed, scheduled]

        let filtered = WorkOrderTimeStatusPolicy.filter(
            orders,
            matching: .delayed,
            now: referenceDate,
            calendar: calendar
        )
        XCTAssertEqual(filtered.map(\.id), [WorkOrderID("wo-delayed")])
    }

    func testPriorityIsIndependentFromTimeStatus() {
        let urgent = makeOrder(scheduledDate: dayStart(offset: 4))
        XCTAssertEqual(urgent.priority, .normal)
        let status = WorkOrderTimeStatusPolicy.timeStatus(for: urgent, now: referenceDate, calendar: calendar)
        XCTAssertEqual(status, .scheduled)
    }
}

@MainActor
final class WorkOrderTimeStatusOfflineConsistencyTests: XCTestCase {

    func testCachedOrdersProduceSameTimeStatusOffline() async throws {
        let container = DIContainer.mock()
        let operatorUser = DomainFixtures.operatorUser()
        let technician = DomainFixtures.technicianUser()
        let customer = DomainFixtures.customer(createdByUserId: operatorUser.id)
        try await container.userRepository.save(operatorUser)
        try await container.userRepository.save(technician)
        try await container.customerRepository.save(customer)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_720_000_000))
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now)!

        try await container.workOrderRepository.save(
            DomainFixtures.workOrder(
                id: WorkOrderID("wo-offline-time"),
                assignedTechnicianId: technician.id,
                customerId: customer.id,
                scheduledDate: yesterday,
                scheduledTimeRange: nil,
                status: .assigned
            )
        )

        let reachability = FakeNetworkReachability(isReachable: false)
        let baseOperatorDeps = container.makeOperatorDependencies()
        let operatorDeps = OperatorDependencies(
            getWorkOrders: baseOperatorDeps.getWorkOrders,
            getWorkOrder: baseOperatorDeps.getWorkOrder,
            workOrderService: baseOperatorDeps.workOrderService,
            customerService: baseOperatorDeps.customerService,
            workOrderTemplateService: baseOperatorDeps.workOrderTemplateService,
            customerRepository: baseOperatorDeps.customerRepository,
            userRepository: baseOperatorDeps.userRepository,
            localDirectoryCacheRefresh: baseOperatorDeps.localDirectoryCacheRefresh,
            workOrderNoteRepository: baseOperatorDeps.workOrderNoteRepository,
            workOrderPhotoRepository: baseOperatorDeps.workOrderPhotoRepository,
            workOrderLocationRepository: baseOperatorDeps.workOrderLocationRepository,
            signatureRepository: baseOperatorDeps.signatureRepository,
            statusHistoryRepository: baseOperatorDeps.statusHistoryRepository,
            editRequestRepository: baseOperatorDeps.editRequestRepository,
            editRequestService: baseOperatorDeps.editRequestService,
            customerSatisfactionRepository: baseOperatorDeps.customerSatisfactionRepository,
            customerSatisfactionService: baseOperatorDeps.customerSatisfactionService,
            notificationRepository: baseOperatorDeps.notificationRepository,
            syncOperationRepository: baseOperatorDeps.syncOperationRepository,
            syncConflictRepository: baseOperatorDeps.syncConflictRepository,
            conflictResolver: baseOperatorDeps.conflictResolver,
            networkReachability: reachability,
            profileAccountService: baseOperatorDeps.profileAccountService,
            storageDataSource: baseOperatorDeps.storageDataSource
        )

        let technicianDeps = container.makeTechnicianDependencies()
        let operatorVM = OperatorWorkOrderListViewModel(actor: operatorUser, dependencies: operatorDeps)
        let technicianVM = TechnicianWorkOrderListViewModel(actor: technician, dependencies: technicianDeps)

        await operatorVM.load()
        await technicianVM.load()

        let operatorStatus = operatorVM.cards.first?.timeStatus
        let technicianStatus = technicianVM.cards.first?.timeStatus
        XCTAssertEqual(operatorStatus, technicianStatus)
        XCTAssertEqual(operatorStatus, .delayed)
    }
}
