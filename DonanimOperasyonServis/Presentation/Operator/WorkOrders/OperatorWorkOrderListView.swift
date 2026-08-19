import SwiftUI

struct OperatorWorkOrderListView: View {
    @Bindable var viewModel: OperatorWorkOrderListViewModel
    var onSelectWorkOrder: (WorkOrderID) -> Void
    var onShowEditRequests: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.m) {
                searchField
                filterChips

                switch viewModel.phase {
                case .loading:
                    LoadingView(message: "İş emirleri yükleniyor...")
                        .frame(minHeight: 240)

                case .error(let message):
                    ErrorBanner(title: "Liste yüklenemedi", message: message) {
                        Task { await viewModel.load() }
                    }

                case .empty:
                    EmptyState(
                        systemImage: "doc.text.magnifyingglass",
                        title: "İş emri bulunamadı",
                        message: "Filtreleri değiştirin veya yeni iş emri oluşturun."
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
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: onShowEditRequests) {
                    Image(systemName: "doc.text.magnifyingglass")
                }
                .accessibilityLabel("Düzenleme Talepleri")
            }
        }
        .task { await viewModel.load() }
        .refreshable { await viewModel.load() }
        .onChange(of: viewModel.searchText) { _, _ in
            Task { await viewModel.load() }
        }
    }

    private var searchField: some View {
        HStack(spacing: AppSpacing.s) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(AppColor.secondaryText)
            TextField("Ara...", text: $viewModel.searchText)
                .font(AppFont.body)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
        .padding(AppSpacing.m)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous)
                .fill(AppColor.elevatedSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous)
                .strokeBorder(AppColor.divider, lineWidth: 1)
        )
    }

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppSpacing.s) {
                ForEach(OperatorWorkOrderListFilter.allCases, id: \.self) { filter in
                    filterChip(filter)
                }
            }
        }
    }

    private func filterChip(_ filter: OperatorWorkOrderListFilter) -> some View {
        let selected = viewModel.selectedFilter == filter
        return Button {
            Task { await viewModel.selectFilter(filter) }
        } label: {
            Text(filter.title)
                .font(AppFont.label)
                .foregroundStyle(selected ? AppColor.onPrimary : AppColor.primaryText)
                .padding(.horizontal, AppSpacing.m)
                .padding(.vertical, AppSpacing.s)
                .background(
                    Capsule(style: .continuous)
                        .fill(selected ? AppColor.brandPrimary : AppColor.elevatedSurface)
                )
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(AppColor.divider, lineWidth: selected ? 0 : 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("\(filter.title) filtresi"))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

#if DEBUG
#Preview("WorkOrder List — loaded") {
    NavigationStack {
        OperatorWorkOrderListView(
            viewModel: .previewLoaded(),
            onSelectWorkOrder: { _ in },
            onShowEditRequests: {}
        )
    }
}

#Preview("WorkOrder List — empty") {
    NavigationStack {
        OperatorWorkOrderListView(
            viewModel: .previewEmpty(),
            onSelectWorkOrder: { _ in },
            onShowEditRequests: {}
        )
    }
}
#endif
