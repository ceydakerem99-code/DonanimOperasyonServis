import SwiftUI

struct OperatorCustomerListView: View {
    @Bindable var viewModel: OperatorCustomerListViewModel
    var onSelectCustomer: (CustomerID) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: AppSpacing.m) {
                searchField

                AsyncLoadContainerView(
                    isLoading: viewModel.phase == .loading,
                    showsLoadingIndicator: viewModel.showsLoadingIndicator,
                    hasCachedContent: viewModel.hasCachedContent,
                    errorMessage: AsyncLoadPhaseParsing.errorMessage(viewModel.phase),
                    isEmpty: viewModel.phase == .empty,
                    loadingMessage: "Müşteriler yükleniyor...",
                    errorTitle: "Liste yüklenemedi",
                    onRetry: { Task { await viewModel.load() } },
                    content: {
                        ForEach(viewModel.rows) { row in
                            customerCard(row)
                        }
                    },
                    empty: {
                        EmptyState(
                            systemImage: "building.2",
                            title: "Müşteri bulunamadı",
                            message: viewModel.searchText.isEmpty
                                ? "Henüz kayıtlı müşteri yok. Yeni iş emri sihirbazından müşteri ekleyebilirsiniz."
                                : "Arama kriterlerinize uygun müşteri bulunamadı."
                        )
                    }
                )
            }
            .padding(.horizontal, AppSpacing.l)
            .padding(.bottom, AppSpacing.xl)
        }
        .navigationTitle("Müşteriler")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load() }
        .refreshable { await viewModel.load() }
        .onChange(of: viewModel.searchText) { _, _ in
            Task { await viewModel.load() }
        }
        .onAppear {
            Task { await viewModel.load() }
        }
    }

    private var searchField: some View {
        HStack(spacing: AppSpacing.s) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(AppColor.secondaryText)
            TextField("Ad, telefon, adres veya şehir ara...", text: $viewModel.searchText)
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

    private func customerCard(_ row: OperatorCustomerRow) -> some View {
        Button {
            onSelectCustomer(row.id)
        } label: {
            HStack(spacing: AppSpacing.m) {
                Image(systemName: "building.2.fill")
                    .font(.title2)
                    .foregroundStyle(AppColor.brandPrimary)
                    .frame(width: 40)
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Text(row.name)
                        .font(AppFont.subtitle)
                        .foregroundStyle(AppColor.primaryText)
                        .multilineTextAlignment(.leading)
                    if !row.subtitle.isEmpty {
                        Text(row.subtitle)
                            .font(AppFont.caption)
                            .foregroundStyle(AppColor.secondaryText)
                            .multilineTextAlignment(.leading)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.secondaryText)
            }
            .padding(AppSpacing.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous)
                    .fill(AppColor.elevatedSurface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous)
                    .strokeBorder(AppColor.divider, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(row.name)
    }
}

#if DEBUG
#Preview("Customer List") {
    NavigationStack {
        OperatorCustomerListView(
            viewModel: OperatorCustomerListViewModel.previewLoaded(),
            onSelectCustomer: { _ in }
        )
    }
}
#endif
