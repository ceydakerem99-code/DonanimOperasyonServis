import SwiftUI

struct OperatorAppShellView: View {
    let user: User
    let dependencies: OperatorDependencies
    let onLogout: () -> Void

    @State private var router = OperatorAppRouter(selectedTab: .dashboard)
    @State private var dashboardViewModel: OperatorDashboardViewModel
    @State private var workOrderListViewModel: OperatorWorkOrderListViewModel
    @State private var notificationListViewModel: OperatorNotificationListViewModel

    init(user: User, dependencies: OperatorDependencies, onLogout: @escaping () -> Void) {
        self.user = user
        self.dependencies = dependencies
        self.onLogout = onLogout
        _dashboardViewModel = State(initialValue: OperatorDashboardViewModel(actor: user, dependencies: dependencies))
        _workOrderListViewModel = State(initialValue: OperatorWorkOrderListViewModel(actor: user, dependencies: dependencies))
        _notificationListViewModel = State(initialValue: OperatorNotificationListViewModel(actor: user, dependencies: dependencies))
    }

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
                destinationView(for: destination)
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
            OperatorDashboardView(
                viewModel: dashboardViewModel,
                onSelectWorkOrder: { router.push(.workOrderDetail($0)) },
                onShowAllUrgent: { router.selectedTab = .workOrders }
            )

        case .workOrders:
            OperatorWorkOrderListView(
                viewModel: workOrderListViewModel,
                onSelectWorkOrder: { router.push(.workOrderDetail($0)) },
                onShowEditRequests: { router.push(.editRequests) }
            )

        case .notifications:
            OperatorNotificationListView(viewModel: notificationListViewModel)

        case .profile:
            OperatorProfileView(user: user, onLogout: onLogout)
        }
    }

    @ViewBuilder
    private func destinationView(for destination: OperatorDestination) -> some View {
        switch destination {
        case .workOrderDetail(let id):
            OperatorWorkOrderDetailView(
                viewModel: OperatorWorkOrderDetailViewModel(
                    workOrderId: id,
                    actor: user,
                    dependencies: dependencies
                ),
                onShowReport: { router.push(.report($0)) },
                onShowEditRequests: { router.push(.editRequests) }
            )

        case .newWorkOrderWizard:
            NewWorkOrderWizardView(
                viewModel: NewWorkOrderWizardViewModel(actor: user, dependencies: dependencies),
                onFinished: { id in
                    router.popToRoot()
                    router.selectedTab = .workOrders
                    Task { await workOrderListViewModel.load() }
                    Task { await dashboardViewModel.load() }
                    router.push(.workOrderDetail(id))
                },
                onCancel: { router.popToRoot() }
            )

        case .editRequests:
            OperatorEditRequestListView(
                viewModel: OperatorEditRequestListViewModel(actor: user, dependencies: dependencies),
                onSelect: { router.push(.editRequestDetail($0)) }
            )

        case .editRequestDetail(let id):
            OperatorEditRequestDetailView(
                viewModel: OperatorEditRequestDetailViewModel(
                    requestId: id,
                    actor: user,
                    dependencies: dependencies
                )
            )

        case .report(let id):
            OperatorWorkOrderReportView(
                workOrderId: id,
                dependencies: dependencies,
                actor: user
            )
        }
    }
}

#if DEBUG
#Preview("Operator AppShell") {
    OperatorAppShellView(
        user: OperatorPreviewData.operatorUser,
        dependencies: DIContainer.mock().makeOperatorDependencies(),
        onLogout: {}
    )
}
#endif
