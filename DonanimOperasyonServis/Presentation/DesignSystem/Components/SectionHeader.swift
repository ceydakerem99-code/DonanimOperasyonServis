import SwiftUI

/// Section header used to introduce a group of rows or cards.
///
/// Supports an optional trailing accessory (typically a "Tümü" link or
/// small icon-only action).
struct SectionHeader<Trailing: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder let trailing: () -> Trailing

    init(
        title: String,
        subtitle: String? = nil,
        @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }
    ) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: AppSpacing.m) {
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text(title)
                    .font(AppFont.subtitle)
                    .foregroundStyle(AppColor.primaryText)
                if let subtitle {
                    Text(subtitle)
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.secondaryText)
                }
            }
            Spacer(minLength: 0)
            trailing()
        }
        .padding(.vertical, AppSpacing.xs)
    }
}

#if DEBUG
#Preview("SectionHeader") {
    VStack(alignment: .leading, spacing: AppSpacing.m) {
        SectionHeader(title: "Bugünkü İşler", subtitle: "18 Ağustos 2026, Pazartesi")
        SectionHeader(title: "Acil İşler") {
            Text("Tümü")
                .font(AppFont.label)
                .foregroundStyle(AppColor.brandPrimary)
        }
    }
    .padding(AppSpacing.l)
    .background(AppColor.neutralBackground)
}
#endif
