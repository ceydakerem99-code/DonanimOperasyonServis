import XCTest
@testable import DonanimOperasyonServis

final class TechnicianAssignmentFeatureTests: XCTestCase {

    private let techA = DomainFixtures.technicianUser(
        id: UserID("tech-a"),
        email: "alpha@example.com",
        fullName: "Mehmet Kerem"
    )
    private let techB = DomainFixtures.technicianUser(
        id: UserID("tech-b"),
        email: "beta@example.com",
        fullName: "Ayşe Demir"
    )

    func testSearchByNameOnlyMatchesFullNameParts() {
        XCTAssertTrue(TechnicianAssignmentSupport.matchesTechnicianNameSearch(techA, query: "Mehmet"))
        XCTAssertTrue(TechnicianAssignmentSupport.matchesTechnicianNameSearch(techA, query: "kerem"))
        XCTAssertTrue(TechnicianAssignmentSupport.matchesTechnicianNameSearch(techB, query: "ayse"))
    }

    func testEmailDoesNotMatchTechnicianSearch() {
        XCTAssertFalse(TechnicianAssignmentSupport.matchesTechnicianNameSearch(techA, query: "alpha@example.com"))
        XCTAssertFalse(TechnicianAssignmentSupport.matchesTechnicianNameSearch(techA, query: "mehmetkerem"))
    }

    func testWorkingStatusMapping() {
        let customer = DomainFixtures.customer()
        let availableOrder = DomainFixtures.workOrder(
            id: WorkOrderID("wo-assigned"),
            assignedTechnicianId: techA.id,
            customerId: customer.id,
            status: .assigned
        )
        let busyOrder = DomainFixtures.workOrder(
            id: WorkOrderID("wo-busy"),
            assignedTechnicianId: techB.id,
            customerId: customer.id,
            status: .inProgress
        )
        let pausedOrder = DomainFixtures.workOrder(
            id: WorkOrderID("wo-paused"),
            assignedTechnicianId: techA.id,
            customerId: customer.id,
            status: .paused
        )

        XCTAssertEqual(
            TechnicianAssignmentSupport.workingStatus(for: techA.id, orders: [availableOrder]),
            .available
        )
        XCTAssertEqual(
            TechnicianAssignmentSupport.workingStatus(for: techB.id, orders: [busyOrder]),
            .busy
        )
        XCTAssertEqual(
            TechnicianAssignmentSupport.workingStatus(for: techA.id, orders: [availableOrder, pausedOrder]),
            .available
        )
    }

    func testWorkloadCountsNonTerminalOnly() {
        let customer = DomainFixtures.customer()
        let orders = [
            DomainFixtures.workOrder(
                id: WorkOrderID("wo-u"),
                assignedTechnicianId: techA.id,
                customerId: customer.id,
                priority: .urgent,
                status: .assigned
            ),
            DomainFixtures.workOrder(
                id: WorkOrderID("wo-h"),
                assignedTechnicianId: techA.id,
                customerId: customer.id,
                priority: .high,
                status: .inProgress
            ),
            DomainFixtures.workOrder(
                id: WorkOrderID("wo-n"),
                assignedTechnicianId: techA.id,
                customerId: customer.id,
                priority: .normal,
                status: .paused
            ),
            DomainFixtures.workOrder(
                id: WorkOrderID("wo-done"),
                assignedTechnicianId: techA.id,
                customerId: customer.id,
                priority: .urgent,
                status: .completed
            )
        ]

        let load = TechnicianAssignmentSupport.workload(for: techA.id, orders: orders)
        XCTAssertEqual(load.urgent, 1)
        XCTAssertEqual(load.high, 1)
        XCTAssertEqual(load.normal, 1)
        XCTAssertEqual(load.activeTotal, 3)
    }

    func testRecommendationOrderingPrefersAvailableAndLowerLoad() {
        let customer = DomainFixtures.customer()
        let orders = [
            DomainFixtures.workOrder(
                assignedTechnicianId: techA.id,
                customerId: customer.id,
                priority: .urgent,
                status: .inProgress
            ),
            DomainFixtures.workOrder(
                id: WorkOrderID("wo-b"),
                assignedTechnicianId: techB.id,
                customerId: customer.id,
                priority: .normal,
                status: .assigned
            )
        ]

        let sorted = TechnicianAssignmentSupport.sortedTechniciansForAssignment([techA, techB], orders: orders)
        XCTAssertEqual(sorted.first?.id, techB.id)
    }

