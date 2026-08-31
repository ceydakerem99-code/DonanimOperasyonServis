import SwiftUI

/// A single tab entry described by a stable `Tab` identity, the label
/// shown under the icon, and the SF Symbol drawn above the label.
struct CustomTabBarItem<Tab: Hashable>: Identifiable {
    let tab: Tab
    let title: String
    let systemImage: String
    var showsUnreadIndicator: Bool = false

    var id: Tab { tab }
}

/// Optional center floating action button rendered by ``CustomTabBar``.
struct CustomTabBarCenterAction {
    let systemImage: String
    let accessibilityLabel: String
    let action: () -> Void
}

/// Corporate-style bottom tab bar with optional center floating action.
///
/// The role-specific tabs (Admin / Operator / Technician) are provided
/// by the caller in later phases. Operator uses `centerAction` to open
/// the New Work Order wizard from the middle of the bar.
///
/// This component has zero navigation knowledge; it only manages
/// visual state and forwards taps via the `selection` binding and the
/// optional center-action closure.
struct CustomTabBar<Tab: Hashable>: View {
    let items: [CustomTabBarItem<Tab>]
    @Binding var selection: Tab
    var centerAction: CustomTabBarCenterAction?

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            if centerAction != nil, items.count >= 2 {
                let leftCount = (items.count + 1) / 2
                HStack(spacing: 0) {
                    ForEach(Array(items.prefix(leftCount)), id: \.tab) { item in
                        tabButton(for: item)
                    }
                }
                .frame(maxWidth: .infinity)

                centerButton

                HStack(spacing: 0) {
                    ForEach(Array(items.suffix(items.count - leftCount)), id: \.tab) { item in
                        tabButton(for: item)
                    }
                }
                .frame(maxWidth: .infinity)
            } else {
                ForEach(items) { item in
                    tabButton(for: item)
                }
            }
        }
        .padding(.top, centerAction != nil ? CustomTabBarLayout.centerFABProtrusion : AppSpacing.s)
        .padding(.horizontal, AppSpacing.m)
        .padding(.bottom, AppSpacing.m)
        .background(
            AppColor.elevatedSurface
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(AppColor.divider)
                        .frame(height: 0.5)
                }
        )
        .background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: TabBarHeightPreferenceKey.self,
                    value: proxy.size.height
                )
            }
        }
    }

    @ViewBuilder private var centerButton: some View {
        if let centerAction {
            Button {
                centerAction.action()
            } label: {
                Image(systemName: centerAction.systemImage)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(AppColor.onPrimary)
                    .frame(width: 56, height: 56)
                    .background(
                        Circle()
                            .fill(AppColor.brandPrimary)
                            .shadow(color: AppColor.brandPrimary.opacity(0.35),
                                    radius: 8, x: 0, y: 4)
                    )
                    .offset(y: -AppSpacing.m)
            }
            .buttonStyle(.plain)
            .frame(width: 64)
            .accessibilityLabel(Text(centerAction.accessibilityLabel))
        }
    }

    private func tabButton(for item: CustomTabBarItem<Tab>) -> some View {
        let isSelected = item.tab == selection
        return Button {
            #if DEBUG
            AppLogger.navigation.info(
                "NAV tabTap tab=\(String(describing: item.tab), privacy: .public) wasSelected=\(isSelected, privacy: .public)"
            )
            #endif
            selection = item.tab
        } label: {
            VStack(spacing: AppSpacing.xs) {
                ZStack(alignment: .top) {
                    Image(systemName: item.systemImage)
                        .font(.system(size: 20, weight: .regular))
                    if item.showsUnreadIndicator {
                        Circle()
                            .fill(AppColor.brandPrimary)
                            .frame(width: 8, height: 8)
                            .offset(x:11, y: -5)
                    }
                }
                Text(item.title)
                    .font(AppFont.label)
            }
            .foregroundStyle(isSelected ? AppColor.brandPrimary : AppColor.secondaryText)
            .frame(maxWidth: .infinity)
            .frame(minHeight: AppSpacing.minimumTouchTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(item.title))
        .accessibilityValue(
            Text(item.showsUnreadIndicator ? "Okunmamış bildirim var" : "")
        )
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

#if DEBUG
private struct CustomTabBarPreview: View {
    @State private var operatorTab = "dashboard"
    @State private var techTab = "home"

    var body: some View {
        VStack(spacing: AppSpacing.xxl) {
            VStack(alignment: .leading, spacing: AppSpacing.s) {
                Text("Operasyon Yetkilisi (merkez FAB'lı)")
                    .font(AppFont.subtitle)
                    .foregroundStyle(AppColor.primaryText)
                CustomTabBar<String>(
                    items: [
                        .init(tab: "dashboard", title: "Dashboard", systemImage: "square.grid.2x2"),
                        .init(tab: "orders", title: "İş Emirleri", systemImage: "list.bullet.rectangle"),
                        .init(tab: "notifications", title: "Bildirimler", systemImage: "bell", showsUnreadIndicator: true),
                        .init(tab: "profile", title: "Profil", systemImage: "person.crop.circle")
                    ],
                    selection: $operatorTab,
                    centerAction: .init(
                        systemImage: "plus",
                        accessibilityLabel: "Yeni İş Emri",
                        action: {}
                    )
                )
            }

            VStack(alignment: .leading, spacing: AppSpacing.s) {
                Text("Teknisyen (merkez FAB'sız)")
                    .font(AppFont.subtitle)
                    .foregroundStyle(AppColor.primaryText)
                CustomTabBar<String>(
                    items: [
                        .init(tab: "home", title: "Ana Sayfa", systemImage: "house"),
                        .init(tab: "orders", title: "İş Emirleri", systemImage: "list.bullet.rectangle"),
                        .init(tab: "notifications", title: "Bildirimler", systemImage: "bell"),
                        .init(tab: "profile", title: "Profil", systemImage: "person.crop.circle")
                    ],
                    selection: $techTab
                )
            }
        }
        .padding(.horizontal, AppSpacing.l)
        .padding(.vertical, AppSpacing.xl)
        .background(AppColor.neutralBackground)
    }
}

#Preview("CustomTabBar") {
    CustomTabBarPreview()
}
#endif
