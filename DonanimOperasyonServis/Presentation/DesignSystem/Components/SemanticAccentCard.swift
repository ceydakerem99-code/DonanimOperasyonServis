import SwiftUI

// MARK: - Accent card modifier

struct SemanticAccentCardModifier: ViewModifier {
    let role: AppSemanticRole
    var minHeight: CGFloat?

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous)
                    .fill(AppColor.elevatedSurface)
            )
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous)
                    .fill(role.accentColor)
                    .frame(width: 4)
            }
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous)
                    .strokeBorder(AppColor.divider, lineWidth: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous)
                    .strokeBorder(role.accentColor.opacity(0.14), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.04), radius: 2, x: 0, y: 1)
    }
}

extension View {
    func semanticAccentCard(role: AppSemanticRole, minHeight: CGFloat? = nil) -> some View {
        modifier(SemanticAccentCardModifier(role: role, minHeight: minHeight))
    }
}

// MARK: - Metric / KPI card

struct SemanticMetricCard: View {
    let title: String
    let value: String
    var role: AppSemanticRole
    var systemImage: String?
    var minHeight: CGFloat? = 88
    var action: (() -> Void)?

    init(
        title: String,
        value: String,
        role: AppSemanticRole? = nil,
        systemImage: String? = nil,
        minHeight: CGFloat? = 88,
        action: (() -> Void)? = nil
    ) {
        self.title = title
        self.value = value
        self.role = role ?? AppSemanticRole.metricRole(forTitle: title)
        self.systemImage = systemImage
        self.minHeight = minHeight
        self.action = action
    }

    var body: some View {
        Group {
            if let action {
                Button(action: action) {
                    cardContent
                }
                .buttonStyle(.plain)
            } else {
                cardContent
            }
        }
    }

    private var cardContent: some View {
        HStack(alignment: .top, spacing: AppSpacing.s) {
            if let systemImage {
                iconBadge(systemImage)
            }
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text(title)
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.secondaryText)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(value)
                    .font(AppFont.title)
                    .foregroundStyle(AppColor.primaryText)
                    .lineLimit(3)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
        }
        .padding(AppSpacing.m)
        .semanticAccentCard(role: role, minHeight: minHeight)
    }

    private func iconBadge(_ name: String) -> some View {
        Image(systemName: name)
            .font(AppFont.caption)
            .foregroundStyle(role.accentColor)
            .frame(width: 32, height: 32)
            .background(
                RoundedRectangle(cornerRadius: AppRadius.chip, style: .continuous)
                    .fill(role.accentColor.opacity(0.12))
            )
    }
}

// MARK: - Report hub tile

struct ReportHubTile: View {
    let kind: AdminReportKind
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: AppSpacing.s) {
                Image(systemName: kind.systemImage)
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(kind.hubAccentRole.accentColor)
                    .frame(width: 40, height: 40)
                    .background(
                        RoundedRectangle(cornerRadius: AppRadius.chip, style: .continuous)
                            .fill(kind.hubAccentRole.accentColor.opacity(0.12))
                    )
                Text(kind.title)
                    .font(AppFont.subtitle)
                    .foregroundStyle(AppColor.primaryText)
                    .multilineTextAlignment(.leading)
                Text(kind.subtitle)
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.secondaryText)
                    .multilineTextAlignment(.leading)
                    .lineLimit(3)
            }
            .padding(AppSpacing.m)
            .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
            .semanticAccentCard(role: .neutral, minHeight: 120)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(kind.title)
        .accessibilityHint(kind.subtitle)
    }
}

#if DEBUG
#Preview("Semantic Metric Cards") {
    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: AppSpacing.m) {
        SemanticMetricCard(title: "Açık İşler", value: "12", systemImage: "doc.text")
        SemanticMetricCard(title: "Acil", value: "3", role: .urgent, systemImage: "exclamationmark.triangle.fill")
        SemanticMetricCard(title: "Geciken", value: "2", role: .overdue, systemImage: "clock.badge.exclamationmark")
        SemanticMetricCard(title: "Beklemede", value: "1", role: .paused, systemImage: "pause.circle")
    }
    .padding(AppSpacing.l)
    .background(AppColor.neutralBackground)
}
#endif
