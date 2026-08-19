import SwiftUI

/// Centered loading indicator with an optional caption.
struct LoadingView: View {
    var message: String?

    var body: some View {
        VStack(spacing: AppSpacing.m) {
            ProgressView()
                .progressViewStyle(.circular)
                .tint(AppColor.brandPrimary)
                .controlSize(.large)
            if let message {
                Text(message)
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.secondaryText)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(AppSpacing.xl)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(message ?? "Yükleniyor"))
    }
}

#if DEBUG
#Preview("LoadingView") {
    VStack(spacing: AppSpacing.xxl) {
        LoadingView()
        LoadingView(message: "İş emirleri yükleniyor...")
    }
    .background(AppColor.neutralBackground)
}
#endif
