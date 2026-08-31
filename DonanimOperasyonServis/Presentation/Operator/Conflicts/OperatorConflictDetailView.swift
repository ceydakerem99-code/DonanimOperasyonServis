import SwiftUI

struct OperatorConflictDetailView: View {
    @Bindable var viewModel: OperatorConflictDetailViewModel

    var body: some View {
        Group {
            if viewModel.phase == .resolving {
                LoadingView(message: "Çözüm uygulanıyor...")
            } else if case .resolved(let decisionLabel) = viewModel.phase {
                resolvedBody(decisionLabel)
            } else {
                AsyncLoadContainerView(
                    isLoading: viewModel.phase == .loading,
                    showsLoadingIndicator: viewModel.showsLoadingIndicator,
                    hasCachedContent: viewModel.hasCachedContent,
                    errorMessage: AsyncLoadPhaseParsing.errorMessage(viewModel.phase),
                    isEmpty: false,
                    loadingMessage: "Çakışma yükleniyor...",
                    errorTitle: "Hata",
                    onRetry: { Task { await viewModel.load() } }
                ) {
                    if let conflict = viewModel.conflict {
                        detailBody(conflict)
                    }
                }
            }
        }
        .navigationTitle("Çakışma Detayı")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load() }
    }

    @ViewBuilder
    private func detailBody(_ conflict: SyncConflict) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.l) {
                InfoRow(title: "Kayıt Türü", value: viewModel.entityTypeLabel, systemImage: "doc")
                InfoRow(title: "Kayıt ID", value: conflict.entityId, systemImage: "number")
                InfoRow(title: "Tespit", value: viewModel.detectedAtLabel, systemImage: "clock")
                InfoRow(
                    title: "Durum",
                    value: conflict.isResolved ? "Çözüldü" : "Bekliyor",
                    systemImage: "flag"
                )

                ConflictSheet(
                    field: viewModel.entityTypeLabel,
                    server: .init(
                        title: conflict.remoteReference ?? conflict.entityId,
                        subtitle: "Uzak sürüm: v\(conflict.remoteVersion)",
                        updatedByLabel: nil,
                        timestampLabel: viewModel.detectedAtLabel
                    ),
                    local: .init(
                        title: conflict.localReference ?? conflict.entityId,
                        subtitle: "Yerel sürüm: v\(conflict.localVersion)",
                        updatedByLabel: nil,
                        timestampLabel: viewModel.detectedAtLabel
                    ),
                    onUseServer: {
                        Task { await viewModel.resolveUsingRemote() }
                    },
                    onUseLocal: {
                        Task { await viewModel.resolveUsingLocal() }
                    },
                    onDismiss: {
                        Task { await viewModel.leaveUnresolved() }
                    }
                )
                .disabled(!viewModel.canResolve)

                if let actionMessage = viewModel.actionMessage {
                    Text(actionMessage)
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.secondaryText)
                }
            }
            .padding(AppSpacing.l)
        }
    }

    private func resolvedBody(_ decisionLabel: String) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.l) {
            EmptyState(
                systemImage: "checkmark.seal.fill",
                title: "Çakışma çözüldü",
                message: decisionLabel
            )
            if let conflict = viewModel.conflict {
                InfoRow(title: "Kayıt Türü", value: viewModel.entityTypeLabel, systemImage: "doc")
                InfoRow(title: "Kayıt ID", value: conflict.entityId, systemImage: "number")
            }
            if let actionMessage = viewModel.actionMessage {
                Text(actionMessage)
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.secondaryText)
            }
        }
        .padding(AppSpacing.l)
    }
}
