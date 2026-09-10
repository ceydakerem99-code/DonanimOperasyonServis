import SwiftUI

struct OperatorAppShellView: View {
    let user: User
    let dependencies: OperatorDependencies
    var syncProgressStore: SyncProgressStore?
    let onLogout: () -> Void

    @State private var router = OperatorAppRouter(selectedTab: .dashboard)
    @State private var dashboardViewModel: OperatorDashboardViewModel
    @State private var workOrderListViewModel: OperatorWorkOrderListViewModel
    @State private var notificationListViewModel: OperatorNotificationListViewModel
    @State private var editRequestListViewModel: OperatorEditRequestListViewModel
    @State private var conflictListViewModel: OperatorConflictListViewModel
    @State private var customerListViewModel: OperatorCustomerListViewModel
    @State private var technicianListViewModel: OperatorTechnicianListViewModel
    @State private var workOrderDetailCache: OperatorWorkOrderDetailViewModelCache
    @State private var reportDetailCache: OperatorReportDetailViewModelCache
    @State private var customerAnalyticsCache: OperatorCustomerAnalyticsViewModelCache
    @State private var customerSatisfactionCache: OperatorCustomerSatisfactionViewModelCache
    @State private var faultRecurrenceCache: OperatorFaultRecurrenceAnalysisViewModelCache
    @State private var dailyOperationsCache: OperatorDailyOperationsReportViewModelCache

    init(
        user: User,
        dependencies: OperatorDependencies,
        syncProgressStore: SyncProgressStore? = nil,
        onLogout: @escaping () -> Void
    ) {
        self.user = user
        self.dependencies = dependencies
        self.syncProgressStore = syncProgressStore
        self.onLogout = onLogout
        _dashboardViewModel = State(initialValue: OperatorDashboardViewModel(actor: user, dependencies: dependencies))
        _workOrderListViewModel = State(initialValue: OperatorWorkOrderListViewModel(actor: user, dependencies: dependencies))
        _notificationListViewModel = State(initialValue: OperatorNotificationListViewModel(actor: user, dependencies: dependencies))
        _editRequestListViewModel = State(initialValue: OperatorEditRequestListViewModel(actor: user, dependencies: dependencies))
        _conflictListViewModel = State(initialValue: OperatorConflictListViewModel(actor: user, dependencies: dependencies))
        _customerListViewModel = State(initialValue: OperatorCustomerListViewModel(actor: user, dependencies: dependencies))
        _technicianListViewModel = State(initialValue: OperatorTechnicianListViewModel(actor: user, dependencies: dependencies))
        _workOrderDetailCache = State(initialValue: OperatorWorkOrderDetailViewModelCache(actor: user, dependencies: dependencies))
        _reportDetailCache = State(initialValue: OperatorReportDetailViewModelCache(actor: user, dependencies: dependencies))
        _customerAnalyticsCache = State(initialValue: OperatorCustomerAnalyticsViewModelCache(actor: user, dependencies: dependencies))
        _customerSatisfactionCache = State(initialValue: OperatorCustomerSatisfactionViewModelCache(actor: user, dependencies: dependencies))
        _faultRecurrenceCache = State(initialValue: OperatorFaultRecurrenceAnalysisViewModelCache(actor: user, dependencies: dependencies))
        _dailyOperationsCache = State(initialValue: OperatorDailyOperationsReportViewModelCache(actor: user, dependencies: dependencies))
    }

