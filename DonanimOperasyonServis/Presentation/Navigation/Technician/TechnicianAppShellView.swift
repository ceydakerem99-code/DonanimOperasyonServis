import SwiftUI

struct TechnicianAppShellView: View {
    let user: User
    let onLogout: () -> Void
    @State private var router = TechnicianAppRouter(selectedTab: .home)

    var body: some View {
        AppShellLayout(
            headerTitle: UserRole.technician.displayName,
            userName: user.fullName,
            tabs: TechnicianNavigationConfiguration.tabItems(),
            selectedTab: $router.selectedTab,
            path: $router.path,
            root: { tab in
                technicianRoot(for: tab)
            },
            destination: { destination in
                NavigationPlaceholderView(
                    title: destination.title,
                    subtitle: TechnicianNavigationConfiguration.destinationSubtitle(for: destination),
                    detail: "Gerçek ekran Faz 8'de."
                )
            }
        )
        .onChange(of: router.selectedTab) { _, _ in
            router.popToRoot()
        }
    }

    @ViewBuilder
    private func technicianRoot(for tab: TechnicianTab) -> some View {
        switch tab {
        case .home:
            tabRoot(tab: tab, sampleDestination: nil, showsLogout: false)
        case .workOrders:
            tabRoot(tab: tab, sampleDestination: .workOrderDetail, showsLogout: false)
        case .notifications:
            tabRoot(tab: tab, sampleDestination: nil, showsLogout: false)
        case .profile:
            tabRoot(tab: tab, sampleDestination: nil, showsLogout: true)
        }
    }

    @ViewBuilder
    private func tabRoot(
        tab: TechnicianTab,
        sampleDestination: TechnicianDestination?,
        showsLogout: Bool
    ) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.l) {
                NavigationPlaceholderView(
                    title: tab.title,
                    subtitle: TechnicianNavigationConfiguration.rootSubtitle(for: tab)
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
#Preview("Technician AppShell") {
    TechnicianAppShellView(
        user: User(
            id: UserID("technician-preview"),
            email: "tech@example.com",
            fullName: "Teknisyen Önizleme",
            role: .technician,
            createdAt: Date(),
            updatedAt: Date()
        ),
        onLogout: {}
    )
}
#endif
