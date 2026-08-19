import SwiftUI

struct AdminAppShellView: View {
    let user: User
    let dependencies: AdminDependencies
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
                destinationView(for: destination)
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
            AdminDashboardView(
                viewModel: AdminDashboardViewModel(actor: user, dependencies: dependencies)
            )

        case .users:
            AdminUserListView(
                viewModel: AdminUserListViewModel(actor: user, dependencies: dependencies),
                onSelectUser: { router.push(.userDetail($0)) }
            )

        case .roles:
            AdminRoleListView(
                viewModel: AdminRoleListViewModel(actor: user, dependencies: dependencies),
                onSelectRole: { router.push(.roleDetail($0)) }
            )

        case .system:
            AdminSystemView(
                viewModel: AdminSystemViewModel(actor: user, dependencies: dependencies),
                onShowWorkTypes: { router.push(.workTypes) },
                onShowPauseReasons: { router.push(.pauseReasons) },
                onShowConflicts: { router.push(.conflicts) },
                onLogout: onLogout
            )

        case .reports:
            AdminReportsView(
                onSelectReport: { router.push(.reportDetail($0)) }
            )
        }
    }

    @ViewBuilder
    private func destinationView(for destination: AdminDestination) -> some View {
        switch destination {
        case .userDetail(let id):
            AdminUserDetailView(
                viewModel: AdminUserDetailViewModel(
                    userId: id,
                    actor: user,
                    dependencies: dependencies
                )
            )

        case .roleDetail(let role):
            AdminRoleDetailView(role: role)

        case .workTypes:
            AdminWorkTypesView()

        case .pauseReasons:
            AdminPauseReasonsView()

        case .reportDetail(let kind):
            AdminReportDetailView(
                viewModel: AdminReportDetailViewModel(
                    kind: kind,
                    actor: user,
                    dependencies: dependencies
                ),
                onSelectWorkOrder: { router.push(.workOrderReport($0)) }
            )

        case .workOrderReport(let id):
            AdminWorkOrderReportView(
                viewModel: AdminWorkOrderReportViewModel(
                    workOrderId: id,
                    actor: user,
                    dependencies: dependencies
                )
            )

        case .conflicts:
            AdminConflictListView(
                viewModel: AdminConflictListViewModel(
                    actor: user,
                    dependencies: dependencies
                )
            )
        }
    }
}

#if DEBUG
#Preview("Admin AppShell") {
    AdminAppShellView(
        user: AdminPreviewData.adminUser,
        dependencies: DIContainer.mock().makeAdminDependencies(),
        onLogout: {}
    )
}
#endif
