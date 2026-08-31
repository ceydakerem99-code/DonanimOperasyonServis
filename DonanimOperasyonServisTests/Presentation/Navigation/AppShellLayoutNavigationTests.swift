import XCTest
@testable import DonanimOperasyonServis

/// Regression tests for shared shell navigation: profile/debug/conflict
/// flows must use router `$path` so tab bar stays interactive after pop.
@MainActor
final class AppShellLayoutNavigationTests: XCTestCase {

    func testProfileDebugFlowUsesRouterPathNotInnerNavigationLink() {
        let router = OperatorAppRouter(selectedTab: .profile)
        XCTAssertTrue(router.path.isEmpty)

        #if DEBUG
        router.push(.debugDeveloperTools)
        XCTAssertEqual(router.path, [.debugDeveloperTools])
        XCTAssertFalse(router.path.isEmpty, "Debug screen must hide tab bar via non-empty path")

        router.popToRoot()
        XCTAssertTrue(router.path.isEmpty, "Back from debug must restore tab bar path")
        #endif

        router.selectedTab = .dashboard
        router.popToRoot()
        XCTAssertEqual(router.selectedTab, .dashboard)
        XCTAssertTrue(router.path.isEmpty)
    }

    func testBottomNavigationRemainsInteractiveAfterConflictScreen() {
        let router = OperatorAppRouter(selectedTab: .profile)
        router.push(.conflicts)
        XCTAssertFalse(router.path.isEmpty)

        router.popToRoot()
        XCTAssertTrue(router.path.isEmpty)

        router.selectedTab = .dashboard
        router.popToRoot()

        XCTAssertEqual(router.selectedTab, .dashboard)
        XCTAssertTrue(router.path.isEmpty)
    }

    func testCenterActionPushAndCancelRestoresTabBarPath() {
        let router = OperatorAppRouter(selectedTab: .dashboard)
        router.push(.newWorkOrderWizard)
        XCTAssertEqual(router.path, [.newWorkOrderWizard])

        router.popToRoot()
        XCTAssertTrue(router.path.isEmpty)
    }

    func testTabChangePopToRootClearsShellDestinations() {
        let router = OperatorAppRouter(selectedTab: .profile)
        router.push(.conflicts)
        router.push(.conflictDetail(SyncConflictID("conflict-1")))
        XCTAssertEqual(router.path.count, 2)

        router.selectedTab = .dashboard
        router.popToRoot()

        XCTAssertEqual(router.selectedTab, .dashboard)
        XCTAssertTrue(router.path.isEmpty)
    }

    func testProfileSettingsRoutesUseSharedNavigationPath() {
        let router = OperatorAppRouter(selectedTab: .profile)
        router.push(.notificationSettings)
        router.push(.changePassword)
        XCTAssertEqual(
            router.path,
            [.notificationSettings, .changePassword]
        )

        router.popToRoot()
        router.selectedTab = .workOrders
        XCTAssertEqual(router.selectedTab, .workOrders)
        XCTAssertTrue(router.path.isEmpty)
    }

    func testTabIdentityChangesWhenSelectingDifferentTab() {
        let profileTab = OperatorTab.profile
        let dashboardTab = OperatorTab.dashboard
        XCTAssertNotEqual(profileTab, dashboardTab)
    }

    func testProfileLogoutRemainsAboveBottomTabBar() {
        let operatorReserved = CustomTabBarLayout.estimatedReservedHeight(hasCenterFAB: true)
        let technicianReserved = CustomTabBarLayout.estimatedReservedHeight(hasCenterFAB: false)

        XCTAssertGreaterThan(
            operatorReserved,
            technicianReserved,
            "Operator FAB tab bar must reserve more vertical space than technician"
        )

        let operatorScrollMargin = CustomTabBarLayout.scrollContentBottomMargin(
            occupiedHeight: operatorReserved
        )
        let technicianScrollMargin = CustomTabBarLayout.scrollContentBottomMargin(
            occupiedHeight: technicianReserved
        )

        XCTAssertGreaterThan(
            operatorScrollMargin,
            AppSpacing.minimumTouchTarget,
            "Profile logout scroll margin must clear tab bar touch target (operator)"
        )
        XCTAssertGreaterThan(
            technicianScrollMargin,
            AppSpacing.minimumTouchTarget,
            "Profile logout scroll margin must clear tab bar touch target (technician)"
        )
        XCTAssertEqual(
            CustomTabBarLayout.scrollContentBottomMargin(occupiedHeight: 0),
            0,
            "Hidden tab bar must not add scroll bottom margin"
        )

        let router = OperatorAppRouter(selectedTab: .profile)
        XCTAssertTrue(router.path.isEmpty, "Profile tab root keeps tab bar visible for scroll inset")
    }
}
