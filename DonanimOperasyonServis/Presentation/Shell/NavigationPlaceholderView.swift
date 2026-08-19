import SwiftUI

/// Minimal Faz 7 destination — proves routing only, not real feature UI.
struct NavigationPlaceholderView: View {
    let title: String
    let subtitle: String
    var detail: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.l) {
                EmptyState(
                    systemImage: "arrow.triangle.branch",
                    title: title,
                    message: subtitle
                )

                if let detail {
                    Text(detail)
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .padding(AppSpacing.l)
        }
        .background(AppColor.neutralBackground)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

#if DEBUG
#Preview("NavigationPlaceholderView") {
    NavigationStack {
        NavigationPlaceholderView(
            title: "İş Emirleri",
            subtitle: "Faz 7 — navigation skeleton.",
            detail: "Gerçek liste Faz 9'da."
        )
    }
}
#endif
