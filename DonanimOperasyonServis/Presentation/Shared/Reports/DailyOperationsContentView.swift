import SwiftUI

struct DailyOperationsContentView: View {
    enum Phase: Equatable {
        case loading
        case ready
        case empty
        case error(String)
    }

    let phase: Phase
    let showsLoadingIndicator: Bool
    let hasCachedContent: Bool
    let report: DailyOperationsReport?
    @Binding var selectedDay: Date
    var onPreviousDay: () -> Void
    var onNextDay: () -> Void
    var onReload: () -> Void
    var onSelectWorkOrder: ((WorkOrderID) -> Void)?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.l) {
                AsyncLoadContainerView(
                    isLoading: phase == .loading,
                    showsLoadingIndicator: showsLoadingIndicator,
                    hasCachedContent: hasCachedContent,
                    errorMessage: AsyncLoadPhaseParsing.errorMessage(phase),
                    isEmpty: phase == .empty,
                    loadingMessage: "Günlük operasyon raporu yükleniyor...",
                    errorTitle: "Rapor yüklenemedi",
                    onRetry: onReload,
                    content: {
                        dateSelectionSection
                        if let report {
                            kpiSection(report.kpis)
                            technicianSection(report.technicianSummaries)
                            customerSection(report.customerSummary)
                            workflowSection(report.workflowEntries)
                            delayedSection(report.delayedEntries)
                            pauseSection(report.pauseSummary)
                        }
                    },
                    empty: {
                        EmptyState(
                            systemImage: "calendar",
                            title: "Bu gün için kayıt yok",
                            message: "Seçilen günde planlanmış veya tamamlanmış iş emri bulunamadı."
                        )
                    }
                )
            }
            .padding(.horizontal, AppSpacing.l)
            .padding(.bottom, AppSpacing.xl)
        }
    }

    private var dateSelectionSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.m) {
            SectionHeader(title: "Gün Seçimi")
            HStack {
                Button(action: onPreviousDay) {
                    Image(systemName: "chevron.left")
                }
                .accessibilityLabel("Önceki gün")

                Spacer()

                DatePicker(
                    "",
                    selection: $selectedDay,
                    displayedComponents: .date
                )
                .labelsHidden()
                .datePickerStyle(.compact)

                Spacer()

                Button(action: onNextDay) {
                    Image(systemName: "chevron.right")
                }
                .accessibilityLabel("Sonraki gün")
            }
            .padding(AppSpacing.m)
            .background(RoundedRectangle(cornerRadius: AppRadius.card).fill(AppColor.elevatedSurface))

            Text("Tüm hesaplar seçilen günün yerel saat dilimine göre yapılır.")
                .font(AppFont.caption)
                .foregroundStyle(AppColor.secondaryText)
        }
    }

    private func kpiSection(_ kpis: DailyOperationsKPIs) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.m) {
            SectionHeader(title: "Günlük Özet")
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: AppSpacing.m) {
                SemanticMetricCard(title: "Açılan İşler", value: "\(kpis.openedCount)")
                SemanticMetricCard(title: "Tamamlanan İşler", value: "\(kpis.completedCount)")
                SemanticMetricCard(title: "Devam Eden İşler", value: "\(kpis.inProgressCount)")
                SemanticMetricCard(title: "Beklemede İşler", value: "\(kpis.pausedCount)")
                SemanticMetricCard(title: "Acil İşler", value: "\(kpis.urgentCount)")
                SemanticMetricCard(title: "Geciken İşler", value: "\(kpis.delayedCount)")
                SemanticMetricCard(title: "Reddedilen", value: "\(kpis.rejectedCount)", role: .error)
                SemanticMetricCard(title: "Tamamlanma Oranı", value: String(format: "%.0f%%", kpis.completionRate), role: .completed)
                SemanticMetricCard(title: "Aktif Teknisyen", value: "\(kpis.activeTechnicianCount)", role: .available)
                SemanticMetricCard(title: "Görev Alan Teknisyen", value: "\(kpis.assignedTechnicianCount)", role: .busy)
            }
        }
    }

    private func kpiCard(_ title: String, _ value: String) -> some View {
        SemanticMetricCard(title: title, value: value, minHeight: nil)
    }

    private func technicianSection(_ summaries: [DailyTechnicianSummary]) -> some View {
        listSection(title: "Teknisyen Günlük Özeti", empty: summaries.isEmpty) {
            ForEach(summaries) { tech in
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Text(tech.name)
                        .font(AppFont.subtitle)
                    Text("Atanan: \(tech.assignedCount) · Tamamlanan: \(tech.completedCount) · Devam: \(tech.inProgressCount) · Beklemede: \(tech.pausedCount)")
                        .font(AppFont.caption)
                    Text("Acil: \(tech.urgentCount) · Yüksek: \(tech.highCount) · Normal: \(tech.normalCount)")
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.secondaryText)
                    Text(String(format: "Tamamlanma: %.0f%%", tech.completionRate))
                        .font(AppFont.caption)
                    if let hours = tech.averageCompletionHours {
                        Text(String(format: "Ort. süre: %.1f sa", hours))
                            .font(AppFont.caption)
                            .foregroundStyle(AppColor.secondaryText)
                    }
                }
                .padding(AppSpacing.m)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: AppRadius.card).fill(AppColor.elevatedSurface))
            }
        }
    }

    private func customerSection(_ summary: DailyCustomerOperationSummary) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.m) {
            SectionHeader(title: "Müşteri / İşlem Özeti")
            kpiCard("Servis Verilen Müşteri", "\(summary.uniqueCustomerCount)")

            if !summary.workTypeCounts.isEmpty {
                Text("İş Türleri")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.secondaryText)
                ForEach(WorkType.allCases, id: \.self) { workType in
                    if let count = summary.workTypeCounts[workType], count > 0 {
                        HStack {
                            Text(workType.displayName)
                            Spacer()
                            Text("\(count)")
                        }
                        .font(AppFont.caption)
                    }
                }
            }

            if !summary.deviceCategoryCounts.isEmpty {
                Text("Cihaz Türleri")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.secondaryText)
                    .padding(.top, AppSpacing.s)
                ForEach(DeviceCategory.allCases, id: \.self) { category in
                    if let count = summary.deviceCategoryCounts[category], count > 0 {
                        HStack {
                            Text(category.displayName)
                            Spacer()
                            Text("\(count)")
                        }
                        .font(AppFont.caption)
                    }
                }
            }
        }
    }

    private func workflowSection(_ entries: [DailyWorkflowEntry]) -> some View {
        listSection(title: "Günlük İş Akışı", empty: entries.isEmpty) {
            ForEach(entries) { entry in
                Button {
                    onSelectWorkOrder?(entry.id)
                } label: {
                    HStack(alignment: .top, spacing: AppSpacing.m) {
                        Text(WorkOrderPresentationMapping.formatTime(entry.plannedTime))
                            .font(AppFont.monoDigits)
                            .foregroundStyle(AppColor.secondaryText)
                            .frame(width: 52, alignment: .leading)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.workOrderNumber)
                                .font(AppFont.subtitle)
                            Text("\(entry.customerName) · \(entry.technicianName)")
                                .font(AppFont.caption)
                            Text("\(entry.workType.displayName) · \(entry.priority.displayName)")
                                .font(AppFont.caption)
                                .foregroundStyle(AppColor.secondaryText)
                            StatusChip(status: WorkOrderPresentationMapping.appStatus(from: entry.status))
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(AppSpacing.m)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: AppRadius.card).fill(AppColor.elevatedSurface))
                }
                .buttonStyle(.plain)
                .disabled(onSelectWorkOrder == nil)
            }
        }
    }

    private func delayedSection(_ entries: [DailyDelayedEntry]) -> some View {
        listSection(title: "Geciken İşler", empty: entries.isEmpty) {
            Text("\(entries.count) geciken iş")
                .font(AppFont.caption)
                .foregroundStyle(AppColor.secondaryText)
            ForEach(entries) { entry in
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Text(entry.workOrderNumber)
                        .font(AppFont.subtitle)
                    Text("\(entry.customerName) · \(entry.technicianName)")
                        .font(AppFont.caption)
                }
                .padding(AppSpacing.m)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: AppRadius.card).fill(AppColor.elevatedSurface))
            }
        }
    }

    private func pauseSection(_ summary: DailyPauseSummary) -> some View {
        listSection(title: "Bekleme Özeti", empty: summary.pausedCount == 0) {
            Text("\(summary.pausedCount) bekleme kaydı")
                .font(AppFont.caption)
            if let average = summary.averagePauseDurationSeconds {
                Text("Ortalama bekleme: \(formatDuration(average))")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.secondaryText)
            }
            ForEach(PauseReason.allCases, id: \.self) { reason in
                if let count = summary.reasonCounts[reason], count > 0 {
                    HStack {
                        Text(reason.displayName)
                        Spacer()
                        Text("\(count)")
                    }
                    .font(AppFont.caption)
                }
            }
            ForEach(summary.entries) { entry in
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Text(entry.workOrderNumber)
                        .font(AppFont.subtitle)
                    Text(entry.subtitle)
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.secondaryText)
                }
                .padding(AppSpacing.m)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: AppRadius.card).fill(AppColor.elevatedSurface))
            }
        }
    }

    @ViewBuilder
    private func listSection<Content: View>(
        title: String,
        empty: Bool,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.m) {
            SectionHeader(title: title)
            if empty {
                Text("Kayıt yok")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.secondaryText)
            } else {
                content()
            }
        }
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds / 3600)
        let minutes = Int(seconds.truncatingRemainder(dividingBy: 3600) / 60)
        if hours > 0 { return "\(hours) sa \(minutes) dk" }
        return "\(minutes) dk"
    }
}

#if DEBUG
#Preview("Daily Operations") {
    DailyOperationsContentView(
        phase: .ready,
        showsLoadingIndicator: false,
        hasCachedContent: true,
        report: DailyOperationsReportViewModel.previewReady().report,
        selectedDay: .constant(AdminPreviewData.referenceDate),
        onPreviousDay: {},
        onNextDay: {},
        onReload: {},
        onSelectWorkOrder: nil
    )
}
#endif
