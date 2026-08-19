import SwiftUI

struct OperatorDashboardView: View {
    @Bindable var viewModel: OperatorDashboardViewModel
    var onSelectWorkOrder: (WorkOrderID) -> Void
    var onShowAllUrgent: () -> Void

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
                        systemImage: "tray",
                        title: "Henüz iş emri yok",
                        message: "Yeni iş emri oluşturduğunuzda burada özet görünecek."
                    )

                case .loaded:
                    summaryCard
                    urgentSection
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
            Text("Merhaba, \(viewModel.userFirstName) 👋")
                .font(AppFont.title)
                .foregroundStyle(AppColor.primaryText)
            Text(viewModel.greetingDate)
                .font(AppFont.caption)
                .foregroundStyle(AppColor.secondaryText)
        }
        .padding(.top, AppSpacing.s)
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: AppSpacing.m) {
            HStack {
                Text("Günlük Özet")
                    .font(AppFont.subtitle)
                    .foregroundStyle(AppColor.onPrimary)
                Spacer()
                Text("Bugün")
                    .font(AppFont.label)
                    .foregroundStyle(AppColor.onPrimary.opacity(0.85))
            }

            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible())],
                spacing: AppSpacing.m
            ) {
                summaryMetric(title: "Toplam İş Emri", value: viewModel.summary.total)
                summaryMetric(title: "Atandı", value: viewModel.summary.assigned)
                summaryMetric(title: "Devam Eden", value: viewModel.summary.inProgress)
                summaryMetric(title: "Tamamlandı", value: viewModel.summary.completed)
            }
        }
        .padding(AppSpacing.l)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous)
                .fill(AppColor.brandPrimary)
        )
        .accessibilityElement(children: .combine)
    }

    private func summaryMetric(title: String, value: Int) -> some View {
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
}

#if DEBUG
#Preview("Dashboard — loaded") {
    NavigationStack {
        OperatorDashboardView(
            viewModel: .previewLoaded(),
            onSelectWorkOrder: { _ in },
            onShowAllUrgent: {}
        )
    }
}

#Preview("Dashboard — empty") {
    NavigationStack {
        OperatorDashboardView(
            viewModel: .previewEmpty(),
            onSelectWorkOrder: { _ in },
            onShowAllUrgent: {}
        )
    }
}
#endif
