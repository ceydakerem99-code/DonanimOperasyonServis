import SwiftUI

struct AdminDashboardView: View {
    @Bindable var viewModel: AdminDashboardViewModel
    var onShowUsers: ((UserRole?) -> Void)?
    var onShowReports: ((AdminReportKind) -> Void)?
    var onShowConflicts: (() -> Void)?
    var onSelectWorkOrder: ((WorkOrderID) -> Void)?
    var onShowAllCompleted: (() -> Void)?

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
                        systemSummaryCard
                        workOrderSummaryCard
                        if !viewModel.recentActivities.isEmpty {
                            recentActivitiesSection
                        }
                        if !viewModel.recentCompletedOrders.isEmpty {
                            recentCompletedSection
                        }
                    },
                    empty: {
                        EmptyState(
                            systemImage: "chart.bar",
                            title: "Henüz veri yok",
                            message: "Kullanıcı ve iş emri verileri eklendiğinde özet burada görünecek."
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
    }

    private var greetingSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text("Merhaba, \(viewModel.userFirstName)")
                .font(AppFont.title)
                .foregroundStyle(AppColor.primaryText)
            Text(WorkOrderPresentationMapping.greetingDate())
                .font(AppFont.caption)
                .foregroundStyle(AppColor.secondaryText)
        }
        .padding(.top, AppSpacing.s)
    }

    private var systemSummaryCard: some View {
        summaryCard(title: "Sistem Özeti", badge: viewModel.summary.isOnline ? "Çevrimiçi" : "Çevrimdışı") {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: AppSpacing.m) {
                tappableMetric(title: "Admin", value: viewModel.summary.adminCount) {
                    onShowUsers?(.admin)
                }
                tappableMetric(title: "Operasyon Yetkilisi", value: viewModel.summary.operatorCount) {
                    onShowUsers?(.operator)
                }
                tappableMetric(title: "Teknisyen", value: viewModel.summary.technicianCount) {
                    onShowUsers?(.technician)
                }
                tappableMetric(title: "Toplam İş Emri", value: viewModel.summary.totalWorkOrders) {
                    onShowReports?(.workOrders)
                }
            }
        }
    }

    private var workOrderSummaryCard: some View {
        summaryCard(title: "İş Emri Özeti", badge: "Durum") {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: AppSpacing.m) {
                tappableMetric(title: "Atandı", value: viewModel.summary.assigned) {
                    onShowReports?(.workOrders)
                }
                tappableMetric(title: "Devam Eden", value: viewModel.summary.inProgress) {
                    onShowReports?(.workOrders)
                }
                tappableMetric(title: "Beklemede", value: viewModel.summary.paused) {
                    onShowReports?(.pauseReasons)
                }
                tappableMetric(title: "Tamamlandı", value: viewModel.summary.completed) {
                    onShowReports?(.workOrders)
                }
            }
        }
    }

    private func summaryCard<Content: View>(
        title: String,
        badge: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.m) {
            HStack {
                Text(title)
                    .font(AppFont.subtitle)
                    .foregroundStyle(AppColor.onPrimary)
                Spacer()
                Text(badge)
                    .font(AppFont.label)
                    .foregroundStyle(AppColor.onPrimary.opacity(0.85))
            }
            content()
        }
        .padding(AppSpacing.l)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous)
                .fill(AppColor.brandPrimary)
        )
    }

    private func tappableMetric(title: String, value: Int, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text(title)
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.onPrimary.opacity(0.85))
                Text("\(value)")
                    .font(AppFont.title)
                    .foregroundStyle(AppColor.onPrimary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .accessibilityHint("İlgili ekrana gider")
    }

    private var recentActivitiesSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.s) {
            SectionHeader(title: "Son Aktiviteler")
            ForEach(Array(viewModel.recentActivities.enumerated()), id: \.element.id) { index, item in
                Button {
                    onSelectWorkOrder?(WorkOrderID(item.id))
                } label: {
                    TimelineItem(
                        time: item.time,
                        title: item.title,
                        subtitle: item.subtitle,
                        accentColor: AppColor.brandPrimary,
                        showsConnector: index < viewModel.recentActivities.count - 1
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var recentCompletedSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.s) {
            SectionHeader(title: "Son Tamamlanan İşler") {
                Button("Tümünü Gör") { onShowAllCompleted?() }
                    .font(AppFont.label)
                    .foregroundStyle(AppColor.brandPrimary)
            }
            ForEach(viewModel.recentCompletedOrders) { card in
                WorkOrderCard(data: card) {
                    onSelectWorkOrder?(WorkOrderID(card.id))
                }
            }
        }
    }
}

#if DEBUG
#Preview("Dashboard — loaded") {
    NavigationStack {
        AdminDashboardView(viewModel: .previewLoaded())
    }
}

#Preview("Dashboard — empty") {
    NavigationStack {
        AdminDashboardView(viewModel: .previewEmpty())
    }
}

#Preview("Dashboard — error") {
    NavigationStack {
        AdminDashboardView(viewModel: .previewError())
    }
}
#endif