    var body: some View {
        AppShellLayout(
            headerTitle: UserRole.operator.displayName,
            userName: user.fullName,
            tabs: OperatorNavigationConfiguration.tabItems(
                showsNotificationsUnreadIndicator: notificationListViewModel.unreadCount > 0
            ),
            selectedTab: $router.selectedTab,
            path: $router.path,
            centerAction: CustomTabBarCenterAction(
                systemImage: "plus",
                accessibilityLabel: "Yeni İş Emri",
                action: { router.push(.newWorkOrderWizard) }
            ),
            syncProgressStore: syncProgressStore,
            root: { tab in
                operatorRoot(for: tab)
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
    private func operatorRoot(for tab: OperatorTab) -> some View {
        switch tab {
        case .dashboard:
            OperatorDashboardView(
                viewModel: dashboardViewModel,
                syncProgressStore: syncProgressStore,
                onSelectWorkOrder: { router.push(.workOrderDetail($0)) },
                onShowAllUrgent: {
                    router.selectedTab = .workOrders
                    Task {
                        await workOrderListViewModel.applyDashboardScope(.urgent)
                    }
                },
                onShowAllCompleted: {
                    router.selectedTab = .workOrders
                    Task {
                        await workOrderListViewModel.applyDashboardScope(.completed)
                    }
                },
                onSelectKPI: { selection in
                    router.selectedTab = .workOrders
                    Task {
                        switch selection {
                        case .openWorkOrders:
                            await workOrderListViewModel.applyDashboardScope(.open)
                        case .urgentWorkOrders:
                            await workOrderListViewModel.applyDashboardScope(.urgent)
                        case .overdueWorkOrders:
                            await workOrderListViewModel.applyDashboardScope(.overdue)
                        case .pausedWorkOrders:
                            await workOrderListViewModel.applyDashboardScope(.paused)
                        case .availableTechnicians, .busyTechnicians:
                            break
                        }
                    }
                },
                onShowAllTechnicians: {
                    router.push(.technicians)
                    Task {
                        await technicianListViewModel.clearDashboardScope()
                    }
                },
                onSelectTechnicianStatus: { scope in
                    router.push(.technicians)
                    Task {
                        await technicianListViewModel.applyDashboardScope(scope)
                    }
                }
            )

        case .workOrders:
            OperatorWorkOrderListView(
                viewModel: workOrderListViewModel,
                onSelectWorkOrder: { router.push(.workOrderDetail($0)) },
                onShowEditRequests: { router.push(.editRequests) },
                onShowConflicts: { router.push(.conflicts) }
            )

        case .reports:
            EmptyView()

        case .notifications:
            OperatorNotificationListView(
                viewModel: notificationListViewModel,
                onOpenWorkOrder: { router.push(.workOrderDetail($0)) },
                onOpenEditRequest: { router.push(.editRequestDetail($0)) }
            )

        case .profile:
            operatorProfileView()
        }
    }

    private func operatorProfileView() -> some View {
        #if DEBUG
        OperatorProfileView(
            user: user,
            accountService: dependencies.profileAccountService,
            onShowReports: { router.push(.reports) },
            onShowConflicts: { router.push(.conflicts) },
            onShowCustomers: { router.push(.customers) },
            onShowNotificationSettings: { router.push(.notificationSettings) },
            onShowChangePassword: { router.push(.changePassword) },
            onShowDebugTools: { router.push(.debugDeveloperTools) },
            onLogout: onLogout
        )
        #else
        OperatorProfileView(
            user: user,
            accountService: dependencies.profileAccountService,
            onShowReports: { router.push(.reports) },
            onShowConflicts: { router.push(.conflicts) },
            onShowCustomers: { router.push(.customers) },
            onShowNotificationSettings: { router.push(.notificationSettings) },
            onShowChangePassword: { router.push(.changePassword) },
            onLogout: onLogout
        )
        #endif
    }

    @ViewBuilder
    private func destinationView(for destination: OperatorDestination) -> some View {
        switch destination {
        case .workOrderDetail(let id):
            OperatorWorkOrderDetailView(
                viewModel: workOrderDetailCache.viewModel(for: id),
                onShowReport: { router.push(.report($0)) },
                onShowTracking: { router.push(.tracking($0)) },
                onShowEditRequests: { router.push(.editRequests) },
                onShowCustomer: { router.push(.customerDetail($0)) }
            )

        case .newWorkOrderWizard:
            NewWorkOrderWizardView(
                viewModel: NewWorkOrderWizardViewModel(actor: user, dependencies: dependencies),
                onFinished: { id in
                    Task { @MainActor in
                        router.popToRoot()
                        router.selectedTab = .workOrders
                        router.push(.workOrderDetail(id))

                        Task {
                            await workOrderListViewModel.resetToDefaultListingAndLoad()
                            await dashboardViewModel.load()
                        }
                    }
                },
                onCancel: { router.popToRoot() }
            )

        case .editRequests:
            OperatorEditRequestListView(
                viewModel: editRequestListViewModel,
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

        case .conflicts:
            OperatorConflictListView(
                viewModel: conflictListViewModel,
                onSelect: { router.push(.conflictDetail($0)) }
            )

        case .conflictDetail(let id):
            OperatorConflictDetailView(
                viewModel: OperatorConflictDetailViewModel(
                    conflictId: id,
                    actor: user,
                    dependencies: dependencies
                )
            )

        case .notifications:
            OperatorNotificationListView(
                viewModel: notificationListViewModel,
                onOpenWorkOrder: { router.push(.workOrderDetail($0)) },
                onOpenEditRequest: { router.push(.editRequestDetail($0)) }
            )

        case .reports:
            OperatorReportsView(
                onSelectReport: { router.push(.reportDetail($0)) }
            )

        case .report(let id):
            OperatorWorkOrderReportView(
                workOrderId: id,
                dependencies: dependencies,
                actor: user
            )

        case .tracking(let id):
            OperatorWorkOrderTrackingView(
                workOrderId: id,
                dependencies: dependencies,
                actor: user
            )

        case .reportDetail(let kind):
            if kind == .customerAnalytics {
                OperatorCustomerAnalyticsView(
                    viewModel: customerAnalyticsCache.viewModel()
                )
            } else if kind == .customerSatisfaction {
                OperatorCustomerSatisfactionView(
                    viewModel: customerSatisfactionCache.viewModel(),
                    onSelectEntry: { router.push(.customerSatisfactionDetail($0)) }
                )
            } else if kind == .faultRecurrence {
                OperatorFaultRecurrenceAnalysisView(
                    viewModel: faultRecurrenceCache.viewModel(),
                    onSelectWorkOrder: { router.push(.workOrderDetail($0)) }
                )
            } else if kind == .dailyOperations {
                OperatorDailyOperationsReportView(
                    viewModel: dailyOperationsCache.viewModel(),
                    onSelectWorkOrder: { router.push(.workOrderDetail($0)) }
                )
            } else {
                OperatorReportDetailView(
                    viewModel: reportDetailCache.viewModel(for: kind),
                    mediaLoader: WorkOrderMediaLoader(storage: dependencies.storageDataSource),
                    onSelectWorkOrder: { router.push(.workOrderDetail($0)) }
                )
            }

        case .customers:
            OperatorCustomerListView(
                viewModel: customerListViewModel,
                onSelectCustomer: { router.push(.customerDetail($0)) }
            )

        case .technicians:
            OperatorTechnicianListView(viewModel: technicianListViewModel)

        case .customerDetail(let id):
            OperatorCustomerDetailView(
                viewModel: OperatorCustomerDetailViewModel(
                    customerId: id,
                    actor: user,
                    dependencies: dependencies
                ),
                onSelectWorkOrder: { router.push(.workOrderDetail($0)) },
                onEditCustomer: { router.push(.editCustomer($0)) }
            )

        case .editCustomer(let id):
            OperatorCustomerEditView(
                viewModel: OperatorCustomerEditViewModel(
                    customerId: id,
                    actor: user,
                    dependencies: dependencies
                ),
                onSaved: { router.pop() },
                onCancel: { router.pop() }
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

        case .customerSatisfactionDetail(let entry):
            CustomerSatisfactionDetailView(entry: entry)

        #if DEBUG
        case .debugDeveloperTools:
            DebugDeveloperToolsView(
                currentUser: user,
                showsDemoDataLoad: false,
                onOpenCustomerSatisfactionSurvey: { router.push(.customerSatisfactionSurvey($0)) }
            )
        #endif
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
