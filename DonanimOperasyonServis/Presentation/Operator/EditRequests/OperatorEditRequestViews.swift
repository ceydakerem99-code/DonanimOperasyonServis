import SwiftUI

struct OperatorEditRequestListView: View {
    @Bindable var viewModel: OperatorEditRequestListViewModel
    var onSelect: (EditRequestID) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: AppSpacing.m) {
                filterChips

                AsyncLoadContainerView(
                    isLoading: viewModel.phase == .loading,
                    showsLoadingIndicator: viewModel.showsLoadingIndicator,
                    hasCachedContent: viewModel.hasCachedContent,
                    errorMessage: AsyncLoadPhaseParsing.errorMessage(viewModel.phase),
                    isEmpty: viewModel.phase == .empty,
                    loadingMessage: "Talepler yükleniyor...",
                    errorTitle: "Liste yüklenemedi",
                    onRetry: { Task { await viewModel.load() } },
                    content: {
                        ForEach(viewModel.rows) { row in
                            editRequestCard(row)
                        }
                    },
                    empty: {
                        EmptyState(
                            systemImage: "doc.text",
                            title: "Düzenleme talebi yok",
                            message: "Teknisyenlerden gelen talepler burada listelenecek."
                        )
                    }
                )
            }
            .padding(.horizontal, AppSpacing.l)
            .padding(.bottom, AppSpacing.xl)
        }
        .navigationTitle("Düzenleme Talepleri")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load() }
        .refreshable { await viewModel.load() }
    }

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppSpacing.s) {
                ForEach(OperatorEditRequestFilter.allCases, id: \.self) { filter in
                    let selected = viewModel.selectedFilter == filter
                    Button {
                        Task { await viewModel.selectFilter(filter) }
                    } label: {
                        Text(filter.title)
                            .font(AppFont.label)
                            .foregroundStyle(selected ? AppColor.onPrimary : AppColor.primaryText)
                            .padding(.horizontal, AppSpacing.m)
                            .padding(.vertical, AppSpacing.s)
                            .background(Capsule().fill(selected ? AppColor.brandPrimary : AppColor.elevatedSurface))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func editRequestCard(_ row: OperatorEditRequestRow) -> some View {
        Button { onSelect(row.id) } label: {
            VStack(alignment: .leading, spacing: AppSpacing.s) {
                HStack {
                    Text(row.workOrderNumber)
                        .font(AppFont.subtitle)
                    Spacer()
                    Text(row.status.displayName)
                        .font(AppFont.label)
                        .foregroundStyle(statusColor(row.status))
                }
                Text(row.requesterName)
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.secondaryText)
                Text(row.reason)
                    .font(AppFont.body)
                    .foregroundStyle(AppColor.primaryText)
            }
            .padding(AppSpacing.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: AppRadius.card).fill(AppColor.elevatedSurface))
            .overlay(RoundedRectangle(cornerRadius: AppRadius.card).strokeBorder(AppColor.divider))
        }
        .buttonStyle(.plain)
    }

    private func statusColor(_ status: EditRequestStatus) -> Color {
        switch status {
        case .pending: return AppColor.warning
        case .approved: return AppColor.success
        case .rejected: return AppColor.danger
        }
    }
}

struct OperatorEditRequestDetailView: View {
    @Bindable var viewModel: OperatorEditRequestDetailViewModel

    var body: some View {
        Group {
            switch viewModel.phase {
            case .loading, .submitting:
                LoadingView(message: viewModel.phase == .submitting ? "Kaydediliyor..." : "Yükleniyor...")
            case .error(let message):
                ErrorBanner(title: "Hata", message: message) {
                    Task { await viewModel.load() }
                }
                .padding(AppSpacing.l)
            case .loaded:
                if let request = viewModel.request {
                    detail(request)
                }
            }
        }
        .navigationTitle("Talep Detayı")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load() }
    }

    @ViewBuilder
    private func detail(_ request: EditRequest) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.l) {
                InfoRow(title: "İş Emri", value: viewModel.workOrderNumber, systemImage: "doc.text")
                InfoRow(title: "Talep Eden", value: viewModel.requesterName, systemImage: "person")
                InfoRow(title: "Alan", value: request.field, systemImage: "pencil")
                InfoRow(title: "Mevcut Değer", value: request.currentValue, systemImage: "text.alignleft")
                InfoRow(title: "İstenen Değer", value: request.requestedValue, systemImage: "arrow.right")
                InfoRow(title: "Gerekçe", value: request.reason, systemImage: "note.text")
                InfoRow(title: "Durum", value: request.status.displayName, systemImage: "flag")

                if request.status == .pending {
                    PrimaryButton(title: "Onayla") { Task { await viewModel.approve() } }
                    SecondaryButton(title: "Reddet") { Task { await viewModel.reject() } }
                }
            }
            .padding(AppSpacing.l)
        }
    }
}

#if DEBUG
#Preview("Edit Requests") {
    NavigationStack {
        OperatorEditRequestListView(viewModel: .previewLoaded(), onSelect: { _ in })
    }
}
#endif
