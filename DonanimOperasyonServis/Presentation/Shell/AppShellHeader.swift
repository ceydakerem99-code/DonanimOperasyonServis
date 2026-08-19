import SwiftUI

/// Shared top chrome for every role shell. Keeps auth profile context
/// visible without mixing navigation state into `AuthSessionController`.
struct AppShellHeader: View {
    let title: String
    let userName: String

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text(title)
                .font(AppFont.title)
                .foregroundStyle(AppColor.primaryText)
                .accessibilityAddTraits(.isHeader)
            Text(userName)
                .font(AppFont.caption)
                .foregroundStyle(AppColor.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, AppSpacing.l)
        .padding(.top, AppSpacing.m)
        .padding(.bottom, AppSpacing.s)
        .background(AppColor.neutralBackground)
    }
}
