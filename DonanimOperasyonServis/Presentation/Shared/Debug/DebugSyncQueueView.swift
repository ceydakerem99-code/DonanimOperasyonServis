#if DEBUG
import SwiftUI

/// Read-only sync queue inspector for DEBUG builds.
struct DebugSyncQueueView: View {
    @Bindable var viewModel: DebugSyncQueueViewModel

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: AppSpacing.m) {
                Text("Yerel sync kuyruğu. Başarısız operasyonlarda DEBUG amaçlı tekli \"Yeniden Dene\" mevcut sync pipeline'ını kullanır.")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.secondaryText)

                if let actionMessage = viewModel.actionMessage {
                    Text(actionMessage)
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.brandPrimary)
                }

                Picker("Durum filtresi", selection: $viewModel.selectedStatus) {
                    ForEach(SyncStatus.allCases, id: \.self) { status in
                        Text(status.displayName).tag(status)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: viewModel.selectedStatus) { _, _ in
                    Task { await viewModel.load() }
                }

                AsyncLoadContainerView(
                    isLoading: viewModel.phase == .loading,
                    showsLoadingIndicator: viewModel.showsLoadingIndicator,
                    hasCachedContent: viewModel.hasCachedContent,
                    errorMessage: AsyncLoadPhaseParsing.errorMessage(viewModel.phase),
                    isEmpty: viewModel.phase == .empty,
                    loadingMessage: "Sync operasyonları yükleniyor...",
                    errorTitle: "Liste yüklenemedi",
                    onRetry: { Task { await viewModel.load() } },
                    content: {
                        ForEach(viewModel.operations) { operation in
                            operationCard(operation)
                        }
                    },
                    empty: {
                        EmptyState(
                            systemImage: "tray",
                            title: "Kayıt yok",
                            message: "\(viewModel.selectedStatus.displayName) durumunda sync operasyonu bulunmuyor."
                        )
                    }
                )
            }
            .padding(.horizontal, AppSpacing.l)
            .padding(.bottom, AppSpacing.xl)
        }
        .navigationTitle("Sync Kuyruğu")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load() }
        .refreshable { await viewModel.load() }
    }

    private func operationCard(_ operation: SyncOperation) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.s) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(operation.entityType.rawValue) · \(operation.entityId)")
                    .font(AppFont.subtitle)
                    .foregroundStyle(AppColor.primaryText)
                Spacer(minLength: AppSpacing.s)
                Text(operation.status.displayName)
                    .font(AppFont.label)
                    .foregroundStyle(statusColor(operation.status))
            }

            InfoRow(title: "Durum", value: operation.status.displayName, systemImage: "arrow.triangle.2.circlepath")
            InfoRow(title: "Varlık Türü", value: operation.entityType.rawValue, systemImage: "cube")
            InfoRow(title: "Varlık ID", value: operation.entityId, systemImage: "number")
            InfoRow(title: "Actor UID", value: displayOptional(operation.actorUserId), systemImage: "person")
            InfoRow(title: "Hata Mesajı", value: displayOptional(operation.errorMessage), systemImage: "exclamationmark.bubble")
            InfoRow(title: "Yeniden Deneme", value: "\(operation.retryCount)", systemImage: "arrow.clockwise")
            InfoRow(
                title: "Son Deneme",
                value: displayOptionalDate(operation.lastAttemptAt),
                systemImage: "clock"
            )
            InfoRow(
                title: "Sonraki Deneme",
                value: displayOptionalDate(operation.nextRetryAt),
                systemImage: "clock.arrow.circlepath"
            )
            InfoRow(
                title: "Bağımlı Operasyon",
                value: displayOptional(operation.dependsOnOperationId?.rawValue),
                systemImage: "link"
            )

            if operation.status == .failed {
                SecondaryButton(
                    title: viewModel.isRetrying(operation.id) ? "Deneniyor…" : "Yeniden Dene",
                    systemImage: "arrow.clockwise",
                    isEnabled: viewModel.retryingOperationId == nil
                ) {
                    Task { await viewModel.retry(operation: operation) }
                }
            }
        }
        .padding(AppSpacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: AppRadius.card).fill(AppColor.elevatedSurface))
        .overlay(RoundedRectangle(cornerRadius: AppRadius.card).strokeBorder(AppColor.divider))
    }

    private func displayOptional(_ value: String?) -> String {
        guard let value, !value.isEmpty else { return "—" }
        return value
    }

    private func displayOptionalDate(_ date: Date?) -> String {
        guard let date else { return "—" }
        return WorkOrderPresentationMapping.formatDateTime(date)
    }

    private func statusColor(_ status: SyncStatus) -> Color {
        switch status {
        case .pending:    return AppColor.secondaryText
        case .inProgress: return AppColor.brandPrimary
        case .succeeded:  return AppColor.success
        case .failed:     return AppColor.danger
        case .conflict:   return AppColor.warning
        }
    }
}

#Preview("Sync Queue — empty") {
    NavigationStack {
        DebugSyncQueueView(
            viewModel: DebugSyncQueueViewModel(
                repository: DIContainer.mock().syncOperationRepository,
                syncManager: DIContainer.mock().syncManager
            )
        )
    }
}
#endif
