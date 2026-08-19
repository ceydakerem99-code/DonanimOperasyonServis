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
    @ViewBuilder let root: (Tab) -> Root
    @ViewBuilder let destination: (Destination) -> Dest

    var body: some View {
        VStack(spacing: 0) {
            AppShellHeader(title: headerTitle, userName: userName)
            NavigationStack(path: $path) {
                root(selectedTab)
                    .navigationDestination(for: Destination.self) { item in
                        destination(item)
                    }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Hide tab bar while a stack destination (wizard/detail) is
            // active so FAB/tab selection cannot fight the pushed flow.
            if path.isEmpty {
                CustomTabBar(
                    items: tabs,
                    selection: $selectedTab,
                    centerAction: centerAction
                )
            }
        }
        .background(AppColor.neutralBackground)
    }
}
