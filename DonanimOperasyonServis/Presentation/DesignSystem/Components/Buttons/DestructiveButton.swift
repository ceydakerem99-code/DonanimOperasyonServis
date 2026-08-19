import SwiftUI

/// Destructive action button. Reserved for irreversible or high-risk
/// operations such as rejecting an edit request or deleting a draft.
struct DestructiveButton: View {
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
            .foregroundStyle(AppColor.onPrimary)
            .background(
                RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous)
                    .fill(AppColor.danger.opacity(isEnabled ? 1.0 : 0.4))
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
#Preview("DestructiveButton") {
    VStack(spacing: AppSpacing.l) {
        DestructiveButton(title: "Reddet") {}
        DestructiveButton(title: "Sil", systemImage: "trash") {}
        DestructiveButton(title: "Devre Dışı", isEnabled: false) {}
    }
    .padding(AppSpacing.l)
    .background(AppColor.neutralBackground)
}
#endif
