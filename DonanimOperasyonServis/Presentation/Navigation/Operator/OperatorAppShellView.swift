import SwiftUI

struct OperatorAppShellView: View {
    let user: User
    let onLogout: () -> Void
    @State private var router = OperatorAppRouter(selectedTab: .dashboard)

    var body: some View {
        AppShellLayout(
            headerTitle: UserRole.operator.displayName,
            userName: user.fullName,
            tabs: OperatorNavigationConfiguration.tabItems(),
            selectedTab: $router.selectedTab,
            path: $router.path,
            centerAction: CustomTabBarCenterAction(
                systemImage: "plus",
                accessibilityLabel: "Yeni İş Emri",
                action: { router.push(.newWorkOrderWizard) }
            ),
            root: { tab in
                operatorRoot(for: tab)
            },
            destination: { destination in
                NavigationPlaceholderView(
                    title: destination.title,
                    subtitle: OperatorNavigationConfiguration.destinationSubtitle(for: destination),
                    detail: "Gerçek ekran Faz 9'da."
                )
            }
        )
        .onChange(of: router.selectedTab) { _, _ in
            router.popToRoot()
        }
    }

    @ViewBuilder
    private func operatorRoot(for tab: OperatorTab) -> some View {
        switch tab {
        case .dashboard:
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
        tab: OperatorTab,
        sampleDestination: OperatorDestination?,
        showsLogout: Bool
    ) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.l) {
                NavigationPlaceholderView(
                    title: tab.title,
                    subtitle: OperatorNavigationConfiguration.rootSubtitle(for: tab)
                )

                if tab == .workOrders {
                    SecondaryButton(
                        title: "Düzenleme Talepleri",
                        systemImage: "doc.text.magnifyingglass"
                    ) {
                        router.push(.editRequests)
                    }
                }

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
#Preview("Operator AppShell") {
    OperatorAppShellView(
        user: User(
            id: UserID("operator-preview"),
            email: "operator@example.com",
            fullName: "Operasyon Önizleme",
            role: .operator,
            createdAt: Date(),
            updatedAt: Date()
        ),
        onLogout: {}
    )
}
#endif
