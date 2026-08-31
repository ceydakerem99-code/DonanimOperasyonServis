import SwiftUI

struct OperatorDashboardView: View {
    @Bindable var viewModel: OperatorDashboardViewModel
    var syncProgressStore: SyncProgressStore?
    var onSelectWorkOrder: (WorkOrderID) -> Void
    var onShowAllUrgent: () -> Void
    var onShowAllCompleted: () -> Void
    var onSelectKPI: (OperatorDashboardKPISelection) -> Void
    var onShowAllTechnicians: () -> Void
    var onSelectTechnicianStatus: (OperatorTechnicianDashboardScope) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: AppSpacing.l) {
                greetingSection

                AsyncLoadContainerView(
                    isLoading: viewModel.phase == .loading,
                    showsLoadingIndicator: viewModel.showsLoadingIndicator,
                    hasCachedContent: viewModel.hasCachedContent,
                    errorMessage: AsyncLoadPhaseParsing.errorMessage(viewModel.phase),
                    isEmpty: viewModel.phase == .empty,
                    loadingMessage: "Özet yükleniyor...",
                    errorTitle: "Dashboard yüklenemedi",
                    onRetry: { Task { await viewModel.load() } },
                    content: {
                        operationsPanel
                        technicianStatusSection
                        urgentSection
                        recentCompletedSection
                    },
                    empty: {
                        EmptyState(
                            systemImage: "tray",
                            title: "Henüz iş emri yok",
                            message: "Yeni iş emri oluşturduğunuzda operasyon özeti burada görünecek."
                        )
                    }
                )
            }
            .padding(.horizontal, AppSpacing.l)
            .padding(.bottom, AppSpacing.xl)
        }
        .navigationTitle("Dashboard")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load() }
        .refreshable { await viewModel.load() }
        .onAppear {
            if viewModel.hasCachedContent {
                Task { await viewModel.refreshFromLocalCache() }
            }
        }
        .onChange(of: syncProgressStore?.isSyncing) { wasSyncing, isSyncing in
            guard wasSyncing == true, isSyncing == false else { return }
            Task { await viewModel.refreshFromLocalCache() }
        }
    }

    private var greetingSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text("Merhaba, \(viewModel.userFirstName) 👋")
                .font(AppFont.title)
                .foregroundStyle(AppColor.primaryText)
            Text(viewModel.greetingDate)
                .font(AppFont.caption)
                .foregroundStyle(AppColor.secondaryText)
        }
        .padding(.top, AppSpacing.s)
    }

    private var operationsPanel: some View {
        VStack(alignment: .leading, spacing: AppSpacing.m) {
            Text("Operasyon Özeti")
                .font(AppFont.subtitle)
                .foregroundStyle(AppColor.primaryText)

            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible())],
                spacing: AppSpacing.m
            ) {
                SemanticMetricCard(
                    title: "Açık İşler",
                    value: "\(viewModel.operationsKPIs.openWorkOrders)",
                    role: .primary,
                    systemImage: "doc.text",
                    action: { onSelectKPI(.openWorkOrders) }
                )
                SemanticMetricCard(
                    title: "Acil",
                    value: "\(viewModel.operationsKPIs.urgentWorkOrders)",
                    role: .urgent,
                    systemImage: "exclamationmark.triangle.fill",
                    action: { onSelectKPI(.urgentWorkOrders) }
                )
                SemanticMetricCard(
                    title: "Geciken",
                    value: "\(viewModel.operationsKPIs.overdueWorkOrders)",
                    role: .overdue,
                    systemImage: "clock.badge.exclamationmark",
                    action: { onSelectKPI(.overdueWorkOrders) }
                )
                SemanticMetricCard(
                    title: "Beklemede",
                    value: "\(viewModel.operationsKPIs.pausedWorkOrders)",
                    role: .paused,
                    systemImage: "pause.circle",
                    action: { onSelectKPI(.pausedWorkOrders) }
                )
            }
        }
    }

    private var technicianStatusSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.m) {
            SectionHeader(title: "Teknisyen Durumu") {
                Button("Tümünü Gör") { onShowAllTechnicians() }
                    .font(AppFont.label)
                    .foregroundStyle(AppColor.brandPrimary)
            }

            HStack(spacing: 0) {
                technicianStatusItem(
                    scope: .available,
                    count: viewModel.operationsKPIs.availableTechnicians,
                    label: "Müsait",
                    role: .available
                )
                technicianStatusDivider
                technicianStatusItem(
                    scope: .busy,
                    count: viewModel.operationsKPIs.busyTechnicians,
                    label: "Meşgul",
                    role: .busy
                )
            }
            .padding(.vertical, AppSpacing.m)
            .padding(.horizontal, AppSpacing.s)
            .semanticAccentCard(role: .neutral, minHeight: nil)
        }
    }

    private var technicianStatusDivider: some View {
        Rectangle()
            .fill(AppColor.divider)
            .frame(width: 1)
            .padding(.vertical, AppSpacing.s)
    }

    private func technicianStatusItem(
        scope: OperatorTechnicianDashboardScope,
        count: Int,
        label: String,
        role: AppSemanticRole
    ) -> some View {
        Button {
            onSelectTechnicianStatus(scope)
        } label: {
            VStack(spacing: AppSpacing.xs) {
                HStack(spacing: AppSpacing.xs) {
                    Circle()
                        .fill(role.accentColor)
                        .frame(width: 8, height: 8)
                    Text("\(count)")
                        .font(AppFont.title)
                        .foregroundStyle(AppColor.primaryText)
                }
                Text(label)
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.secondaryText)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var urgentSection: some View {
        if !viewModel.urgentOrders.isEmpty {
            SectionHeader(title: "Acil İşler") {
                Button("Tümü") { onShowAllUrgent() }
                    .font(AppFont.label)
                    .foregroundStyle(AppColor.brandPrimary)
            }

            ForEach(viewModel.urgentOrders) { card in
                WorkOrderCard(data: card) {
                    onSelectWorkOrder(WorkOrderID(card.id))
                }
            }

            SecondaryButton(title: "Tüm Acil İşler", systemImage: "exclamationmark.triangle") {
                onShowAllUrgent()
            }
        }
    }

    @ViewBuilder
    private var recentCompletedSection: some View {
        if !viewModel.recentCompletedOrders.isEmpty {
            SectionHeader(title: "Son Tamamlanan İşler") {
                Button("Tümünü Gör") { onShowAllCompleted() }
                    .font(AppFont.label)
                    .foregroundStyle(AppColor.brandPrimary)
            }

            ForEach(viewModel.recentCompletedOrders) { card in
                WorkOrderCard(data: card) {
                    onSelectWorkOrder(WorkOrderID(card.id))
                }
            }
        }
    }
}

#if DEBUG
#Preview("Dashboard — loaded") {
    NavigationStack {
        OperatorDashboardView(
            viewModel: .previewLoaded(),
            syncProgressStore: nil,
            onSelectWorkOrder: { _ in },
            onShowAllUrgent: {},
            onShowAllCompleted: {},
            onSelectKPI: { _ in },
            onShowAllTechnicians: {},
            onSelectTechnicianStatus: { _ in }
        )
    }
}

#Preview("Dashboard — empty") {
    NavigationStack {
        OperatorDashboardView(
            viewModel: .previewEmpty(),
            syncProgressStore: nil,
            onSelectWorkOrder: { _ in },
            onShowAllUrgent: {},
            onShowAllCompleted: {},
            onSelectKPI: { _ in },
            onShowAllTechnicians: {},
            onSelectTechnicianStatus: { _ in }
        )
    }
}
#endif
