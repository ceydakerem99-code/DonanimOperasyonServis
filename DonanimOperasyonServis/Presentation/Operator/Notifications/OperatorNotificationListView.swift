import SwiftUI

struct OperatorNotificationListView: View {
    @Bindable var viewModel: OperatorNotificationListViewModel

    var body: some View {
        ScrollView {
            switch viewModel.phase {
            case .loading:
                LoadingView(message: "Bildirimler yükleniyor...")
                    .frame(minHeight: 240)

            case .error(let message):
                ErrorBanner(title: "Bildirimler yüklenemedi", message: message) {
                    Task { await viewModel.load() }
                }
                .padding(AppSpacing.l)

            case .empty:
                EmptyState(
                    systemImage: "bell.slash",
                    title: "Bildirim yok",
                    message: "Yeni bildirimler burada görünecek."
                )

            case .loaded:
                LazyVStack(spacing: AppSpacing.m) {
                    ForEach(viewModel.notifications) { item in
                        notificationRow(item)
                    }
                }
                .padding(.horizontal, AppSpacing.l)
                .padding(.bottom, AppSpacing.xl)
            }
        }
        .navigationTitle("Bildirimler")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load() }
        .refreshable { await viewModel.load() }
    }

    private func notificationRow(_ item: OperatorNotificationRow) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            HStack {
                Text(item.title)
                    .font(AppFont.subtitle)
                    .foregroundStyle(AppColor.primaryText)
                Spacer()
                if !item.isRead {
                    Circle()
                        .fill(AppColor.brandPrimary)
                        .frame(width: 8, height: 8)
                }
            }
            Text(item.body)
                .font(AppFont.body)
                .foregroundStyle(AppColor.secondaryText)
            Text(WorkOrderPresentationMapping.formatDateTime(item.createdAt))
                .font(AppFont.caption)
                .foregroundStyle(AppColor.secondaryText)
        }
        .padding(AppSpacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: AppRadius.card).fill(AppColor.elevatedSurface))
        .overlay(RoundedRectangle(cornerRadius: AppRadius.card).strokeBorder(AppColor.divider))
        .onTapGesture {
            Task { await viewModel.markRead(item.id) }
        }
    }
}

#if DEBUG
#Preview("Notifications") {
    NavigationStack {
        OperatorNotificationListView(viewModel: .previewLoaded())
    }
}
#endif
