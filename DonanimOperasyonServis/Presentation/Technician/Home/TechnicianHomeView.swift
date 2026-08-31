import SwiftUI

struct TechnicianHomeView: View {
    @Bindable var viewModel: TechnicianHomeViewModel
    var onSelectWorkOrder: (WorkOrderID) -> Void
    var onShowWorkOrders: () -> Void

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: AppSpacing.l) {
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Text("Merhaba, \(viewModel.userFirstName) 👋")
                        .font(AppFont.title)
                    Text(WorkOrderPresentationMapping.greetingDate())
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.secondaryText)
                }

                AsyncLoadContainerView(
                    isLoading: viewModel.phase == .loading,
                    showsLoadingIndicator: viewModel.showsLoadingIndicator,
                    hasCachedContent: viewModel.hasCachedContent,
                    errorMessage: AsyncLoadPhaseParsing.errorMessage(viewModel.phase),
                    isEmpty: viewModel.phase == .empty,
                    loadingMessage: "Günlük özet yükleniyor...",
                    errorTitle: "Ana sayfa yüklenemedi",
                    onRetry: { Task { await viewModel.load() } },
                    content: {
                        summaryCard
                        if let active = viewModel.activeJob {
                            SectionHeader(title: "Aktif İş") {
                                Button("Detay") { onSelectWorkOrder(WorkOrderID(active.id)) }
                                    .font(AppFont.label)
                                    .foregroundStyle(AppColor.brandPrimary)
                            }
                            WorkOrderCard(data: active) {
                                onSelectWorkOrder(WorkOrderID(active.id))
                            }
                        }
                        if !viewModel.upcomingJobs.isEmpty {
                            SectionHeader(title: "Yaklaşan İşler") {
                                Button("Tümü") { onShowWorkOrders() }
                                    .font(AppFont.label)
                                    .foregroundStyle(AppColor.brandPrimary)
                            }
                            ForEach(viewModel.upcomingJobs) { card in
                                WorkOrderCard(data: card) {
                                    onSelectWorkOrder(WorkOrderID(card.id))
                                }
                            }
                        }
                    },
                    empty: {
                        EmptyState(
                            systemImage: "tray",
                            title: "Atanmış iş yok",
                            message: "Size yeni bir iş atandığında burada görünecek."
                        )
                    }
                )
            }
            .padding(.horizontal, AppSpacing.l)
            .padding(.bottom, AppSpacing.xl)
        }
        .navigationTitle("Ana Sayfa")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load() }
        .refreshable { await viewModel.load() }
        .onAppear {
            if viewModel.hasCachedContent {
                Task { await viewModel.refreshFromRemoteDirectory() }
            }
        }
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: AppSpacing.m) {
            Text("Günlük İş Özeti")
                .font(AppFont.subtitle)
                .foregroundStyle(AppColor.onPrimary)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: AppSpacing.m) {
                metric("Toplam", viewModel.summary.total)
                metric("Devam Eden", viewModel.summary.inProgress)
                metric("Beklemede", viewModel.summary.paused)
                metric("Tamamlanan", viewModel.summary.completed)
            }
        }
        .padding(AppSpacing.l)
        .background(RoundedRectangle(cornerRadius: AppRadius.card).fill(AppColor.brandPrimary))
    }

    private func metric(_ title: String, _ value: Int) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text(title).font(AppFont.caption).foregroundStyle(AppColor.onPrimary.opacity(0.85))
            Text("\(value)").font(AppFont.title).foregroundStyle(AppColor.onPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#if DEBUG
#Preview("Technician Home") {
    NavigationStack {
        TechnicianHomeView(viewModel: .previewLoaded(), onSelectWorkOrder: { _ in }, onShowWorkOrders: {})
    }
}
#endif
