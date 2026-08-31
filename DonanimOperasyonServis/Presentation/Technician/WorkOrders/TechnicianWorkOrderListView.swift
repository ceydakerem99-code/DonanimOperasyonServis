import SwiftUI

struct TechnicianWorkOrderListView: View {
    @Bindable var viewModel: TechnicianWorkOrderListViewModel
    var onSelectWorkOrder: (WorkOrderID) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: AppSpacing.m) {
                searchField
                filterChips
                AsyncLoadContainerView(
                    isLoading: viewModel.phase == .loading,
                    showsLoadingIndicator: viewModel.showsLoadingIndicator,
                    hasCachedContent: viewModel.hasCachedContent,
                    errorMessage: AsyncLoadPhaseParsing.errorMessage(viewModel.phase),
                    isEmpty: viewModel.phase == .empty,
                    loadingMessage: "İş emirleri yükleniyor...",
                    errorTitle: "Liste yüklenemedi",
                    onRetry: { Task { await viewModel.load() } },
                    content: {
                        ForEach(viewModel.cards) { card in
                            WorkOrderCard(data: card) {
                                onSelectWorkOrder(WorkOrderID(card.id))
                            }
                        }
                    },
                    empty: {
                        EmptyState(
                            systemImage: "doc.text.magnifyingglass",
                            title: "Atanmış iş emri yok",
                            message: "Size atanan işler burada listelenecek."
                        )
                    }
                )
            }
            .padding(.horizontal, AppSpacing.l)
            .padding(.bottom, AppSpacing.xl)
        }
        .navigationTitle("İş Emirleri")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load() }
        .refreshable { await viewModel.load() }
        .onAppear {
            // The first local read can legitimately be empty while the
            // assigned-work-order directory is still being hydrated.
            // Always request the refresh on first appearance; the refresh
            // gate coalesces this with `.task` and foreground refreshes.
            Task { await viewModel.refreshFromRemoteDirectory() }
        }
        .onChange(of: viewModel.searchText) { _, _ in
            Task { await viewModel.applyLocalSearch() }
        }
    }

    private var searchField: some View {
        HStack(spacing: AppSpacing.s) {
            Image(systemName: "magnifyingglass").foregroundStyle(AppColor.secondaryText)
            TextField("Ara...", text: $viewModel.searchText)
                .font(AppFont.body)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
        .padding(AppSpacing.m)
        .background(RoundedRectangle(cornerRadius: AppRadius.card).fill(AppColor.elevatedSurface))
        .overlay(RoundedRectangle(cornerRadius: AppRadius.card).strokeBorder(AppColor.divider))
    }

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppSpacing.s) {
                ForEach(TechnicianWorkOrderListFilter.allCases, id: \.self) { filter in
                    let selected = viewModel.selectedFilter == filter
                    Button { Task { await viewModel.selectFilter(filter) } } label: {
                        Text(filter.title)
                            .font(AppFont.label)
                            .foregroundStyle(selected ? AppColor.onPrimary : AppColor.primaryText)
                            .padding(.horizontal, AppSpacing.m)
                            .padding(.vertical, AppSpacing.s)
                            .background(Capsule().fill(selected ? AppColor.brandPrimary : AppColor.elevatedSurface))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

#if DEBUG
#Preview("Technician List") {
    NavigationStack {
        TechnicianWorkOrderListView(viewModel: .previewLoaded(), onSelectWorkOrder: { _ in })
    }
}
#endif
