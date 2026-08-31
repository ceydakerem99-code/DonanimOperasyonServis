import SwiftUI

/// Inline error banner used at the top of a screen or above a form.
///
/// Not a modal — it renders as a rounded, tinted card with an icon, a
/// title, and an optional secondary line. Callers provide an optional
/// retry closure that renders as a trailing action.
struct ErrorBanner: View {
    let title: String
    var message: String?
    var retryTitle: String = "Tekrar Dene"
    var onRetry: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: AppSpacing.m) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(AppFont.subtitle)
                .foregroundStyle(AppColor.statusError)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text(title)
                    .font(AppFont.subtitle)
                    .foregroundStyle(AppColor.primaryText)
                if let message {
                    Text(message)
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.secondaryText)
                }
            }

            Spacer(minLength: 0)

            if let onRetry {
                Button(action: onRetry) {
                    Text(retryTitle)
                        .font(AppFont.label)
                        .foregroundStyle(AppColor.statusError)
                        .padding(.horizontal, AppSpacing.s)
                        .frame(minHeight: AppSpacing.minimumTouchTarget)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(retryTitle))
            }
        }
        .padding(AppSpacing.m)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous)
                .fill(AppColor.semanticErrorSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous)
                .strokeBorder(AppColor.statusError.opacity(0.25), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
#Preview("ErrorBanner") {
    VStack(spacing: AppSpacing.l) {
        ErrorBanner(
            title: "İş emirleri alınamadı",
            message: "İnternet bağlantınızı kontrol edip tekrar deneyin.",
            onRetry: {}
        )
        ErrorBanner(title: "Konum servisleri kapalı")
    }
    .padding(AppSpacing.l)
    .background(AppColor.neutralBackground)
}
#endif
