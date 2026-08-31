import SwiftUI

struct OperatorTechnicianListView: View {
    @Bindable var viewModel: OperatorTechnicianListViewModel

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: AppSpacing.m) {
                if viewModel.dashboardScope != .none {
                    dashboardScopeBanner
                }

                filterChips
                searchField

                AsyncLoadContainerView(
                    isLoading: viewModel.phase == .loading,
                    showsLoadingIndicator: viewModel.showsLoadingIndicator,
                    hasCachedContent: viewModel.hasCachedContent,
                    errorMessage: AsyncLoadPhaseParsing.errorMessage(viewModel.phase),
                    isEmpty: viewModel.phase == .empty,
                    loadingMessage: "Teknisyenler yükleniyor...",
                    errorTitle: "Liste yüklenemedi",
                    onRetry: { Task { await viewModel.load() } },
                    content: {
                        ForEach(viewModel.rows) { row in
                            technicianCard(row)
                        }
                    },
                    empty: {
                        EmptyState(
                            systemImage: "person.crop.circle.badge.questionmark",
                            title: emptyTitle,
                            message: emptyMessage
                        )
                    }
                )
            }
            .padding(.horizontal, AppSpacing.l)
            .padding(.bottom, AppSpacing.xl)
        }
        .navigationTitle("Teknisyenler")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load() }
        .refreshable { await viewModel.load() }
        .onChange(of: viewModel.searchText) { _, _ in
            Task { await viewModel.load() }
        }
    }

    private var dashboardScopeBanner: some View {
        HStack(spacing: AppSpacing.s) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .foregroundStyle(AppColor.brandPrimary)
            Text("Dashboard filtresi: \(viewModel.selectedFilter.title)")
                .font(AppFont.caption)
                .foregroundStyle(AppColor.secondaryText)
            Spacer()
            Button("Temizle") {
                Task { await viewModel.clearDashboardScope() }
            }
            .font(AppFont.label)
            .foregroundStyle(AppColor.brandPrimary)
        }
        .padding(AppSpacing.m)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous)
                .fill(AppColor.brandPrimary.opacity(0.08))
        )
    }

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppSpacing.s) {
                ForEach(OperatorTechnicianListFilter.allCases, id: \.self) { filter in
                    filterChip(filter)
                }
            }
        }
    }

    private func filterChip(_ filter: OperatorTechnicianListFilter) -> some View {
        let selected = viewModel.selectedFilter == filter
        let role = filter.semanticRole
        return Button {
            Task { await viewModel.selectFilter(filter) }
        } label: {
            Text(filter.title)
                .font(AppFont.label)
                .foregroundStyle(selected ? AppColor.onPrimary : role.accentColor)
                .padding(.horizontal, AppSpacing.m)
                .padding(.vertical, AppSpacing.s)
                .background(
                    Capsule(style: .continuous)
                        .fill(selected ? role.accentColor : role.surfaceColor)
                )
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(role.accentColor.opacity(selected ? 0 : 0.25), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private var searchField: some View {
        HStack(spacing: AppSpacing.s) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(AppColor.secondaryText)
            TextField("Teknisyen ara...", text: $viewModel.searchText)
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

    private func technicianCard(_ row: OperatorTechnicianRow) -> some View {
        let role = row.workingStatus.semanticRole
        return HStack(spacing: AppSpacing.m) {
            Image(systemName: "person.crop.circle.fill")
                .font(.title2)
                .foregroundStyle(role.accentColor)
                .frame(width: 40)

            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text(row.fullName)
                    .font(AppFont.body)
                    .foregroundStyle(AppColor.primaryText)
                    .lineLimit(1)
                Text("\(row.workingStatus.displayName) · \(row.workloadSummary)")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.secondaryText)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
        }
        .padding(AppSpacing.m)
        .semanticAccentCard(role: role, minHeight: nil)
    }

    private var emptyTitle: String {
        if !viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Sonuç bulunamadı"
        }
        switch viewModel.selectedFilter {
        case .all: return "Teknisyen bulunamadı"
        case .available: return "Müsait teknisyen yok"
        case .busy: return "Meşgul teknisyen yok"
        }
    }

    private var emptyMessage: String {
        if !viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Arama kriterlerinize uygun teknisyen bulunamadı."
        }
        return "Aktif servis yetkilisi bulunamadı veya seçili durumda teknisyen yok."
    }
}

#if DEBUG
#Preview("Technician List") {
    NavigationStack {
        OperatorTechnicianListView(viewModel: .previewLoaded())
    }
}
#endif