    func testAvailableTechnicianRanksBeforeBusy() {
        let customer = DomainFixtures.customer()
        let techBusy = DomainFixtures.technicianUser(id: UserID("tech-busy"), fullName: "Busy Tech")
        let techAvailable = DomainFixtures.technicianUser(id: UserID("tech-free"), fullName: "Free Tech")
        let orders = [
            DomainFixtures.workOrder(
                assignedTechnicianId: techBusy.id,
                customerId: customer.id,
                status: .enRoute
            )
        ]

        let sorted = TechnicianAssignmentSupport.sortedTechniciansForAssignment(
            [techBusy, techAvailable],
            orders: orders
        )
        XCTAssertEqual(sorted.first?.id, techAvailable.id)
    }

    func testLowerActiveTotalRanksFirstAmongSameStatus() {
        let customer = DomainFixtures.customer()
        let lowLoad = DomainFixtures.technicianUser(id: UserID("tech-low"), fullName: "Low Load")
        let highLoad = DomainFixtures.technicianUser(id: UserID("tech-high"), fullName: "High Load")
        let orders = [
            DomainFixtures.workOrder(
                id: WorkOrderID("wo-1"),
                assignedTechnicianId: highLoad.id,
                customerId: customer.id,
                status: .assigned
            ),
            DomainFixtures.workOrder(
                id: WorkOrderID("wo-2"),
                assignedTechnicianId: highLoad.id,
                customerId: customer.id,
                status: .assigned
            ),
            DomainFixtures.workOrder(
                id: WorkOrderID("wo-3"),
                assignedTechnicianId: lowLoad.id,
                customerId: customer.id,
                status: .assigned
            )
        ]

        let sorted = TechnicianAssignmentSupport.sortedTechniciansForAssignment(
            [highLoad, lowLoad],
            orders: orders
        )
        XCTAssertEqual(sorted.first?.id, lowLoad.id)
    }

    func testLowerUrgentLoadRanksFirstWhenActiveTotalsEqual() {
        let customer = DomainFixtures.customer()
        let fewerUrgent = DomainFixtures.technicianUser(id: UserID("tech-few-urgent"), fullName: "Few Urgent")
        let moreUrgent = DomainFixtures.technicianUser(id: UserID("tech-many-urgent"), fullName: "Many Urgent")
        let orders = [
            DomainFixtures.workOrder(
                id: WorkOrderID("wo-u1"),
                assignedTechnicianId: moreUrgent.id,
                customerId: customer.id,
                priority: .urgent,
                status: .assigned
            ),
            DomainFixtures.workOrder(
                id: WorkOrderID("wo-n1"),
                assignedTechnicianId: moreUrgent.id,
                customerId: customer.id,
                priority: .normal,
                status: .assigned
            ),
            DomainFixtures.workOrder(
                id: WorkOrderID("wo-n2"),
                assignedTechnicianId: fewerUrgent.id,
                customerId: customer.id,
                priority: .normal,
                status: .assigned
            )
        ]

        let sorted = TechnicianAssignmentSupport.sortedTechniciansForAssignment(
            [moreUrgent, fewerUrgent],
            orders: orders
        )
        XCTAssertEqual(sorted.first?.id, fewerUrgent.id)
    }

    func testRecommendationTieBreaksByNameDeterministically() {
        let customer = DomainFixtures.customer()
        let techZ = DomainFixtures.technicianUser(id: UserID("tech-z"), fullName: "Zeynep Arslan")
        let techA = DomainFixtures.technicianUser(id: UserID("tech-a2"), fullName: "Ahmet Yılmaz")

        let sorted = TechnicianAssignmentSupport.sortedTechniciansForAssignment(
            [techZ, techA],
            orders: []
        )
        XCTAssertEqual(sorted.map(\.fullName), ["Ahmet Yılmaz", "Zeynep Arslan"])
    }

