import SwiftUI

/// Secondary action button. Same footprint as `PrimaryButton` but
/// rendered as an outlined pill on the surface color.
struct SecondaryButton: View {
    let title: String
    var systemImage: String?
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: AppSpacing.s) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(AppFont.buttonLabel)
                }
                Text(title)
                    .font(AppFont.buttonLabel)
            }
            .frame(maxWidth: .infinity)
            .frame(height: AppSpacing.minimumTouchTarget + AppSpacing.xs)
            .foregroundStyle(AppColor.brandPrimary.opacity(isEnabled ? 1.0 : 0.4))
            .background(
                RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous)
                    .fill(AppColor.brandSurface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous)
                    .strokeBorder(AppColor.brandPrimary.opacity(isEnabled ? 0.35 : 0.15), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(Text(title))
        .accessibilityAddTraits(.isButton)
    }
}

#if DEBUG
#Preview("SecondaryButton") {
    VStack(spacing: AppSpacing.l) {
        SecondaryButton(title: "Geri") {}
        SecondaryButton(title: "İptal", systemImage: "xmark") {}
        SecondaryButton(title: "Devre Dışı", isEnabled: false) {}
    }
    .padding(AppSpacing.l)
    .background(AppColor.neutralBackground)
}
#endif
