import SwiftUI

struct OperatorNotificationListView: View {
    @Bindable var viewModel: OperatorNotificationListViewModel
    var onOpenWorkOrder: ((WorkOrderID) -> Void)?
    var onOpenEditRequest: ((EditRequestID) -> Void)?

    var body: some View {
        ScrollView {
            AsyncLoadContainerView(
                isLoading: viewModel.phase == .loading,
                showsLoadingIndicator: viewModel.showsLoadingIndicator,
                hasCachedContent: viewModel.hasCachedContent,
                errorMessage: AsyncLoadPhaseParsing.errorMessage(viewModel.phase),
                isEmpty: viewModel.phase == .empty,
                loadingMessage: "Bildirimler yükleniyor...",
                errorTitle: "Bildirimler yüklenemedi",
                onRetry: { Task { await viewModel.load() } },
                content: {
                    LazyVStack(spacing: AppSpacing.m) {
                        ForEach(viewModel.notifications) { item in
                            notificationRow(item)
                        }
                    }
                    .padding(.horizontal, AppSpacing.l)
                    .padding(.bottom, AppSpacing.xl)
                },
                empty: {
                    EmptyState(
                        systemImage: "bell.slash",
                        title: "Henüz bildiriminiz yok",
                        message: "Yeni bildirimler burada görünecek."
                    )
                }
            )
        }
        .navigationTitle("Bildirimler")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load() }
        .refreshable { await viewModel.load() }
        .alert(
            "Bildirim",
            isPresented: Binding(
                get: { viewModel.fallbackMessage != nil },
                set: { if !$0 { viewModel.clearFallbackMessage() } }
            )
        ) {
            Button("Tamam", role: .cancel) { viewModel.clearFallbackMessage() }
        } message: {
            Text(viewModel.fallbackMessage ?? "")
        }
    }

    private func notificationRow(_ item: OperatorNotificationRow) -> some View {
        Button {
            Task { await handleTap(item.id) }
        } label: {
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
            .background(
                RoundedRectangle(cornerRadius: AppRadius.card)
                    .fill(item.isRead ? AppColor.elevatedSurface : AppColor.brandSurface)
            )
            .overlay(RoundedRectangle(cornerRadius: AppRadius.card).strokeBorder(AppColor.divider))
        }
        .buttonStyle(.plain)
    }

    private func handleTap(_ id: NotificationID) async {
        let outcome = await viewModel.open(id)
        switch outcome {
        case .workOrderDetail(let workOrderId):
            onOpenWorkOrder?(workOrderId)
        case .editRequestDetail(let editRequestId):
            onOpenEditRequest?(editRequestId)
        case .markedReadOnly, .missingRelated:
            break
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
