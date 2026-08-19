import SwiftUI

/// Primary call-to-action button.
///
/// Full-width, 48 pt tall, brand-primary background. Supports `isLoading`
/// to display a spinner while the action is in-flight (also disables input).
struct PrimaryButton: View {
    let title: String
    var systemImage: String?
    var isLoading: Bool = false
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: AppSpacing.s) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(AppColor.onPrimary)
                } else if let systemImage {
                    Image(systemName: systemImage)
                        .font(AppFont.buttonLabel)
                }
                Text(title)
                    .font(AppFont.buttonLabel)
            }
            .frame(maxWidth: .infinity)
            .frame(height: AppSpacing.minimumTouchTarget + AppSpacing.xs)
            .foregroundStyle(AppColor.onPrimary)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled || isLoading)
        .accessibilityLabel(Text(title))
        .accessibilityAddTraits(.isButton)
    }

    private var background: some View {
        RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous)
            .fill(AppColor.brandPrimary.opacity(isEnabled ? 1.0 : 0.4))
    }
}

#if DEBUG
#Preview("PrimaryButton") {
    VStack(spacing: AppSpacing.l) {
        PrimaryButton(title: "Devam Et") {}
        PrimaryButton(title: "Kaydediliyor", isLoading: true) {}
        PrimaryButton(title: "Devre Dışı", isEnabled: false) {}
        PrimaryButton(title: "Yola Çık", systemImage: "car.fill") {}
    }
    .padding(AppSpacing.l)
    .background(AppColor.neutralBackground)
}
#endif
