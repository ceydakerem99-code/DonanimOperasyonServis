import SwiftUI

struct WorkOrderTemplateCard: View {
    let data: WorkOrderTemplateCardData
    var showsChevron = false
    var action: (() -> Void)?

    var body: some View {
        Button(action: { action?() }) {
            VStack(alignment: .leading, spacing: AppSpacing.s) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: AppSpacing.xs) {
                        Text(data.name)
                            .font(AppFont.subtitle)
                            .foregroundStyle(AppColor.primaryText)
                        if let summary = data.summary, !summary.isEmpty {
                            Text(summary)
                                .font(AppFont.caption)
                                .foregroundStyle(AppColor.secondaryText)
                                .lineLimit(2)
                        }
                    }
                    Spacer(minLength: 0)
                    if showsChevron {
                        Image(systemName: "chevron.right")
                            .font(AppFont.caption)
                            .foregroundStyle(AppColor.secondaryText)
                    }
                }

                HStack(spacing: AppSpacing.s) {
                    Label(data.deviceLabel, systemImage: "creditcard")
                    Text("·")
                    Label(data.workTypeLabel, systemImage: "wrench.and.screwdriver")
                    Spacer(minLength: 0)
                    PriorityBadge(priority: data.priority)
                }
                .font(AppFont.caption)
                .foregroundStyle(AppColor.secondaryText)
            }
            .padding(AppSpacing.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous)
                    .fill(AppColor.elevatedSurface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous)
                    .strokeBorder(AppColor.divider, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(action == nil)
    }
}

#if DEBUG
#Preview("WorkOrderTemplateCard") {
    WorkOrderTemplateCard(
        data: WorkOrderTemplateCardData(
            id: "1",
            name: "POS Bakım",
            summary: "Periyodik POS bakım işleri",
            workTypeLabel: "Bakım",
            deviceLabel: "POS",
            priority: .normal
        ),
        action: {}
    )
    .padding(AppSpacing.l)
}
#endif
