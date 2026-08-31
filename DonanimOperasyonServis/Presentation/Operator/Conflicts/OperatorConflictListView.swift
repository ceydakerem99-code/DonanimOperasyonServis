import SwiftUI

struct OperatorConflictListView: View {
    @Bindable var viewModel: OperatorConflictListViewModel
    var onSelect: (SyncConflictID) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: AppSpacing.m) {
                Text("Çözülmemiş senkron çakışmalarını inceleyin. Yerel veya sunucu sürümünü seçebilirsiniz.")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.secondaryText)

                AsyncLoadContainerView(
                    isLoading: viewModel.phase == .loading,
                    showsLoadingIndicator: viewModel.showsLoadingIndicator,
                    hasCachedContent: viewModel.hasCachedContent,
                    errorMessage: AsyncLoadPhaseParsing.errorMessage(viewModel.phase),
                    isEmpty: viewModel.phase == .empty,
                    loadingMessage: "Çakışmalar yükleniyor...",
                    errorTitle: "Liste yüklenemedi",
                    onRetry: { Task { await viewModel.load() } },
                    content: {
                        ForEach(viewModel.rows) { row in
                            Button { onSelect(row.id) } label: {
                                conflictCard(row)
                            }
                            .buttonStyle(.plain)
                        }
                    },
                    empty: {
                        EmptyState(
                            systemImage: "checkmark.seal",
                            title: "Çözülmemiş çakışma yok",
                            message: "Tüm senkron kayıtları güncel."
                        )
                    }
                )
            }
            .padding(.horizontal, AppSpacing.l)
            .padding(.bottom, AppSpacing.xl)
        }
        .navigationTitle("Senkron Çakışmaları")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load() }
        .refreshable { await viewModel.load() }
    }

    private func conflictCard(_ row: OperatorConflictRowData) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.s) {
            HStack {
                Text(row.entityTypeLabel)
                    .font(AppFont.subtitle)
                    .foregroundStyle(AppColor.primaryText)
                Spacer()
                Text("v\(row.localVersion) / v\(row.remoteVersion)")
                    .font(AppFont.label)
                    .foregroundStyle(AppColor.warning)
            }
            Text(row.entityId)
                .font(AppFont.caption)
                .foregroundStyle(AppColor.secondaryText)
            Text("Tespit: \(row.detectedAtLabel)")
                .font(AppFont.caption)
                .foregroundStyle(AppColor.secondaryText)
        }
        .padding(AppSpacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: AppRadius.card).fill(AppColor.elevatedSurface))
        .overlay(RoundedRectangle(cornerRadius: AppRadius.card).strokeBorder(AppColor.divider))
    }
}

#if DEBUG
#Preview("Conflicts — empty") {
    NavigationStack {
        OperatorConflictListView(viewModel: .previewEmpty(), onSelect: { _ in })
    }
}
#endif
