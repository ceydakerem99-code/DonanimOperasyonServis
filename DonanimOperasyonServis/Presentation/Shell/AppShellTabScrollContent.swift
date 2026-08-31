import SwiftUI

/// Shared scroll container for tab-root screens (Profile, Dashboard, …).
///
/// Bottom clearance above ``CustomTabBar`` uses `contentMargins` driven by
/// ``EnvironmentValues/appShellTabBarOccupiedHeight`` (measured in ``AppShellLayout``).
/// Tab bar placement uses `safeAreaInset` on the tab root; scroll content needs an
/// explicit margin because that inset does not always propagate into `ScrollView`
/// content inside `NavigationStack`.
struct AppShellTabScrollContent<Content: View>: View {

    @Environment(\.appShellTabBarOccupiedHeight) private var tabBarOccupiedHeight

    @ViewBuilder let content: () -> Content

    private var scrollBottomMargin: CGFloat {
        CustomTabBarLayout.scrollContentBottomMargin(occupiedHeight: tabBarOccupiedHeight)
    }

    var body: some View {
        ScrollView {
            content()
                .padding(.horizontal, AppSpacing.l)
                .padding(.bottom, AppSpacing.l)
        }
        .contentMargins(
            .bottom,
            scrollBottomMargin,
            for: .scrollContent
        )
    }
}
