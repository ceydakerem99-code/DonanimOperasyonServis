import SwiftUI

/// Tappable profile row that navigates to an account setting screen.
struct ProfileNavigationRow: View {
    let title: String
    let systemImage: String

    var body: some View {
        HStack {
            Image(systemName: systemImage)
                .foregroundStyle(AppColor.brandPrimary)
                .frame(width: 24)
            Text(title)
                .font(AppFont.body)
                .foregroundStyle(AppColor.primaryText)
            Spacer()
            Image(systemName: "chevron.right")
                .font(AppFont.label)
                .foregroundStyle(AppColor.secondaryText)
        }
        .frame(minHeight: AppSpacing.minimumTouchTarget)
        .contentShape(Rectangle())
    }
}
