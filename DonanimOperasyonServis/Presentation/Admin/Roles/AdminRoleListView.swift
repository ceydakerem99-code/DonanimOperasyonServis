import SwiftUI

struct AdminRoleListView: View {
    @Bindable var viewModel: AdminRoleListViewModel
    var onSelectRole: (UserRole) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: AppSpacing.m) {
                AsyncLoadContainerView(
                    isLoading: viewModel.phase == .loading,
                    showsLoadingIndicator: viewModel.showsLoadingIndicator,
                    hasCachedContent: viewModel.hasCachedContent,
                    errorMessage: AsyncLoadPhaseParsing.errorMessage(viewModel.phase),
                    isEmpty: false,
                    loadingMessage: "Roller yükleniyor...",
                    errorTitle: "Roller yüklenemedi",
                    onRetry: { Task { await viewModel.load() } }
                ) {
                    ForEach(viewModel.rows) { row in
                        roleRow(row)
                    }
                }
            }
            .padding(.horizontal, AppSpacing.l)
            .padding(.bottom, AppSpacing.xl)
        }
        .navigationTitle("Rol Yönetimi")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load() }
        .refreshable { await viewModel.load() }
    }

    private func roleRow(_ row: AdminRoleRowData) -> some View {
        Button {
            onSelectRole(row.role)
        } label: {
            HStack(spacing: AppSpacing.m) {
                Image(systemName: "shield.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(AppColor.brandPrimary)
                    .frame(width: 40)
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Text(row.title)
                        .font(AppFont.subtitle)
                        .foregroundStyle(AppColor.primaryText)
                    Text(row.subtitle)
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.secondaryText)
                        .lineLimit(2)
                    Text("\(row.userCount) aktif kullanıcı")
                        .font(AppFont.label)
                        .foregroundStyle(AppColor.brandPrimary)
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
        .accessibilityLabel("\(row.title), \(row.userCount) aktif kullanıcı")
    }
}

#if DEBUG
#Preview("Roles — loaded") {
    NavigationStack {
        AdminRoleListView(viewModel: .previewLoaded(), onSelectRole: { _ in })
    }
}
#endif
