import SwiftUI

/// Shared profile account actions. Unsupported features are clearly marked.
enum ProfileUnsupportedFeature {
    static let badge = "Yakında"
}

struct ProfileUnsupportedRow: View {
    let title: String
    let systemImage: String
    var value: String? = nil

    var body: some View {
        HStack {
            Image(systemName: systemImage)
                .foregroundStyle(AppColor.secondaryText)
                .frame(width: 24)
            Text(title)
                .font(AppFont.body)
                .foregroundStyle(AppColor.secondaryText)
            Spacer()
            if let value {
                Text(value)
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.secondaryText)
            }
            Text(ProfileUnsupportedFeature.badge)
                .font(AppFont.label)
                .foregroundStyle(AppColor.secondaryText)
                .padding(.horizontal, AppSpacing.s)
                .padding(.vertical, AppSpacing.xs)
                .background(Capsule().fill(AppColor.divider.opacity(0.6)))
        }
        .frame(minHeight: AppSpacing.minimumTouchTarget)
        .accessibilityLabel("\(title), \(ProfileUnsupportedFeature.badge)")
    }
}
