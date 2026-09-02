import SwiftUI

struct AdminAppShellView: View {
    let user: User
    let dependencies: AdminDependencies
    let syncProgressStore: SyncProgressStore?
    let onLogout: () -> Void

    @State private var router = AdminAppRouter(selectedTab: .dashboard)
    @State private var dashboardViewModel: AdminDashboardViewModel
    @State private var userListViewModel: AdminUserListViewModel
    @State private var roleListViewModel: AdminRoleListViewModel
    @State private var systemViewModel: AdminSystemViewModel
    @State private var reportDetailCache: AdminReportDetailViewModelCache
    @State private var customerAnalyticsCache: CustomerAnalyticsViewModelCache
    @State private var customerSatisfactionCache: CustomerSatisfactionViewModelCache
    @State private var faultRecurrenceCache: FaultRecurrenceAnalysisViewModelCache
    @State private var dailyOperationsCache: DailyOperationsReportViewModelCache

    init(
        user: User,
        dependencies: AdminDependencies,
        syncProgressStore: SyncProgressStore? = nil,
        onLogout: @escaping () -> Void
    ) {
        self.user = user
        self.dependencies = dependencies
        self.syncProgressStore = syncProgressStore
        self.onLogout = onLogout
        _dashboardViewModel = State(initialValue: AdminDashboardViewModel(actor: user, dependencies: dependencies))
        _userListViewModel = State(initialValue: AdminUserListViewModel(actor: user, dependencies: dependencies))
        _roleListViewModel = State(initialValue: AdminRoleListViewModel(actor: user, dependencies: dependencies))
        _systemViewModel = State(initialValue: AdminSystemViewModel(
            actor: user,
            dependencies: dependencies,
            syncProgressStore: syncProgressStore
        ))
        _reportDetailCache = State(
            initialValue: AdminReportDetailViewModelCache(actor: user, dependencies: dependencies)
        )
        _customerAnalyticsCache = State(
            initialValue: CustomerAnalyticsViewModelCache(actor: user, dependencies: dependencies)
        )
        _customerSatisfactionCache = State(
            initialValue: CustomerSatisfactionViewModelCache(actor: user, dependencies: dependencies)
        )
        _faultRecurrenceCache = State(
            initialValue: FaultRecurrenceAnalysisViewModelCache(actor: user, dependencies: dependencies)
        )
        _dailyOperationsCache = State(
            initialValue: DailyOperationsReportViewModelCache(actor: user, dependencies: dependencies)
        )
    }

    var body: some View {
        AppShellLayout(
            headerTitle: UserRole.admin.displayName,
            userName: user.fullName,
            tabs: AdminNavigationConfiguration.tabItems(),
            selectedTab: $router.selectedTab,
            path: $router.path,
            syncProgressStore: syncProgressStore,
            root: { tab in
                adminRoot(for: tab)
            },
            destination: { destination in
                destinationView(for: destination)
            }
        )
        .onChange(of: router.selectedTab) { _, _ in
            guard !router.path.isEmpty else { return }
            Task { @MainActor in
                router.popToRoot()
            }
        }
    }

    @ViewBuilder
    private func adminRoot(for tab: AdminTab) -> some View {
        switch tab {
        case .dashboard:
            AdminDashboardView(
                viewModel: dashboardViewModel,
                onShowUsers: { role in
                    Task {
                        await userListViewModel.applyRoleFilter(role)
                        router.selectedTab = .users
                    }
                },
                onShowReports: { kind in
                    router.selectedTab = .reports
                    Task { @MainActor in
                        await Task.yield()
                        router.push(.reportDetail(kind))
                    }
                },
                onShowConflicts: {
                    router.selectedTab = .system
                    Task { @MainActor in
                        await Task.yield()
                        router.push(.conflicts)
                    }
                },
                onSelectWorkOrder: { id in
                    router.push(.workOrderReport(id))
                },
                onShowAllCompleted: {
                    router.selectedTab = .reports
                    Task { @MainActor in
                        await Task.yield()
                        router.push(.reportDetail(.workOrders))
                    }
                }
            )

        case .users:
            AdminUserListView(
                viewModel: userListViewModel,
                onSelectUser: { router.push(.userDetail($0)) },
                onCreateUser: { router.push(.createUser) }
            )

        case .roles:
            AdminRoleListView(
                viewModel: roleListViewModel,
                onSelectRole: { router.push(.roleDetail($0)) }
            )

        case .system:
            AdminSystemView(
                viewModel: systemViewModel,
                currentUser: user,
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
        case .createUser:
            AdminCreateUserView(
                viewModel: AdminCreateUserViewModel(
                    actor: user,
                    dependencies: dependencies
                ),
                onCreated: { id in
                    Task {
                        await userListViewModel.load()
                        router.popToRoot()
                        router.push(.userDetail(id))
                    }
                }
            )

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
            if kind == .customerAnalytics {
                CustomerAnalyticsView(
                    viewModel: customerAnalyticsCache.viewModel()
                )
            } else if kind == .customerSatisfaction {
                CustomerSatisfactionView(
                    viewModel: customerSatisfactionCache.viewModel()
                )
            } else if kind == .faultRecurrence {
                FaultRecurrenceAnalysisView(
                    viewModel: faultRecurrenceCache.viewModel(),
                    onSelectWorkOrder: { router.push(.workOrderReport($0)) }
                )
            } else if kind == .dailyOperations {
                DailyOperationsReportView(
                    viewModel: dailyOperationsCache.viewModel(),
                    onSelectWorkOrder: { router.push(.workOrderReport($0)) }
                )
            } else {
                AdminReportDetailView(
                    viewModel: reportDetailCache.viewModel(for: kind),
                    mediaLoader: WorkOrderMediaLoader(storage: dependencies.storageDataSource),
                    onSelectWorkOrder: { router.push(.workOrderReport($0)) }
                )
            }

        case .workOrderReport(let id):
            AdminWorkOrderReportView(
                workOrderId: id,
                actor: user,
                dependencies: dependencies,
                onDeleted: { router.pop() }
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
