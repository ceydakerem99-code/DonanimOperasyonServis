import SwiftUI

struct AdminAppShellView: View {
    let user: User
    let onLogout: () -> Void
    @State private var router = AdminAppRouter(selectedTab: .dashboard)

    var body: some View {
        AppShellLayout(
            headerTitle: UserRole.admin.displayName,
            userName: user.fullName,
            tabs: AdminNavigationConfiguration.tabItems(),
            selectedTab: $router.selectedTab,
            path: $router.path,
            root: { tab in
                adminRoot(for: tab)
            },
            destination: { destination in
                NavigationPlaceholderView(
                    title: destination.title,
                    subtitle: AdminNavigationConfiguration.destinationSubtitle(for: destination),
                    detail: "Gerçek ekran Faz 11'de."
                )
            }
        )
        .onChange(of: router.selectedTab) { _, _ in
            router.popToRoot()
        }
    }

    @ViewBuilder
    private func adminRoot(for tab: AdminTab) -> some View {
        switch tab {
        case .dashboard:
            tabRoot(
                tab: tab,
                sampleDestination: nil,
                showsLogout: false
            )
        case .users:
            tabRoot(
                tab: tab,
                sampleDestination: .userDetail,
                showsLogout: false
            )
        case .roles:
            tabRoot(
                tab: tab,
                sampleDestination: .roleDetail,
                showsLogout: false
            )
        case .system:
            tabRoot(
                tab: tab,
                sampleDestination: .workTypes,
                showsLogout: false
            )
        case .reports:
            tabRoot(
                tab: tab,
                sampleDestination: .reportDetail,
                showsLogout: false
            )
        }
    }

    @ViewBuilder
    private func tabRoot(
        tab: AdminTab,
        sampleDestination: AdminDestination?,
        showsLogout: Bool
    ) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.l) {
                NavigationPlaceholderView(
                    title: tab.title,
                    subtitle: AdminNavigationConfiguration.rootSubtitle(for: tab)
                )

                if let sampleDestination {
                    SecondaryButton(
                        title: "Örnek Detay",
                        systemImage: "chevron.right"
                    ) {
                        router.push(sampleDestination)
                    }
                }

                if showsLogout {
                    SecondaryButton(
                        title: "Çıkış Yap",
                        systemImage: "rectangle.portrait.and.arrow.right",
                        action: onLogout
                    )
                }
            }
            .padding(.horizontal, AppSpacing.l)
        }
        .navigationTitle(tab.title)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityHint(Text(tab.accessibilityHint))
    }
}

#if DEBUG
#Preview("Admin AppShell") {
    AdminAppShellView(
        user: User(
            id: UserID("admin-preview"),
            email: "admin@example.com",
            fullName: "Admin Önizleme",
            role: .admin,
            createdAt: Date(),
            updatedAt: Date()
        ),
        onLogout: {}
    )
}
#endif