    func testRecommendedIDsAreTopThreeOnly() {
        let customer = DomainFixtures.customer()
        let technicians = (0..<5).map { index in
            DomainFixtures.technicianUser(
                id: UserID("tech-rec-\(index)"),
                fullName: "Technician \(index)"
            )
        }
        let orders = [
            DomainFixtures.workOrder(
                assignedTechnicianId: technicians[4].id,
                customerId: customer.id,
                status: .inProgress
            )
        ]

        let recommended = TechnicianAssignmentSupport.recommendedTechnicianIDs(
            from: technicians,
            orders: orders
        )
        XCTAssertEqual(recommended.count, 3)
        XCTAssertFalse(recommended.contains(technicians[4].id))
    }

    func testIsRecommendedUsesGlobalRankingNotSearchSubset() {
        let customer = DomainFixtures.customer()
        let top = DomainFixtures.technicianUser(id: UserID("tech-top"), fullName: "Top Tech")
        let middle = DomainFixtures.technicianUser(id: UserID("tech-middle"), fullName: "Middle Tech")
        let third = DomainFixtures.technicianUser(id: UserID("tech-third"), fullName: "Third Tech")
        let busy = DomainFixtures.technicianUser(id: UserID("tech-busy"), fullName: "Busy Tech")
        let orders = [
            DomainFixtures.workOrder(
                assignedTechnicianId: busy.id,
                customerId: customer.id,
                status: .inProgress
            )
        ]
        let all = [top, middle, third, busy]

        XCTAssertTrue(TechnicianAssignmentSupport.isRecommended(technicianId: top.id, among: all, orders: orders))
        XCTAssertTrue(TechnicianAssignmentSupport.isRecommended(technicianId: middle.id, among: all, orders: orders))
        XCTAssertTrue(TechnicianAssignmentSupport.isRecommended(technicianId: third.id, among: all, orders: orders))
        XCTAssertFalse(TechnicianAssignmentSupport.isRecommended(technicianId: busy.id, among: all, orders: orders))
    }

    func testWorkOrderPriorityOrderingAndCompletedLast() {
        let customer = DomainFixtures.customer()
        let base = DomainFixtures.referenceDate
        let orders = [
            DomainFixtures.workOrder(
                id: WorkOrderID("wo-completed"),
                customerId: customer.id,
                priority: .urgent,
                scheduledDate: base.addingTimeInterval(-7200),
                status: .completed
            ),
            DomainFixtures.workOrder(
                id: WorkOrderID("wo-normal-new"),
                customerId: customer.id,
                priority: .normal,
                scheduledDate: base,
                status: .assigned
            ),
            DomainFixtures.workOrder(
                id: WorkOrderID("wo-urgent-old"),
                customerId: customer.id,
                priority: .urgent,
                scheduledDate: base.addingTimeInterval(-3600),
                status: .assigned
            ),
            DomainFixtures.workOrder(
                id: WorkOrderID("wo-high"),
                customerId: customer.id,
                priority: .high,
                scheduledDate: base.addingTimeInterval(-1800),
                status: .assigned
            )
        ]

        let sorted = WorkOrderListSorting.sortAssignedWorkOrders(orders).map(\.id)
        XCTAssertEqual(sorted, [
            WorkOrderID("wo-urgent-old"),
            WorkOrderID("wo-high"),
            WorkOrderID("wo-normal-new"),
            WorkOrderID("wo-completed")
        ])
    }

    func testPausedResumeActionTitleAndTarget() {
        let action = TechnicianWorkOrderActionMapping.primaryAction(for: .paused)
        XCTAssertEqual(action?.title, "İşe Devam Et")
        XCTAssertEqual(action?.targetStatus, .inProgress)
    }

    func testNonPausedStatusesDoNotExposeResumeAction() {
        XCTAssertNotEqual(TechnicianWorkOrderActionMapping.primaryAction(for: .assigned)?.targetStatus, .inProgress)
        XCTAssertNotEqual(TechnicianWorkOrderActionMapping.primaryAction(for: .inProgress)?.targetStatus, .inProgress)
        XCTAssertNil(TechnicianWorkOrderActionMapping.primaryAction(for: .completed))
    }
}
