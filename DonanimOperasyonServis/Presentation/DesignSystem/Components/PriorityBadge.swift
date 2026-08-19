import SwiftUI

/// Small badge that shows a work-order priority with the corresponding
/// semantic color and glyph.
struct PriorityBadge: View {
    let priority: AppPriority
    var showsSymbol: Bool = true

    var body: some View {
        HStack(spacing: AppSpacing.xs) {
            if showsSymbol {
                Image(systemName: priority.symbolName)
                    .font(AppFont.label)
            }
            Text(priority.displayName)
                .font(AppFont.label)
        }
        .padding(.horizontal, AppSpacing.s)
        .padding(.vertical, AppSpacing.xs)
        .foregroundStyle(priority.accentColor)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.chip, style: .continuous)
                .fill(priority.accentColor.opacity(0.12))
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Öncelik: \(priority.displayName)"))
    }
}

#if DEBUG
#Preview("PriorityBadge") {
    VStack(alignment: .leading, spacing: AppSpacing.s) {
        ForEach(AppPriority.allCases, id: \.self) { priority in
            PriorityBadge(priority: priority)
        }
    }
    .padding(AppSpacing.l)
    .background(AppColor.neutralBackground)
}
#endif
