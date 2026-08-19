import SwiftUI

/// Empty-state placeholder shown when a list, timeline, or search
/// result has no items. Composed of a symbol, title, description, and
/// an optional call-to-action button.
struct EmptyState<Action: View>: View {
    let systemImage: String
    let title: String
    var message: String?
    @ViewBuilder var action: () -> Action

    init(
        systemImage: String,
        title: String,
        message: String? = nil,
        @ViewBuilder action: @escaping () -> Action = { EmptyView() }
    ) {
        self.systemImage = systemImage
        self.title = title
        self.message = message
        self.action = action
    }

    var body: some View {
        VStack(spacing: AppSpacing.m) {
            Image(systemName: systemImage)
                .font(.system(size: 44, weight: .regular))
                .foregroundStyle(AppColor.brandPrimary.opacity(0.65))
                .padding(.bottom, AppSpacing.xs)

            Text(title)
                .font(AppFont.subtitle)
                .foregroundStyle(AppColor.primaryText)
                .multilineTextAlignment(.center)

            if let message {
                Text(message)
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.secondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, AppSpacing.l)
            }

            action()
                .padding(.top, AppSpacing.s)
        }
        .frame(maxWidth: .infinity)
        .padding(AppSpacing.xl)
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
#Preview("EmptyState") {
    VStack(spacing: AppSpacing.xxl) {
        EmptyState(
            systemImage: "tray",
            title: "Bugün atanmış iş yok",
            message: "Size yeni bir iş atandığında burada listelenecektir."
        )
        EmptyState(
            systemImage: "wifi.slash",
            title: "Bağlantı Yok",
            message: "İnternet bağlantısı olmadan yeni iş emri alınamıyor."
        ) {
            PrimaryButton(title: "Yenile") {}
        }
    }
    .padding(AppSpacing.l)
    .background(AppColor.neutralBackground)
}
#endif
