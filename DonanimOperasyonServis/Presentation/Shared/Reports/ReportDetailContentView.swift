import SwiftUI
import Charts

struct ReportDetailContentView: View {
    let kind: AdminReportKind
    let phase: AdminReportDetailViewModel.Phase
    let showsLoadingIndicator: Bool
    let hasCachedContent: Bool
    let payload: ReportDetailPayload
    @Binding var reportSearchText: String
    let mediaLoader: WorkOrderMediaLoader
    var onSelectWorkOrder: ((WorkOrderID) -> Void)?
    var onReload: () -> Void
    var isSelectionMode = false
    var selectedOrderIDs: Set<WorkOrderID> = []
    var canSelectWorkOrder: ((WorkOrderID) -> Bool)? = nil
    var onToggleWorkOrderSelection: ((WorkOrderID) -> Void)? = nil
    var selectionSummaryText: String? = nil
    var onSelectAllEligible: (() -> Void)? = nil
    var onClearSelection: (() -> Void)? = nil

    @State private var selectedSignature: SignatureReportEntry?
    @State private var selectedPhoto: PhotoReportEntry?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.l) {
                AsyncLoadContainerView(
                    isLoading: phase == .loading,
                    showsLoadingIndicator: showsLoadingIndicator,
                    hasCachedContent: hasCachedContent,
                    errorMessage: AsyncLoadPhaseParsing.errorMessage(phase),
                    isEmpty: phase == .empty,
                    loadingMessage: "Rapor yükleniyor...",
                    errorTitle: "Rapor yüklenemedi",
                    onRetry: onReload,
                    content: { loadedContent },
                    empty: {
                        EmptyState(
                            systemImage: kind.systemImage,
                            title: "Rapor verisi yok",
                            message: emptyMessage
                        )
                    }
                )
            }
            .padding(.horizontal, AppSpacing.l)
            .padding(.bottom, AppSpacing.xl)
        }
        .sheet(item: $selectedSignature) { entry in
            ReportMediaPreviewSheet(
                title: entry.displayTitle,
                subtitle: entry.subtitle,
                signature: entry.signature,
                photo: nil,
                mediaLoader: mediaLoader
            )
        }
        .sheet(item: $selectedPhoto) { entry in
            ReportMediaPreviewSheet(
                title: entry.categoryLabel,
                subtitle: entry.subtitle,
                signature: nil,
                photo: entry.photo,
                mediaLoader: mediaLoader
            )
        }
    }

    @ViewBuilder
    private var loadedContent: some View {
        if !payload.metrics.isEmpty, kind != .signatures, kind != .photos, kind != .technicianPerformance {
            metricsSection
        }

        if kind != .customerAnalytics, kind != .customerSatisfaction, kind != .faultRecurrence, kind != .dailyOperations {
            searchSection
        }

        switch kind {
        case .workOrders:
            if !payload.statusBreakdown.isEmpty {
                statusBreakdownSection
            }
            if isSelectionMode, let selectionSummaryText {
                selectionToolbar(summary: selectionSummaryText)
            }
            workOrderListSection

        case .technicianPerformance:
            if !filteredTechnicians.isEmpty {
                technicianPerformanceChartSection
            }
            technicianListSection

        case .pauseReasons:
            pauseListSection

        case .signatures:
            if !payload.metrics.isEmpty {
                metricsSection
            }
            signatureListSection

        case .photos:
            if !payload.metrics.isEmpty {
                metricsSection
            }
            photoGridSection

        case .customerAnalytics:
            EmptyView()

        case .customerSatisfaction:
            EmptyView()

        case .faultRecurrence:
            EmptyView()

        case .dailyOperations:
            EmptyView()
        }
    }

    private var emptyMessage: String {
        switch kind {
        case .signatures: return "Tamamlanan iş emirlerine ait imza kaydı bulunamadı."
        case .photos: return "Yüklenmiş fotoğraf kaydı bulunamadı."
        case .pauseReasons: return "Bekleme kaydı bulunamadı."
        default: return "İş emri verileri eklendiğinde rapor burada görünecek."
        }
    }

    private var searchPlaceholder: String {
        switch kind {
        case .workOrders: return "İş emri ara..."
        case .technicianPerformance: return "Teknisyen ara..."
        case .pauseReasons: return "Bekleme kaydı ara..."
        case .signatures: return "İmza raporu ara..."
        case .photos: return "Fotoğraf raporu ara..."
        case .customerAnalytics: return "Müşteri ara..."
        case .customerSatisfaction: return "Değerlendirme ara..."
        case .faultRecurrence: return "Arıza tekrarı ara..."
        case .dailyOperations: return "Günlük rapor ara..."
        }
    }

    private var searchSection: some View {
        TextField(searchPlaceholder, text: $reportSearchText)
            .padding(AppSpacing.m)
            .background(RoundedRectangle(cornerRadius: AppRadius.card).fill(AppColor.elevatedSurface))
    }

    private var metricsSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.m) {
            SectionHeader(title: "Özet Metrikler")
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: AppSpacing.m) {
                ForEach(payload.metrics) { metric in
                    SemanticMetricCard(
                        title: metric.title,
                        value: metric.value,
                        role: AppSemanticRole.metricRole(forTitle: metric.title),
                        minHeight: nil
                    )
                }
            }
        }
    }

    private var statusBreakdownSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.m) {
            SectionHeader(title: "Durum Dağılımı")
            ForEach(payload.statusBreakdown) { item in
                let appStatus = WorkOrderPresentationMapping.appStatus(from: item.status)
                let barColor = appStatus.accentColor
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    HStack {
                        StatusChip(status: appStatus)
                        Spacer()
                        Text("\(item.count) · \(String(format: "%.0f%%", item.percentage))")
                            .font(AppFont.caption)
                            .foregroundStyle(AppColor.secondaryText)
                    }
                    GeometryReader { geo in
                        RoundedRectangle(cornerRadius: 4)
                            .fill(barColor.opacity(0.2))
                            .overlay(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(barColor)
                                    .frame(width: geo.size.width * item.percentage / 100)
                            }
                    }
                    .frame(height: 8)
                }
                .padding(AppSpacing.m)
                .semanticAccentCard(role: .neutral, minHeight: nil)
            }
        }
    }

    private var workOrderListSection: some View {
        listSection(
            title: "İş Emirleri",
            isEmpty: filteredWorkOrders.isEmpty,
            hasData: !payload.workOrderEntries.isEmpty
        ) {
            ForEach(filteredWorkOrders) { entry in
                if isSelectionMode {
                    HStack(alignment: .top, spacing: AppSpacing.s) {
                        workOrderSelectionCheckbox(for: entry.id)
                        Button {
                            onToggleWorkOrderSelection?(entry.id)
                        } label: {
                            WorkOrderReportCard(entry: entry)
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    Button {
                        onSelectWorkOrder?(entry.id)
                    } label: {
                        WorkOrderReportCard(entry: entry)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func workOrderSelectionCheckbox(for orderId: WorkOrderID) -> some View {
        let selectable = canSelectWorkOrder?(orderId) ?? false
        let selected = selectedOrderIDs.contains(orderId)
        return Button {
            onToggleWorkOrderSelection?(orderId)
        } label: {
            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(
                    selectable
                        ? (selected ? AppColor.brandPrimary : AppColor.secondaryText)
                        : AppColor.divider
                )
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .disabled(!selectable)
        .padding(.top, AppSpacing.m)
        .accessibilityLabel(selected ? "Seçili" : "Seçili değil")
    }

    private func selectionToolbar(summary: String) -> some View {
        HStack {
            Text(summary)
                .font(AppFont.label)
                .foregroundStyle(AppColor.primaryText)
            Spacer()
            Button("Tümünü Seç") {
                onSelectAllEligible?()
            }
            .font(AppFont.label)
            .foregroundStyle(AppColor.brandPrimary)
            Button("Temizle") {
                onClearSelection?()
            }
            .font(AppFont.label)
            .foregroundStyle(AppColor.brandPrimary)
            .disabled(selectedOrderIDs.isEmpty)
        }
        .padding(.vertical, AppSpacing.xs)
    }

    private var technicianPerformanceChartSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.m) {
            SectionHeader(title: "Tamamlanma Oranı")
            Chart(filteredTechnicians) { entry in
                BarMark(
                    x: .value("Oran", entry.completionRate),
                    y: .value("Teknisyen", entry.name)
                )
                .foregroundStyle(AppColor.brandPrimary.gradient)
                .annotation(position: .trailing) {
                    Text(String(format: "%.0f%%", entry.completionRate))
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.secondaryText)
                }
            }
            .chartXScale(domain: 0...100)
            .chartXAxis {
                AxisMarks(values: [0, 25, 50, 75, 100]) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let percent = value.as(Int.self) {
                            Text("\(percent)%")
                                .font(AppFont.caption)
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks { _ in
                    AxisValueLabel()
                        .font(AppFont.caption)
                }
            }
            .frame(minHeight: max(180, CGFloat(filteredTechnicians.count) * 44))
            .padding(AppSpacing.m)
            .background(RoundedRectangle(cornerRadius: AppRadius.card).fill(AppColor.elevatedSurface))
        }
    }

    private var technicianListSection: some View {
        listSection(
            title: "Teknisyen Performansı",
            isEmpty: filteredTechnicians.isEmpty,
            hasData: !payload.technicianEntries.isEmpty
        ) {
            ForEach(filteredTechnicians) { entry in
                VStack(alignment: .leading, spacing: AppSpacing.m) {
                    Text(entry.name)
                        .font(AppFont.subtitle)
                        .foregroundStyle(AppColor.primaryText)

                    HStack(spacing: AppSpacing.l) {
                        technicianMetricColumn(title: "Toplam", value: "\(entry.totalAssigned)")
                        technicianMetricColumn(title: "Tamamlanan", value: "\(entry.completed)")
                        technicianMetricColumn(
                            title: "Oran",
                            value: String(format: "%.0f%%", entry.completionRate)
                        )
                    }

                    VStack(alignment: .leading, spacing: AppSpacing.xs) {
                        HStack {
                            Text("Tamamlanma")
                                .font(AppFont.caption)
                                .foregroundStyle(AppColor.secondaryText)
                            Spacer()
                            Text(String(format: "%.0f%%", entry.completionRate))
                                .font(AppFont.caption)
                                .foregroundStyle(AppColor.primaryText)
                        }
                        ProgressView(value: entry.completionRate, total: 100)
                            .tint(AppColor.brandPrimary)
                    }

                    Text(entry.statusSummary)
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.secondaryText)
                }
                .padding(AppSpacing.m)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: AppRadius.card).fill(AppColor.elevatedSurface))
                .overlay(
                    RoundedRectangle(cornerRadius: AppRadius.card)
                        .strokeBorder(AppColor.divider, lineWidth: 1)
                )
            }
        }
    }

    private func technicianMetricColumn(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text(title)
                .font(AppFont.caption)
                .foregroundStyle(AppColor.secondaryText)
            Text(value)
                .font(AppFont.subtitle)
                .foregroundStyle(AppColor.primaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var pauseListSection: some View {
        listSection(
            title: "Bekleme Kayıtları",
            isEmpty: filteredPauses.isEmpty,
            hasData: !payload.pauseEntries.isEmpty
        ) {
            ForEach(filteredPauses) { entry in
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Text(entry.pauseReason.displayName)
                        .font(AppFont.subtitle)
                        .foregroundStyle(AppColor.primaryText)
                    Text(entry.subtitle)
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.secondaryText)
                        .multilineTextAlignment(.leading)
                }
                .padding(AppSpacing.m)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: AppRadius.card).fill(AppColor.elevatedSurface))
            }
        }
    }

    private var signatureListSection: some View {
        listSection(
            title: "İmza Kayıtları",
            isEmpty: filteredSignatures.isEmpty,
            hasData: !payload.signatureEntries.isEmpty
        ) {
            ForEach(filteredSignatures) { entry in
                Button {
                    selectedSignature = entry
                } label: {
                    HStack(alignment: .top, spacing: AppSpacing.m) {
                        DetailSignatureThumbnail(signature: entry.signature, mediaLoader: mediaLoader)
                        VStack(alignment: .leading, spacing: AppSpacing.xs) {
                            Text(entry.displayTitle)
                                .font(AppFont.subtitle)
                                .foregroundStyle(AppColor.primaryText)
                            Text(entry.subtitle)
                                .font(AppFont.caption)
                                .foregroundStyle(AppColor.secondaryText)
                                .multilineTextAlignment(.leading)
                        }
                    }
                    .padding(AppSpacing.m)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: AppRadius.card).fill(AppColor.elevatedSurface))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var photoGridSection: some View {
        listSection(
            title: "Fotoğraf Kayıtları",
            isEmpty: filteredPhotos.isEmpty,
            hasData: !payload.photoEntries.isEmpty
        ) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: AppSpacing.m) {
                ForEach(filteredPhotos) { entry in
                    Button {
                        selectedPhoto = entry
                    } label: {
                        VStack(alignment: .leading, spacing: AppSpacing.xs) {
                            DetailPhotoThumbnail(photo: entry.photo, mediaLoader: mediaLoader)
                            Text(entry.workOrderNumber)
                                .font(AppFont.caption)
                                .foregroundStyle(AppColor.primaryText)
                            Text(entry.subtitle)
                                .font(AppFont.caption)
                                .foregroundStyle(AppColor.secondaryText)
                                .lineLimit(3)
                                .multilineTextAlignment(.leading)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private func listSection<Content: View>(
        title: String,
        isEmpty: Bool,
        hasData: Bool,
        @ViewBuilder content: () -> Content
    ) -> some View {
        if isEmpty {
            if hasData {
                EmptyState(
                    systemImage: "magnifyingglass",
                    title: "Sonuç bulunamadı",
                    message: "Arama kriterlerinize uygun kayıt bulunamadı."
                )
            }
        } else {
            VStack(alignment: .leading, spacing: AppSpacing.m) {
                SectionHeader(title: title)
                content()
            }
        }
    }

    private var filteredWorkOrders: [WorkOrderReportEntry] {
        ReportSearchFilters.filterWorkOrders(payload.workOrderEntries, query: reportSearchText)
    }

    private var filteredSignatures: [SignatureReportEntry] {
        ReportSearchFilters.filterSignatures(payload.signatureEntries, query: reportSearchText)
    }

    private var filteredPhotos: [PhotoReportEntry] {
        ReportSearchFilters.filterPhotos(payload.photoEntries, query: reportSearchText)
    }

    private var filteredPauses: [PauseReportEntry] {
        ReportSearchFilters.filterPauses(payload.pauseEntries, query: reportSearchText)
    }

    private var filteredTechnicians: [TechnicianPerformanceEntry] {
        ReportSearchFilters.filterTechnicians(payload.technicianEntries, query: reportSearchText)
    }
}

private struct WorkOrderReportCard: View {
    let entry: WorkOrderReportEntry

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.s) {
            HStack(alignment: .top) {
                Text(entry.workOrderNumber)
                    .font(AppFont.subtitle)
                    .foregroundStyle(AppColor.primaryText)
                Spacer()
                PriorityBadge(priority: WorkOrderPresentationMapping.appPriority(from: entry.priority))
            }
            Text(entry.customerName)
                .font(AppFont.body)
                .foregroundStyle(AppColor.primaryText)
            Text(entry.workplace)
                .font(AppFont.caption)
                .foregroundStyle(AppColor.secondaryText)
            HStack {
                Text(entry.technicianName)
                Spacer()
                StatusChip(status: WorkOrderPresentationMapping.appStatus(from: entry.status))
            }
            .font(AppFont.caption)
            .foregroundStyle(AppColor.secondaryText)
            Text(
                [
                    WorkOrderPresentationMapping.formatDate(entry.scheduledDate),
                    entry.deviceLabel,
                    entry.workType.displayName,
                    entry.signatureStatusLabel,
                    entry.photoCount > 0 ? "Fotoğraf: \(entry.photoCount)" : nil
                ].compactMap { $0 }.joined(separator: " · ")
            )
            .font(AppFont.caption)
            .foregroundStyle(AppColor.secondaryText)
            .multilineTextAlignment(.leading)
            Image(systemName: "chevron.right")
                .font(AppFont.label)
                .foregroundStyle(AppColor.secondaryText)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(AppSpacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: AppRadius.card).fill(AppColor.elevatedSurface))
    }
}

struct ReportMediaPreviewSheet: View {
    let title: String
    let subtitle: String
    let signature: Signature?
    let photo: WorkOrderPhoto?
    let mediaLoader: WorkOrderMediaLoader

    @Environment(\.dismiss) private var dismiss
    @State private var imageData: Data?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.l) {
                    Group {
                        if let imageData, let image = UIImage(data: imageData) {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: .infinity)
                        } else {
                            ProgressView("Önizleme yükleniyor...")
                                .frame(maxWidth: .infinity, minHeight: 200)
                        }
                    }
                    .background(AppColor.neutralBackground)
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.card))

                    Text(subtitle)
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.secondaryText)
                }
                .padding(AppSpacing.l)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Kapat") { dismiss() }
                }
            }
            .task(id: taskId) {
                if let signature {
                    imageData = await mediaLoader.loadSignature(signature)
                } else if let photo {
                    imageData = await mediaLoader.loadPhoto(photo)
                }
            }
        }
    }

    private var taskId: String {
        signature?.id ?? photo?.id ?? title
    }
}

#if DEBUG
#Preview("Work Order Report Card") {
    WorkOrderReportCard(
        entry: WorkOrderReportEntry(
            id: WorkOrderID("wo-preview"),
            workOrderNumber: "WO-741970",
            customerName: "Ceka",
            workplace: "Ceka · Çorum",
            technicianName: "Mehmet Kerem",
            priority: .urgent,
            status: .assigned,
            scheduledDate: AdminPreviewData.referenceDate,
            deviceLabel: "POS · Ingenico",
            workType: .repair,
            signatureStatusLabel: "İmzasız",
            photoCount: 2
        )
    )
    .padding()
}
#endif
