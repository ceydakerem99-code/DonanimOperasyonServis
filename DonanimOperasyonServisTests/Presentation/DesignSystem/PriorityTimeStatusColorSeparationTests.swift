import XCTest
import SwiftUI
@testable import DonanimOperasyonServis

/// Ensures priority and time-status use separate semantic color tokens.
final class PriorityTimeStatusColorSeparationTests: XCTestCase {

    func testPriorityAccentUsesPriorityTokensOnly() {
        XCTAssertEqual(AppPriority.normal.accentColor, AppColor.priorityNormalAccent)
        XCTAssertEqual(AppPriority.high.accentColor, AppColor.priorityHighAccent)
        XCTAssertEqual(AppPriority.urgent.accentColor, AppColor.priorityUrgentAccent)
    }

    func testTimeStatusAccentUsesTimeTokensOnly() {
        XCTAssertEqual(WorkOrderTimeStatus.today.accentColor, AppColor.timeToday)
        XCTAssertEqual(WorkOrderTimeStatus.approaching.accentColor, AppColor.timeApproaching)
        XCTAssertEqual(WorkOrderTimeStatus.delayed.accentColor, AppColor.timeDelayed)
        XCTAssertEqual(WorkOrderTimeStatus.windowPassed.accentColor, AppColor.timeWindowPassed)
        XCTAssertEqual(WorkOrderTimeStatus.scheduled.accentColor, AppColor.timeScheduled)
    }

    func testUrgentPriorityAndDelayedTimeStatusUseDifferentAccents() {
        let cardRole = WorkOrderCardData(
            id: "1",
            workOrderNumber: "WO-1",
            customerName: "Test",
            workTypeLabel: "Arıza",
            deviceLabel: nil,
            status: .inProgress,
            priority: .urgent,
            timeStatus: .delayed,
            plannedDateLabel: "01.01.2026",
            plannedTimeLabel: nil,
            technicianName: nil
        ).priorityAccentRole

        XCTAssertEqual(AppPriority.urgent.accentColor, AppColor.priorityUrgentAccent)
        XCTAssertEqual(WorkOrderTimeStatus.delayed.accentColor, AppColor.timeDelayed)
        XCTAssertNotEqual(AppPriority.urgent.accentColor, WorkOrderTimeStatus.delayed.accentColor)
        XCTAssertEqual(cardRole, .urgent)
        XCTAssertNotEqual(cardRole.accentColor, WorkOrderTimeStatus.delayed.accentColor)
    }

    func testNormalPriorityAndTodayTimeStatusBothBlueButSeparateTokens() {
        XCTAssertEqual(AppPriority.normal.accentColor, AppColor.priorityNormalAccent)
        XCTAssertEqual(WorkOrderTimeStatus.today.accentColor, AppColor.timeToday)
        XCTAssertEqual(AppColor.priorityNormalAccent, AppColor.timeToday)
        XCTAssertNotEqual(AppColor.priorityNormalAccent as AnyHashable, AppColor.timeDelayed as AnyHashable)
    }

    func testCardAccentRoleFollowsPriorityNotTimeStatus() {
        let urgentDelayed = sampleCard(priority: .urgent, timeStatus: .delayed)
        XCTAssertEqual(urgentDelayed.priorityAccentRole, .urgent)

        let normalToday = sampleCard(priority: .normal, timeStatus: .today)
        XCTAssertEqual(normalToday.priorityAccentRole, .primary)

        let highApproaching = sampleCard(priority: .high, timeStatus: .approaching)
        XCTAssertEqual(highApproaching.priorityAccentRole, .priorityHigh)
    }

    func testSemanticRolesUseNeutralSurfaceForAllCases() {
        for role in AppSemanticRole.allCases {
            XCTAssertEqual(role.surfaceColor, AppColor.elevatedSurface)
        }
    }

    private func sampleCard(
        priority: AppPriority,
        timeStatus: WorkOrderTimeStatus
    ) -> WorkOrderCardData {
        WorkOrderCardData(
            id: "x",
            workOrderNumber: "WO-x",
            customerName: "Test",
            workTypeLabel: "Test",
            deviceLabel: nil,
            status: .assigned,
            priority: priority,
            timeStatus: timeStatus,
            plannedDateLabel: "01.01.2026",
            plannedTimeLabel: nil,
            technicianName: nil
        )
    }
}
