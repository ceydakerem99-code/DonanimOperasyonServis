import SwiftUI

struct TechnicianWorkOrderListView: View {
    @Bindable var viewModel: TechnicianWorkOrderListViewModel
    var onSelectWorkOrder: (WorkOrderID) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.m) {
                searchField
                filterChips
                switch viewModel.phase {
                case .loading:
                    LoadingView(message: "İş emirleri yükleniyor...")
                        .frame(minHeight: 220)
                case .error(let message):
                    ErrorBanner(title: "Liste yüklenemedi", message: message) {
                        Task { await viewModel.load() }
                    }
                case .empty:
                    EmptyState(
                        systemImage: "doc.text.magnifyingglass",
                        title: "Atanmış iş emri yok",
                        message: "Size atanan işler burada listelenecek."
                    )
                case .loaded:
                    ForEach(viewModel.cards) { card in
                        WorkOrderCard(data: card) {
                            onSelectWorkOrder(WorkOrderID(card.id))
                        }
                    }
                }
            }
            .padding(.horizontal, AppSpacing.l)
            .padding(.bottom, AppSpacing.xl)
        }
        .navigationTitle("İş Emirleri")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load() }
        .refreshable { await viewModel.load() }
        .onChange(of: viewModel.searchText) { _, _ in Task { await viewModel.load() } }
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
