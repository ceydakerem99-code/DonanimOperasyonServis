import XCTest
import UIKit
@testable import DonanimOperasyonServis

/// Regression: `@MainActor Color.dynamic` previously trapped on
/// `com.apple.SwiftUI.AsyncRenderer` when resolving trait colors
/// during tab switches (`_dispatch_assert_queue_fail`).
final class AppColorConcurrencyTests: XCTestCase {

    func testDynamicColorsResolveOffMainActorWithoutTrap() async throws {
        let styles: [UIUserInterfaceStyle] = [.light, .dark]
        try await withThrowingTaskGroup(of: Void.self) { group in
            for style in styles {
                group.addTask {
                    let traits = UITraitCollection(userInterfaceStyle: style)
                    let colors: [UIColor] = [
                        UIColor(AppColor.brandPrimary),
                        UIColor(AppColor.neutralBackground),
                        UIColor(AppColor.elevatedSurface),
                        UIColor(AppColor.primaryText),
                        UIColor(AppColor.secondaryText),
                        UIColor(AppColor.divider),
                        UIColor(AppColor.statusInProgress),
                        UIColor(AppColor.priorityUrgent),
                        UIColor(AppColor.statusUrgent),
                        UIColor(AppColor.statusOverdue),
                        UIColor(AppColor.statusPaused),
                        UIColor(AppColor.statusAvailable),
                        UIColor(AppColor.statusBusy),
                        UIColor(AppColor.priorityNormalAccent),
                        UIColor(AppColor.priorityHighAccent),
                        UIColor(AppColor.timeToday),
                        UIColor(AppColor.timeApproaching),
                        UIColor(AppColor.timeDelayed),
                        UIColor(AppColor.timeWindowPassed),
                        UIColor(AppColor.timeScheduled),
                        UIColor(AppColor.semanticPrimarySurface)
                    ]
                    for color in colors {
                        let resolved = color.resolvedColor(with: traits)
                        var red: CGFloat = 0
                        var green: CGFloat = 0
                        var blue: CGFloat = 0
                        var alpha: CGFloat = 0
                        XCTAssertTrue(
                            resolved.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
                        )
                    }
                }
            }
            try await group.waitForAll()
        }
    }

    func testStatusAndPriorityAccentColorsAreSendableOffMainActor() async {
        await Task.detached {
            _ = AppStatus.inProgress.accentColor
            _ = AppPriority.urgent.accentColor
            _ = AppColor.brandPrimary
        }.value
    }
}
