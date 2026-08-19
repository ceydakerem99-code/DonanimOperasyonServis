import SwiftUI

struct TechnicianAppShellView: View {
    let user: User
    let dependencies: TechnicianDependencies
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
                destinationView(for: destination)
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
            TechnicianHomeView(
                viewModel: TechnicianHomeViewModel(actor: user, dependencies: dependencies),
                onSelectWorkOrder: { router.push(.workOrderDetail($0)) },
                onShowWorkOrders: { router.selectedTab = .workOrders }
            )
        case .workOrders:
            TechnicianWorkOrderListView(
                viewModel: TechnicianWorkOrderListViewModel(actor: user, dependencies: dependencies),
                onSelectWorkOrder: { router.push(.workOrderDetail($0)) }
            )
        case .notifications:
            TechnicianNotificationListView(
                viewModel: TechnicianNotificationListViewModel(actor: user, dependencies: dependencies)
            )
        case .profile:
            TechnicianProfileView(user: user, onLogout: onLogout)
        }
    }

    @ViewBuilder
    private func destinationView(for destination: TechnicianDestination) -> some View {
        switch destination {
        case .workOrderDetail(let id):
            TechnicianWorkOrderDetailView(
                viewModel: TechnicianWorkOrderDetailViewModel(
                    workOrderId: id,
                    actor: user,
                    dependencies: dependencies
                ),
                onShowReport: { router.push(.serviceReport($0)) }
            )
        case .serviceReport(let id):
            TechnicianServiceReportView(
                workOrderId: id,
                dependencies: dependencies,
                actor: user
            )
        }
    }
}

#if DEBUG
#Preview("Technician AppShell") {
    TechnicianAppShellView(
        user: TechnicianPreviewData.technician,
        dependencies: DIContainer.mock().makeTechnicianDependencies(),
        onLogout: {}
    )
}
#endif
