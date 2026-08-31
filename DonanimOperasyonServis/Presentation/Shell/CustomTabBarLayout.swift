import CoreGraphics
import SwiftUI

/// Layout metrics for ``CustomTabBar`` used by the app shell and tab-root scroll
/// content. Values derive from ``AppSpacing`` — no ad-hoc pixel literals.
enum CustomTabBarLayout {

    /// Vertical space reserved for the center FAB protruding above the tab row.
    static let centerFABProtrusion: CGFloat = AppSpacing.m

    /// Small breathing room between scroll content and the tab bar band.
    static let scrollContentSpacing: CGFloat = AppSpacing.s

    /// Estimated height when runtime measurement is unavailable (previews/tests).
    static func estimatedReservedHeight(hasCenterFAB: Bool) -> CGFloat {
        tabRowHeight + (hasCenterFAB ? centerFABProtrusion : 0)
    }

    /// Scroll bottom margin: measured/estimated tab bar band + breathing room.
    static func scrollContentBottomMargin(occupiedHeight: CGFloat) -> CGFloat {
        guard occupiedHeight > 0 else { return 0 }
        return occupiedHeight + scrollContentSpacing
    }

    /// Tab row: top padding + touch target row + bottom padding.
    private static var tabRowHeight: CGFloat {
        AppSpacing.s + AppSpacing.minimumTouchTarget + AppSpacing.m
    }
}

/// Runtime measurement published by ``CustomTabBar`` for scroll clearance.
enum TabBarHeightPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct AppShellTabBarOccupiedHeightKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

extension EnvironmentValues {
    /// Height of the bottom tab bar band when visible; `0` when hidden.
    var appShellTabBarOccupiedHeight: CGFloat {
        get { self[AppShellTabBarOccupiedHeightKey.self] }
        set { self[AppShellTabBarOccupiedHeightKey.self] = newValue }
    }
}
