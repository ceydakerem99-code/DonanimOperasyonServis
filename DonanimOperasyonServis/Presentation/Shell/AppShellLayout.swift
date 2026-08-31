import SwiftUI

/// Shared App Shell chrome: header + `NavigationStack` content +
/// `CustomTabBar`. Role-specific tabs/destinations are supplied via
/// generics — there is only one layout implementation.
struct AppShellLayout<Tab: Hashable, Destination: Hashable, Root: View, Dest: View>: View {

    let headerTitle: String
    let userName: String
    let tabs: [CustomTabBarItem<Tab>]
    @Binding var selectedTab: Tab
    @Binding var path: [Destination]
    var centerAction: CustomTabBarCenterAction?
    var syncProgressStore: SyncProgressStore?
    @ViewBuilder let root: (Tab) -> Root
    @ViewBuilder let destination: (Destination) -> Dest

    @State private var measuredTabBarHeight: CGFloat = 0

    private var tabBarVisible: Bool { path.isEmpty }

    private var tabBarOccupiedHeight: CGFloat {
        if measuredTabBarHeight > 0 {
            return measuredTabBarHeight
        }

        return CustomTabBarLayout.estimatedReservedHeight(
            hasCenterFAB: centerAction != nil
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            AppShellHeader(title: headerTitle, userName: userName, syncStore: syncProgressStore)
            NavigationStack(path: $path) {
                root(selectedTab)
                    .id(selectedTab)
                    // Inset on the tab *root* so ScrollView children inherit bottom
                    // safe area / scroll margins. An inset on `NavigationStack` itself
                    // does not propagate into profile ScrollView content.
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        CustomTabBar(
                            items: tabs,
                            selection: $selectedTab,
                            centerAction: centerAction
                        )
                        .background(AppColor.elevatedSurface)
                        .opacity(tabBarVisible ? 1 : 0)
                        .allowsHitTesting(tabBarVisible)
                        .zIndex(1)
                    }
                    .navigationDestination(for: Destination.self) { item in
                        destination(item)
                    }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onPreferenceChange(TabBarHeightPreferenceKey.self) { height in
                measuredTabBarHeight = height
            }
            .environment(\.appShellTabBarOccupiedHeight, tabBarOccupiedHeight)
        }
        .background(AppColor.neutralBackground)
        #if DEBUG
        .onChange(of: selectedTab) { oldValue, newValue in
            AppLogger.navigation.info(
                "NAV tabSelection old=\(String(describing: oldValue), privacy: .public) new=\(String(describing: newValue), privacy: .public) pathCount=\(path.count)"
            )
        }
        .onChange(of: path) { oldValue, newValue in
            AppLogger.navigation.info(
                "NAV pathChange oldCount=\(oldValue.count) newCount=\(newValue.count) tab=\(String(describing: selectedTab), privacy: .public)"
            )
        }
        #endif
    }
}
