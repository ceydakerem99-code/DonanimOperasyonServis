import SwiftUI

struct TechnicianAppShellView: View {
    let user: User
    let dependencies: TechnicianDependencies
    var syncProgressStore: SyncProgressStore?
    let onLogout: () -> Void
    @Environment(\.diContainer) private var container
    @Environment(\.scenePhase) private var scenePhase

    @State private var router = TechnicianAppRouter(selectedTab: .home)
    @State private var homeViewModel: TechnicianHomeViewModel
    @State private var workOrderListViewModel: TechnicianWorkOrderListViewModel
    @State private var notificationListViewModel: TechnicianNotificationListViewModel
    @State private var workOrderDetailCache: TechnicianWorkOrderDetailViewModelCache

    init(
        user: User,
        dependencies: TechnicianDependencies,
        syncProgressStore: SyncProgressStore? = nil,
        onLogout: @escaping () -> Void
    ) {
        self.user = user
        self.dependencies = dependencies
        self.syncProgressStore = syncProgressStore
        self.onLogout = onLogout
        let locationSampler: LocationSampling = {
            #if DEBUG
            DebugLocationSettings.makeSampler()
            #else
            CoreLocationSampler()
            #endif
        }()
        _homeViewModel = State(initialValue: TechnicianHomeViewModel(actor: user, dependencies: dependencies))
        _workOrderListViewModel = State(initialValue: TechnicianWorkOrderListViewModel(actor: user, dependencies: dependencies))
        _notificationListViewModel = State(initialValue: TechnicianNotificationListViewModel(actor: user, dependencies: dependencies))
        _workOrderDetailCache = State(initialValue: TechnicianWorkOrderDetailViewModelCache(
            actor: user,
            dependencies: dependencies,
            locationSampler: locationSampler
        ))
    }

    var body: some View {
        AppShellLayout(
            headerTitle: UserRole.technician.displayName,
            userName: user.fullName,
            tabs: TechnicianNavigationConfiguration.tabItems(
                showsNotificationsUnreadIndicator: notificationListViewModel.unreadCount > 0
            ),
            selectedTab: $router.selectedTab,
            path: $router.path,
            syncProgressStore: syncProgressStore ?? container.syncProgressStore,
            root: { tab in
                technicianRoot(for: tab)
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
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task {
                await homeViewModel.refreshFromRemoteDirectory()
                await workOrderListViewModel.refreshFromRemoteDirectory()
                await notificationListViewModel.refreshFromRemoteDirectory()
            }
        }
        .onChange(of: syncProgressStore?.isSyncing) { wasSyncing, isSyncing in
            guard wasSyncing == true, isSyncing == false else { return }
            Task {
                await homeViewModel.refreshFromRemoteDirectory()
                await workOrderListViewModel.refreshFromRemoteDirectory()
                await notificationListViewModel.refreshFromRemoteDirectory()
            }
        }
    }

    @ViewBuilder
    private func technicianRoot(for tab: TechnicianTab) -> some View {
        switch tab {
        case .home:
            TechnicianHomeView(
                viewModel: homeViewModel,
                onSelectWorkOrder: { router.push(.workOrderDetail($0)) },
                onShowWorkOrders: { router.selectedTab = .workOrders }
            )
        case .workOrders:
            TechnicianWorkOrderListView(
                viewModel: workOrderListViewModel,
                onSelectWorkOrder: { router.push(.workOrderDetail($0)) }
            )
        case .notifications:
            TechnicianNotificationListView(
                viewModel: notificationListViewModel,
                onOpenWorkOrder: { router.push(.workOrderDetail($0)) }
            )
        case .profile:
            technicianProfileView()
        }
    }

    private func technicianProfileView() -> some View {
        #if DEBUG
        TechnicianProfileView(
            user: user,
            accountService: dependencies.profileAccountService,
            onShowNotificationSettings: { router.push(.notificationSettings) },
            onShowChangePassword: { router.push(.changePassword) },
            onShowDebugTools: { router.push(.debugDeveloperTools) },
            onLogout: onLogout
        )
        #else
        TechnicianProfileView(
            user: user,
            accountService: dependencies.profileAccountService,
            onShowNotificationSettings: { router.push(.notificationSettings) },
            onShowChangePassword: { router.push(.changePassword) },
            onLogout: onLogout
        )
        #endif
    }

    @ViewBuilder
    private func destinationView(for destination: TechnicianDestination) -> some View {
        switch destination {
        case .workOrderDetail(let id):
            TechnicianWorkOrderDetailView(
                viewModel: workOrderDetailCache.viewModel(for: id),
                onShowReport: { router.push(.serviceReport($0)) }
            )
        case .serviceReport(let id):
            TechnicianServiceReportView(
                workOrderId: id,
                dependencies: dependencies,
                actor: user
            )

        case .notificationSettings:
            NotificationSettingsView(
                viewModel: NotificationSettingsViewModel(
                    actor: user,
                    accountService: dependencies.profileAccountService
                )
            )

        case .changePassword:
            ChangePasswordView(
                viewModel: ChangePasswordViewModel(
                    accountService: dependencies.profileAccountService
                )
            )

        case .customerSatisfactionSurvey(let id):
            CustomerSatisfactionFormView(satisfactionId: id)

        #if DEBUG
        case .debugDeveloperTools:
            DebugDeveloperToolsView(
                onOpenCustomerSatisfactionSurvey: { router.push(.customerSatisfactionSurvey($0)) }
            )
        #endif
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
