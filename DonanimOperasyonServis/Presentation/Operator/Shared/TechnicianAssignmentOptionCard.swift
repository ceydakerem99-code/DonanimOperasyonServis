import SwiftUI

struct RecommendedTechnicianBadge: View {
    var body: some View {
        HStack(spacing: AppSpacing.xs) {
            Image(systemName: "star.fill")
                .font(AppFont.label)
            Text("Önerilen")
                .font(AppFont.label)
        }
        .padding(.horizontal, AppSpacing.s)
        .padding(.vertical, AppSpacing.xs)
        .foregroundStyle(AppColor.brandPrimary)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.chip, style: .continuous)
                .fill(AppColor.brandPrimary.opacity(0.12))
        )
        .accessibilityLabel(Text("Önerilen teknisyen"))
    }
}

struct TechnicianAssignmentOptionCard: View {
    let title: String
    let workingStatus: TechnicianWorkingStatus
    let workload: TechnicianWorkloadCounts
    let isRecommended: Bool
    let isSelected: Bool
    var isDisabled = false
    var locationLabel: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: AppSpacing.m) {
                Image(systemName: "person.crop.circle")
                    .foregroundStyle(isSelected ? AppColor.onPrimary : workingStatus.semanticRole.accentColor)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    HStack(spacing: AppSpacing.s) {
                        Text(title)
                            .font(AppFont.body)
                            .foregroundStyle(isSelected ? AppColor.onPrimary : AppColor.primaryText)
                            .lineLimit(1)
                        if isRecommended {
                            recommendedBadge
                        }
                    }

                    Text("\(workingStatus.displayName) · \(workload.compactSummary)")
                        .font(AppFont.caption)
                        .foregroundStyle(isSelected ? AppColor.onPrimary.opacity(0.85) : AppColor.secondaryText)
                        .lineLimit(2)

                    if let locationLabel, !locationLabel.isEmpty {
                        Text(locationLabel)
                            .font(AppFont.caption)
                            .foregroundStyle(isSelected ? AppColor.onPrimary.opacity(0.85) : AppColor.secondaryText)
                    }
                }

                Spacer(minLength: 0)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? AppColor.onPrimary : AppColor.secondaryText)
            }
            .padding(AppSpacing.m)
            .background(
                RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous)
                    .fill(isSelected ? AppColor.brandPrimary : AppColor.elevatedSurface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous)
                    .strokeBorder(
                        isRecommended && !isSelected ? AppColor.brandPrimary.opacity(0.35) : AppColor.divider,
                        lineWidth: isRecommended && !isSelected ? 1.5 : 1
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }

    private var recommendedBadge: some View {
        HStack(spacing: AppSpacing.xs) {
            Image(systemName: "star.fill")
                .font(AppFont.label)
            Text("Önerilen")
                .font(AppFont.label)
        }
        .padding(.horizontal, AppSpacing.s)
        .padding(.vertical, AppSpacing.xs)
        .foregroundStyle(isSelected ? AppColor.onPrimary : AppColor.brandPrimary)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.chip, style: .continuous)
                .fill(isSelected ? AppColor.onPrimary.opacity(0.18) : AppColor.brandPrimary.opacity(0.12))
        )
        .accessibilityLabel(Text("Önerilen teknisyen"))
    }
}

#if DEBUG
#Preview("Technician Assignment Option") {
    VStack(spacing: AppSpacing.m) {
        TechnicianAssignmentOptionCard(
            title: "Mehmet Kerem",
            workingStatus: .available,
            workload: TechnicianWorkloadCounts(urgent: 0, high: 1, normal: 2, activeTotal: 3),
            isRecommended: true,
            isSelected: false,
            action: {}
        )
        TechnicianAssignmentOptionCard(
            title: "Ayşe Demir",
            workingStatus: .busy,
            workload: TechnicianWorkloadCounts(urgent: 1, high: 0, normal: 1, activeTotal: 2),
            isRecommended: false,
            isSelected: true,
            action: {}
        )
    }
    .padding(AppSpacing.l)
}
#endif
