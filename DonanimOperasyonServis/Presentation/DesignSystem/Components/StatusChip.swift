import SwiftUI

/// Compact pill that surfaces a work-order status with a semantic
/// color and matching SF Symbol.
struct StatusChip: View {
    let status: AppStatus
    var showsSymbol: Bool = true

    var body: some View {
        HStack(spacing: AppSpacing.xs) {
            if showsSymbol {
                Image(systemName: status.symbolName)
                    .font(AppFont.label)
            }
            Text(status.displayName)
                .font(AppFont.label)
        }
        .padding(.horizontal, AppSpacing.s)
        .padding(.vertical, AppSpacing.xs)
        .foregroundStyle(status.accentColor)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.chip, style: .continuous)
                .fill(status.accentColor.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.chip, style: .continuous)
                .strokeBorder(status.accentColor.opacity(0.25), lineWidth: 0.5)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Durum: \(status.displayName)"))
    }
}

#if DEBUG
#Preview("StatusChip") {
    VStack(alignment: .leading, spacing: AppSpacing.s) {
        ForEach(AppStatus.allCases, id: \.self) { status in
            StatusChip(status: status)
        }
    }
    .padding(AppSpacing.l)
    .background(AppColor.neutralBackground)
}
#endif
