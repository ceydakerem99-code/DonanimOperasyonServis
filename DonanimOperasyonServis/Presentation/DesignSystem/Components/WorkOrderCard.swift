import SwiftUI

/// Lightweight, presentation-only data structure passed into
/// ``WorkOrderCard``. Kept intentionally separate from any Domain
/// entity — Phase 2 will introduce the real `WorkOrder` and the
/// Presentation layer will map onto this struct at view boundaries.
struct WorkOrderCardData: Identifiable, Hashable {
    let id: String
    let workOrderNumber: String
    let customerName: String
    let workTypeLabel: String
    let deviceLabel: String?
    let status: AppStatus
    let priority: AppPriority
    let plannedDateLabel: String
    let plannedTimeLabel: String?
    let technicianName: String?
}

/// Card summarizing a work order for use inside lists and dashboards.
///
/// Purely visual — tapping is handled by the parent (the component
/// simply forwards a `onTap` closure). Renders header (WO number +
/// status), customer + work type, priority + planned schedule, and
/// assigned technician when present.
struct WorkOrderCard: View {
    let data: WorkOrderCardData
    var onTap: (() -> Void)?

    var body: some View {
        Button(action: { onTap?() }) {
            VStack(alignment: .leading, spacing: AppSpacing.m) {
                header
                Divider().background(AppColor.divider)
                customerSection
                Divider().background(AppColor.divider)
                footer
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
            .contentShape(RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(onTap == nil)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: AppSpacing.s) {
            Text(data.workOrderNumber)
                .font(AppFont.subtitle)
                .foregroundStyle(AppColor.primaryText)
            Spacer(minLength: 0)
            StatusChip(status: data.status)
        }
    }

    private var customerSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text(data.customerName)
                .font(AppFont.body)
                .foregroundStyle(AppColor.primaryText)
            HStack(spacing: AppSpacing.s) {
                Label(data.workTypeLabel, systemImage: "wrench.and.screwdriver")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.secondaryText)
                if let deviceLabel = data.deviceLabel {
                    Text("·")
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.secondaryText)
                    Label(deviceLabel, systemImage: "creditcard")
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.secondaryText)
                }
            }
        }
    }

    private var footer: some View {
        HStack(alignment: .center, spacing: AppSpacing.m) {
            PriorityBadge(priority: data.priority)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: AppSpacing.xs) {
                    Image(systemName: "calendar")
                        .font(AppFont.label)
                        .foregroundStyle(AppColor.secondaryText)
                    Text(data.plannedDateLabel)
                        .font(AppFont.label)
                        .foregroundStyle(AppColor.secondaryText)
                    if let plannedTimeLabel = data.plannedTimeLabel {
                        Text("·")
                            .font(AppFont.label)
                            .foregroundStyle(AppColor.secondaryText)
                        Text(plannedTimeLabel)
                            .font(AppFont.label)
                            .foregroundStyle(AppColor.secondaryText)
                    }
                }
                if let technicianName = data.technicianName {
                    HStack(spacing: AppSpacing.xs) {
                        Image(systemName: "person.crop.circle")
                            .font(AppFont.label)
                            .foregroundStyle(AppColor.secondaryText)
                        Text(technicianName)
                            .font(AppFont.label)
                            .foregroundStyle(AppColor.secondaryText)
                    }
                }
            }

            Spacer(minLength: 0)
        }
    }

    private var accessibilityLabel: Text {
        var text = "\(data.workOrderNumber), \(data.customerName), \(data.workTypeLabel), öncelik \(data.priority.displayName), durum \(data.status.displayName)"
        if let technicianName = data.technicianName {
            text += ", atanan teknisyen \(technicianName)"
        }
        return Text(text)
    }
}

#if DEBUG
#Preview("WorkOrderCard") {
    VStack(spacing: AppSpacing.m) {
        WorkOrderCard(
            data: WorkOrderCardData(
                id: "1",
                workOrderNumber: "WO-1024",
                customerName: "ABC Market - POS Arızası",
                workTypeLabel: "Arıza",
                deviceLabel: "POS",
                status: .assigned,
                priority: .urgent,
                plannedDateLabel: "18.08.2026",
                plannedTimeLabel: "10:30",
                technicianName: "Ahmet Yılmaz"
            ),
            onTap: {}
        )

        WorkOrderCard(
            data: WorkOrderCardData(
                id: "2",
                workOrderNumber: "WO-1025",
                customerName: "XYZ Mağaza - Yazıcı Kurulumu",
                workTypeLabel: "Kurulum",
                deviceLabel: "Yazıcı",
                status: .inProgress,
                priority: .normal,
                plannedDateLabel: "18.08.2026",
                plannedTimeLabel: "13:00",
                technicianName: "Mehmet Kaya"
            ),
            onTap: {}
        )

        WorkOrderCard(
            data: WorkOrderCardData(
                id: "3",
                workOrderNumber: "WO-1026",
                customerName: "DEF Market - Tablet Teslim",
                workTypeLabel: "Teslim",
                deviceLabel: nil,
                status: .completed,
                priority: .normal,
                plannedDateLabel: "17.08.2026",
                plannedTimeLabel: nil,
                technicianName: "Ali Demir"
            )
        )
    }
    .padding(AppSpacing.l)
    .background(AppColor.brandSurface)
}
#endif
