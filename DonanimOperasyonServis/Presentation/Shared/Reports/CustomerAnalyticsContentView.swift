import SwiftUI

struct CustomerAnalyticsContentView: View {
    enum Phase: Equatable {
        case loading
        case ready
        case empty
        case error(String)
    }

    let phase: Phase
    let showsLoadingIndicator: Bool
    let hasCachedContent: Bool
    let summary: CustomerAnalyticsSummary?
    let filteredCustomers: [Customer]
    let customerPickerCards: [CustomerAnalyticsPickerCard]
    @Binding var customerSearchText: String
    let technicianHistory: [CustomerTechnicianVisitEntry]
    let operationHistory: [CustomerOperationEntry]
    let deviceHistory: [CustomerDeviceEntry]
    let timeline: [CustomerTimelineEntry]
    var onSelectCustomer: (Customer) -> Void
    var onClearSelection: () -> Void
    var onReload: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.l) {
                AsyncLoadContainerView(
                    isLoading: phase == .loading,
                    showsLoadingIndicator: showsLoadingIndicator,
                    hasCachedContent: hasCachedContent,
                    errorMessage: AsyncLoadPhaseParsing.errorMessage(phase),
                    isEmpty: phase == .empty,
                    loadingMessage: "Müşteri analizi yükleniyor...",
                    errorTitle: "Analiz yüklenemedi",
                    onRetry: onReload,
                    content: {
                        if summary == nil {
                            customerSearchSection
                            customerPickerSection
                        } else if let summary {
                            summarySection(summary)
                            technicianSection
                            operationSection
                            deviceSection
                            timelineSection
                        }
                    },
                    empty: {
                        EmptyState(
                            systemImage: "chart.line.uptrend.xyaxis",
                            title: "Müşteri bulunamadı",
                            message: "Analiz için kayıtlı müşteri gerekir."
                        )
                    }
                )
            }
            .padding(.horizontal, AppSpacing.l)
            .padding(.bottom, AppSpacing.xl)
        }
    }

    private var customerSearchSection: some View {
        TextField("Müşteri adı, iş yeri veya kod...", text: $customerSearchText)
            .padding(AppSpacing.m)
            .background(RoundedRectangle(cornerRadius: AppRadius.card).fill(AppColor.elevatedSurface))
    }

    private var customerPickerSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.m) {
            SectionHeader(title: "Müşteri Seçin")
            if customerPickerCards.isEmpty {
                EmptyState(
                    systemImage: "magnifyingglass",
                    title: "Sonuç bulunamadı",
                    message: "Arama kriterlerinize uygun müşteri bulunamadı."
                )
            } else {
                ForEach(Array(customerPickerCards.enumerated()), id: \.element.id) { index, card in
                    Button {
                        onSelectCustomer(card.customer)
                    } label: {
                        VStack(alignment: .leading, spacing: AppSpacing.s) {
                            Text(card.customer.name)
                                .font(AppFont.subtitle)
                                .foregroundStyle(AppColor.primaryText)
                            Text(card.workplace)
                                .font(AppFont.caption)
                                .foregroundStyle(AppColor.secondaryText)
                            HStack {
                                Text("Toplam ziyaret: \(card.totalVisits)")
                                    .font(AppFont.caption)
                                    .foregroundStyle(AppColor.secondaryText)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(AppFont.label)
                                    .foregroundStyle(AppColor.secondaryText)
                            }
                            Text(card.shortSummary)
                                .font(AppFont.caption)
                                .foregroundStyle(AppColor.secondaryText)
                                .lineLimit(2)
                        }
                        .padding(AppSpacing.m)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: AppRadius.card)
                                .fill(AppColor.elevatedSurface)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: AppRadius.card)
                                .stroke(AppColor.divider, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, index < customerPickerCards.count - 1 ? AppSpacing.xs : 0)
                }
            }
        }
    }

    private func summarySection(_ summary: CustomerAnalyticsSummary) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.m) {
            SectionHeader(title: "Genel Özet")
            VStack(alignment: .leading, spacing: AppSpacing.s) {
                Text(summary.customerName)
                    .font(AppFont.title)
                    .foregroundStyle(AppColor.primaryText)
                Text(summary.workplace)
                    .font(AppFont.body)
                    .foregroundStyle(AppColor.secondaryText)
                metricRow("Toplam Ziyaret", "\(summary.totalVisits)")
                metricRow("Tamamlanan Ziyaret", "\(summary.completedVisits)")
                metricRow("Toplam İş Emri", "\(summary.totalOrders)")
                metricRow("Tamamlanan İş", "\(summary.completedOrders)")
                metricRow("Beklemede", "\(summary.pausedOrders)")
                metricRow("Devam Eden", "\(summary.inProgressOrders)")
                if let last = summary.lastVisitDate {
                    metricRow("Son Ziyaret", WorkOrderPresentationMapping.formatDate(last))
                }
            }
            .padding(AppSpacing.m)
            .semanticAccentCard(role: .primary, minHeight: nil)

            Button("Başka müşteri seç", action: onClearSelection)
                .font(AppFont.caption)
        }
    }

    private func metricRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .font(AppFont.caption)
                .foregroundStyle(AppColor.secondaryText)
            Spacer()
            Text(value)
                .font(AppFont.body)
                .foregroundStyle(AppColor.primaryText)
        }
    }

    private var technicianSection: some View {
        analyticsListSection(title: "Teknisyen Geçmişi", empty: technicianHistory.isEmpty) {
            ForEach(technicianHistory) { entry in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.technicianName)
                            .font(AppFont.body)
                            .foregroundStyle(AppColor.primaryText)
                        if let last = entry.lastVisit {
                            Text("Son: \(WorkOrderPresentationMapping.formatDate(last))")
                                .font(AppFont.caption)
                                .foregroundStyle(AppColor.secondaryText)
                        }
                    }
                    Spacer()
                    Text("\(entry.visitCount) ziyaret")
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.secondaryText)
                }
                .padding(AppSpacing.m)
                .background(RoundedRectangle(cornerRadius: AppRadius.card).fill(AppColor.elevatedSurface))
            }
        }
    }

    private var operationSection: some View {
        analyticsListSection(title: "İşlem Geçmişi", empty: operationHistory.isEmpty) {
            ForEach(operationHistory) { entry in
                HStack {
                    Text(entry.workType.displayName)
                        .font(AppFont.body)
                    Spacer()
                    Text("\(entry.count)")
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.secondaryText)
                }
                .padding(AppSpacing.m)
                .background(RoundedRectangle(cornerRadius: AppRadius.card).fill(AppColor.elevatedSurface))
            }
        }
    }

    private var deviceSection: some View {
        analyticsListSection(title: "Cihaz Geçmişi", empty: deviceHistory.isEmpty) {
            ForEach(deviceHistory) { entry in
                HStack {
                    Text(entry.deviceCategory.displayName)
                        .font(AppFont.body)
                    Spacer()
                    Text("\(entry.count) işlem")
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.secondaryText)
                }
                .padding(AppSpacing.m)
                .background(RoundedRectangle(cornerRadius: AppRadius.card).fill(AppColor.elevatedSurface))
            }
        }
    }

    private var timelineSection: some View {
        analyticsListSection(title: "Zaman Çizelgesi", empty: timeline.isEmpty) {
            ForEach(timeline) { entry in
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Text(WorkOrderPresentationMapping.formatDateTime(entry.date))
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.secondaryText)
                    Text(entry.workOrderNumber)
                        .font(AppFont.subtitle)
                        .foregroundStyle(AppColor.primaryText)
                    Text(
                        [
                            entry.technicianName,
                            entry.workType.displayName,
                            entry.deviceCategory.displayName,
                            entry.status.displayName
                        ].joined(separator: " · ")
                    )
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
    private func analyticsListSection<Content: View>(
        title: String,
        empty: Bool,
        @ViewBuilder content: () -> Content
    ) -> some View {
        if !empty {
            VStack(alignment: .leading, spacing: AppSpacing.m) {
                SectionHeader(title: title)
                content()
            }
        }
    }
}
