import SwiftUI

struct TechnicianNotificationListView: View {
    @Bindable var viewModel: TechnicianNotificationListViewModel

    var body: some View {
        ScrollView {
            switch viewModel.phase {
            case .loading:
                LoadingView(message: "Bildirimler yükleniyor...").frame(minHeight: 220)
            case .error(let message):
                ErrorBanner(title: "Bildirimler yüklenemedi", message: message) {
                    Task { await viewModel.load() }
                }.padding(AppSpacing.l)
            case .empty:
                EmptyState(systemImage: "bell.slash", title: "Bildirim yok", message: "Yeni bildirimler burada görünecek.")
            case .loaded:
                LazyVStack(spacing: AppSpacing.m) {
                    ForEach(viewModel.notifications) { item in
                        VStack(alignment: .leading, spacing: AppSpacing.xs) {
                            Text(item.title).font(AppFont.subtitle)
                            Text(item.body).font(AppFont.body).foregroundStyle(AppColor.secondaryText)
                            Text(WorkOrderPresentationMapping.formatDateTime(item.createdAt))
                                .font(AppFont.caption).foregroundStyle(AppColor.secondaryText)
                        }
                        .padding(AppSpacing.m)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: AppRadius.card).fill(AppColor.elevatedSurface))
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
}

#if DEBUG
#Preview("Technician Notifications") {
    NavigationStack {
        TechnicianNotificationListView(viewModel: .previewLoaded())
    }
}
#endif
