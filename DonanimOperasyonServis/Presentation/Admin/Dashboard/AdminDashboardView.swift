import SwiftUI

struct AdminDashboardView: View {
    @Bindable var viewModel: AdminDashboardViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.l) {
                greetingSection

                switch viewModel.phase {
                case .loading:
                    LoadingView(message: "Özet yükleniyor...")
                        .frame(minHeight: 240)

                case .error(let message):
                    ErrorBanner(title: "Dashboard yüklenemedi", message: message) {
                        Task { await viewModel.load() }
                    }

                case .empty:
                    EmptyState(
                        systemImage: "chart.bar",
                        title: "Henüz veri yok",
                        message: "Kullanıcı ve iş emri verileri eklendiğinde özet burada görünecek."
                    )

                case .loaded:
                    systemSummaryCard
                    workOrderSummaryCard
                    if !viewModel.alerts.isEmpty {
                        alertsSection
                    }
                    if !viewModel.recentActivities.isEmpty {
                        recentActivitiesSection
                    }
                }
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
                metric(title: "Admin", value: viewModel.summary.adminCount)
                metric(title: "Operasyon Yetkilisi", value: viewModel.summary.operatorCount)
                metric(title: "Teknisyen", value: viewModel.summary.technicianCount)
                metric(title: "Toplam İş Emri", value: viewModel.summary.totalWorkOrders)
            }
        }
    }

    private var workOrderSummaryCard: some View {
        summaryCard(title: "İş Emri Özeti", badge: "Durum") {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: AppSpacing.m) {
                metric(title: "Atandı", value: viewModel.summary.assigned)
                metric(title: "Devam Eden", value: viewModel.summary.inProgress)
                metric(title: "Beklemede", value: viewModel.summary.paused)
                metric(title: "Tamamlandı", value: viewModel.summary.completed)
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

    private func metric(title: String, value: Int) -> some View {
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

    private var alertsSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.s) {
            SectionHeader(title: "Uyarılar")
            ForEach(viewModel.alerts, id: \.self) { alert in
                HStack(spacing: AppSpacing.s) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(AppColor.warning)
                    Text(alert)
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.primaryText)
                }
                .padding(AppSpacing.m)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: AppRadius.card).fill(AppColor.elevatedSurface))
            }
        }
    }

    private var recentActivitiesSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.s) {
            SectionHeader(title: "Son Aktiviteler")
            ForEach(Array(viewModel.recentActivities.enumerated()), id: \.element.id) { index, item in
                TimelineItem(
                    time: item.time,
                    title: item.title,
                    subtitle: item.subtitle,
                    accentColor: AppColor.brandPrimary,
                    showsConnector: index < viewModel.recentActivities.count - 1
                )
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
