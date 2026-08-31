import SwiftUI

/// Shared top chrome for every role shell. Keeps auth profile context
/// visible without mixing navigation state into `AuthSessionController`.
struct AppShellHeader: View {
    let title: String
    let userName: String
    var syncStore: SyncProgressStore?

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text(title)
                    .font(AppFont.title)
                    .foregroundStyle(AppColor.primaryText)
                    .accessibilityAddTraits(.isHeader)
                Text(userName)
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.secondaryText)
                ConnectionStatusIndicator()
            }
            Spacer()
            if let syncStore {
                SyncStatusBadge(store: syncStore)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, AppSpacing.l)
        .padding(.top, AppSpacing.m)
        .padding(.bottom, AppSpacing.s)
        .background(AppColor.neutralBackground)
    }
}

enum SyncStatusBadgeRules {
    static func showsWaitingBadge(waitingCount: Int, hasError: Bool) -> Bool {
        !hasError && waitingCount > 0
    }

    static func showsErrorBadge(hasError: Bool, errorCount: Int) -> Bool {
        hasError && errorCount > 0
    }
}

/// Compact sync status indicator shown in the app header.
struct SyncStatusBadge: View {
    let store: SyncProgressStore
    @Environment(\.diContainer) private var container

    var body: some View {
        Group {
            if store.isSyncing {
                HStack(spacing: AppSpacing.xs) {
                    ProgressView()
                        .controlSize(.mini)
                    Text("Senkronize ediliyor…")
                        .font(AppFont.label)
                        .foregroundStyle(AppColor.brandPrimary)
                }
                .padding(.horizontal, AppSpacing.s)
                .padding(.vertical, AppSpacing.xs)
                .background(Capsule().fill(AppColor.brandPrimary.opacity(0.1)))
                .accessibilityLabel("Senkronizasyon devam ediyor")
            } else if let snapshot = store.issueSnapshot {
                let waitingTotal = snapshot.retryableFailedCount + snapshot.pendingCount
                syncIssueBadge(
                    hasError: snapshot.activeFailedCount > 0,
                    waitingCount: waitingTotal,
                    errorCount: snapshot.activeFailedCount
                )
            } else if let report = store.lastReport {
                syncIssueBadge(
                    hasError: report.activeFailedCount > 0,
                    waitingCount: report.retryableFailedCount,
                    errorCount: report.activeFailedCount
                )
            }
        }
        .task {
            await container.syncCoordinator.refreshProgressSnapshot()
        }
    }

    @ViewBuilder
    private func syncIssueBadge(
        hasError: Bool,
        waitingCount: Int,
        errorCount: Int
    ) -> some View {
        if hasError {
            compactBadge(
                systemImage: "exclamationmark.arrow.triangle.2.circlepath",
                text: "\(errorCount)",
                tint: AppColor.warning,
                accessibilityLabel: "Senkronizasyon hatası"
            )
        } else if waitingCount > 0 {
            compactBadge(
                systemImage: "clock.arrow.circlepath",
                text: "\(waitingCount)",
                tint: AppColor.brandPrimary,
                accessibilityLabel: "Senkronizasyon bekliyor, \(waitingCount) bekleyen işlem"
            )
        }
    }

    @ViewBuilder
    private func compactBadge(
        systemImage: String,
        text: String,
        tint: Color,
        accessibilityLabel: String
    ) -> some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.system(size: 10, weight: .medium))
            Text(text)
                .font(AppFont.label)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, AppSpacing.xs)
        .padding(.vertical, 4)
        .background(Capsule().fill(tint.opacity(0.12)))
        .accessibilityLabel(accessibilityLabel)
    }
}
