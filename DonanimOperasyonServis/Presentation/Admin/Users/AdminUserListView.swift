import SwiftUI

struct AdminUserListView: View {
    @Bindable var viewModel: AdminUserListViewModel
    var onSelectUser: (UserID) -> Void
    var onCreateUser: (() -> Void)?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: AppSpacing.m) {
                searchField
                filterChips
                if let role = viewModel.roleFilter {
                    HStack {
                        Text("Rol: \(role.displayName)")
                            .font(AppFont.caption)
                            .foregroundStyle(AppColor.secondaryText)
                        Spacer()
                        Button("Temizle") {
                            Task { await viewModel.applyRoleFilter(nil) }
                        }
                        .font(AppFont.label)
                        .foregroundStyle(AppColor.brandPrimary)
                    }
                }

                AsyncLoadContainerView(
                    isLoading: viewModel.phase == .loading,
                    showsLoadingIndicator: viewModel.showsLoadingIndicator,
                    hasCachedContent: viewModel.hasCachedContent,
                    errorMessage: AsyncLoadPhaseParsing.errorMessage(viewModel.phase),
                    isEmpty: viewModel.phase == .empty,
                    loadingMessage: "Kullanıcılar yükleniyor...",
                    errorTitle: "Liste yüklenemedi",
                    onRetry: { Task { await viewModel.load() } },
                    content: {
                        ForEach(viewModel.rows) { row in
                            userRow(row)
                        }
                    },
                    empty: {
                        EmptyState(
                            systemImage: "person.2",
                            title: "Kullanıcı bulunamadı",
                            message: "Arama veya filtre kriterlerini değiştirin."
                        )
                    }
                )
            }
            .padding(.horizontal, AppSpacing.l)
            .padding(.bottom, AppSpacing.xl)
        }
        .navigationTitle("Kullanıcılar")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if onCreateUser != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        onCreateUser?()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Yeni kullanıcı")
                }
            }
        }
        .task { await viewModel.load() }
        .refreshable { await viewModel.load() }
        .onChange(of: viewModel.searchText) { _, _ in
            viewModel.refreshSearch()
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
                ForEach(AdminUserListFilter.allCases, id: \.self) { filter in
                    filterChip(filter)
                }
            }
        }
    }

    private func filterChip(_ filter: AdminUserListFilter) -> some View {
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

    private func userRow(_ row: AdminUserRowData) -> some View {
        Button {
            onSelectUser(UserID(row.id))
        } label: {
            HStack(spacing: AppSpacing.m) {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(AppColor.brandPrimary)
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Text(row.fullName)
                        .font(AppFont.subtitle)
                        .foregroundStyle(AppColor.primaryText)
                    Text(row.email)
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.secondaryText)
                    HStack(spacing: AppSpacing.s) {
                        Text(row.roleLabel)
                            .font(AppFont.label)
                            .foregroundStyle(AppColor.brandPrimary)
                        Text(row.isActive ? "Aktif" : "Pasif")
                            .font(AppFont.label)
                            .foregroundStyle(row.isActive ? AppColor.success : AppColor.secondaryText)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(AppColor.secondaryText)
            }
            .padding(AppSpacing.m)
            .background(RoundedRectangle(cornerRadius: AppRadius.card).fill(AppColor.elevatedSurface))
            .overlay(RoundedRectangle(cornerRadius: AppRadius.card).strokeBorder(AppColor.divider))
        }
        .buttonStyle(.plain)
        .frame(minHeight: AppSpacing.minimumTouchTarget)
        .accessibilityLabel("\(row.fullName), \(row.roleLabel), \(row.isActive ? "aktif" : "pasif")")
    }
}

#if DEBUG
#Preview("Users — loaded") {
    NavigationStack {
        AdminUserListView(
            viewModel: .previewLoaded(),
            onSelectUser: { _ in },
            onCreateUser: {}
        )
    }
}

#Preview("Users — empty") {
    NavigationStack {
        AdminUserListView(viewModel: .previewEmpty(), onSelectUser: { _ in })
    }
}
#endif
