import SwiftUI

struct WorkOrderTimeStatusBadge: View {
    let status: WorkOrderTimeStatus
    var compact: Bool = true

    var body: some View {
        HStack(spacing: AppSpacing.xs) {
            Image(systemName: symbolName)
                .font(compact ? AppFont.label : AppFont.body)
            Text(status.displayName)
                .font(compact ? AppFont.label : AppFont.body)
        }
        .padding(.horizontal, compact ? AppSpacing.s : AppSpacing.m)
        .padding(.vertical, compact ? AppSpacing.xs : AppSpacing.s)
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
        .accessibilityLabel(Text("Zaman durumu: \(status.displayName)"))
    }

    private var symbolName: String {
        switch status {
        case .delayed: return "clock.badge.exclamationmark"
        case .windowPassed: return "clock.badge.exclamationmark"
        case .today: return "sun.max"
        case .approaching: return "clock"
        case .scheduled: return "calendar"
        }
    }
}

struct WorkOrderTimeStatusDetailBanner: View {
    let status: WorkOrderTimeStatus
    let plannedScheduleLabel: String

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.s) {
            WorkOrderTimeStatusBadge(status: status, compact: false)
            Text(status.detailMessage)
                .font(AppFont.caption)
                .foregroundStyle(AppColor.secondaryText)
            HStack(spacing: AppSpacing.xs) {
                Image(systemName: "calendar")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.secondaryText)
                Text(plannedScheduleLabel)
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.secondaryText)
            }
        }
        .padding(AppSpacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous)
                .fill(AppColor.elevatedSurface)
        )
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous)
                .fill(status.accentColor)
                .frame(width: 4)
        }
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous)
                .strokeBorder(AppColor.divider, lineWidth: 1)
        )
    }
}

#if DEBUG
#Preview("WorkOrderTimeStatusBadge") {
    VStack(alignment: .leading, spacing: AppSpacing.s) {
        ForEach(WorkOrderTimeStatus.allCases, id: \.self) { status in
            WorkOrderTimeStatusBadge(status: status)
        }
    }
    .padding(AppSpacing.l)
}
#endif
