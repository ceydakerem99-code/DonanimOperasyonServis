import SwiftUI

/// Read-only conflict visibility for admin. Resolution remains operator-only.
struct AdminConflictListView: View {
    @Bindable var viewModel: AdminConflictListViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.m) {
                Text("Çakışmalar yalnızca görüntülenir. Çözüm yetkisi operasyon yetkilisindedir.")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.secondaryText)

                switch viewModel.phase {
                case .loading:
                    LoadingView(message: "Çakışmalar yükleniyor...")
                        .frame(minHeight: 200)

                case .error(let message):
                    ErrorBanner(title: "Liste yüklenemedi", message: message) {
                        Task { await viewModel.load() }
                    }

                case .empty:
                    EmptyState(
                        systemImage: "checkmark.seal",
                        title: "Çözülmemiş çakışma yok",
                        message: "Tüm senkron kayıtları güncel."
                    )

                case .loaded:
                    ForEach(viewModel.rows) { row in
                        VStack(alignment: .leading, spacing: AppSpacing.xs) {
                            Text("\(row.entityType) · \(row.entityId)")
                                .font(AppFont.subtitle)
                            Text("Tespit: \(row.detectedAt)")
                                .font(AppFont.caption)
                                .foregroundStyle(AppColor.secondaryText)
                        }
                        .padding(AppSpacing.m)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: AppRadius.card).fill(AppColor.elevatedSurface))
                        .overlay(RoundedRectangle(cornerRadius: AppRadius.card).strokeBorder(AppColor.divider))
                    }
                }
            }
            .padding(.horizontal, AppSpacing.l)
            .padding(.bottom, AppSpacing.xl)
        }
        .navigationTitle("Senkron Çakışmaları")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load() }
    }
}

#if DEBUG
#Preview("Conflicts — empty") {
    NavigationStack {
        AdminConflictListView(viewModel: .previewEmpty())
    }
}
#endif
