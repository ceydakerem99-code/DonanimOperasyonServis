import SwiftUI

struct FaultRecurrenceContentView: View {
    enum Phase: Equatable {
        case loading
        case ready
        case empty
        case error(String)
    }

    let phase: Phase
    let showsLoadingIndicator: Bool
    let hasCachedContent: Bool
    let kpis: FaultRecurrenceKPIs?
    let customerSummaries: [FaultRecurrenceCustomerSummary]
    let workTypeSummaries: [FaultRecurrenceWorkTypeSummary]
    let filteredEntries: [FaultRecurrenceEntry]
    @Binding var searchText: String
    @Binding var selectedWorkType: WorkType?
    @Binding var filterDateFrom: Date?
    @Binding var filterDateTo: Date?
    let detailRows: (FaultRecurrenceEntry) -> [FaultRecurrenceDetailRow]
    var onSelectWorkOrder: (WorkOrderID) -> Void
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
                    loadingMessage: "Arıza tekrar analizi yükleniyor...",
                    errorTitle: "Analiz yüklenemedi",
                    onRetry: onReload,
                    content: {
                        methodologyNote
                        if let kpis { kpiSection(kpis) }
                        filterSection
                        customerSummarySection
                        workTypeSummarySection
                        recurrenceListSection
                    },
                    empty: {
                        EmptyState(
                            systemImage: "arrow.triangle.2.circlepath",
                            title: "Tekrarlayan arıza yok",
                            message: "Aynı müşteri ve cihazda birden fazla arıza kaydı bulunamadı."
                        )
                    }
                )
            }
            .padding(.horizontal, AppSpacing.l)
            .padding(.bottom, AppSpacing.xl)
        }
    }

    private var methodologyNote: some View {
        Text("Tekrar, aynı müşteri ve seri numaralı cihazda birden fazla arıza iş emri olarak sayılır. Reddedilen kayıtlar hariç tutulur; metin benzerliği kullanılmaz.")
            .font(AppFont.caption)
            .foregroundStyle(AppColor.secondaryText)
            .padding(AppSpacing.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: AppRadius.card).fill(AppColor.elevatedSurface))
    }

    private func kpiSection(_ kpis: FaultRecurrenceKPIs) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.m) {
            SectionHeader(title: "Özet")
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: AppSpacing.m) {
                SemanticMetricCard(title: "Tekrarlayan Arıza", value: "\(kpis.recurringFaultCount)", role: .urgent)
                SemanticMetricCard(title: "En Çok Tekrar Eden Cihaz", value: kpis.topDeviceLabel ?? "—", role: .primary, minHeight: nil)
                SemanticMetricCard(title: "Cihaz Tekrar Sayısı", value: kpis.topDeviceRecurrence > 0 ? "\(kpis.topDeviceRecurrence)" : "—", role: .overdue, minHeight: nil)
                SemanticMetricCard(title: "En Çok Tekrar Eden Müşteri", value: kpis.topCustomerName ?? "—", role: .primary, minHeight: nil)
            }
        }
    }

    private func kpiCard(_ title: String, _ value: String) -> some View {
        SemanticMetricCard(title: title, value: value, minHeight: nil)
    }

    private var filterSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.m) {
            SectionHeader(title: "Arama ve Filtre")
            TextField("Müşteri, iş yeri, cihaz, arıza, teknisyen...", text: $searchText)
                .padding(AppSpacing.m)
                .background(RoundedRectangle(cornerRadius: AppRadius.card).fill(AppColor.elevatedSurface))

            Picker("İş türü", selection: $selectedWorkType) {
                Text("Tümü").tag(WorkType?.none)
                ForEach(WorkType.allCases, id: \.self) { workType in
                    Text(workType.displayName).tag(WorkType?.some(workType))
                }
            }
            .pickerStyle(.menu)

            HStack(spacing: AppSpacing.m) {
                optionalDatePicker(title: "Başlangıç", selection: $filterDateFrom)
                optionalDatePicker(title: "Bitiş", selection: $filterDateTo)
            }
        }
    }

    private func optionalDatePicker(title: String, selection: Binding<Date?>) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text(title)
                .font(AppFont.caption)
                .foregroundStyle(AppColor.secondaryText)
            if let date = selection.wrappedValue {
                DatePicker(
                    "",
                    selection: Binding(
                        get: { date },
                        set: { selection.wrappedValue = $0 }
                    ),
                    displayedComponents: .date
                )
                .labelsHidden()
                Button("Temizle") { selection.wrappedValue = nil }
                    .font(AppFont.caption)
            } else {
                Button("\(title) ekle") {
                    selection.wrappedValue = Calendar.current.startOfDay(for: Date())
                }
                .font(AppFont.caption)
            }
        }
        .padding(AppSpacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: AppRadius.card).fill(AppColor.elevatedSurface))
    }

    private var customerSummarySection: some View {
        analyticsListSection(title: "Müşteri Bazında Tekrar", empty: customerSummaries.isEmpty) {
            ForEach(customerSummaries.prefix(5)) { summary in
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Text(summary.customerName)
                        .font(AppFont.subtitle)
                    Text(summary.workplace)
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.secondaryText)
                    Text("Tekrar: \(summary.recurrenceCount) · Cihaz: \(summary.deviceCount)")
                        .font(AppFont.caption)
                    Text("Son: \(WorkOrderPresentationMapping.formatDate(summary.lastOccurrenceDate))")
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.secondaryText)
                }
                .padding(AppSpacing.m)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: AppRadius.card).fill(AppColor.elevatedSurface))
            }
        }
    }

    private var workTypeSummarySection: some View {
        analyticsListSection(title: "İş Türü Bazında Tekrar", empty: workTypeSummaries.isEmpty) {
            ForEach(workTypeSummaries) { summary in
                HStack {
                    Text(summary.workType.displayName)
                        .font(AppFont.body)
                    Spacer()
                    Text("\(summary.count)")
                        .font(AppFont.body)
                        .foregroundStyle(AppColor.secondaryText)
                }
                .padding(AppSpacing.m)
                .background(RoundedRectangle(cornerRadius: AppRadius.card).fill(AppColor.elevatedSurface))
            }
        }
    }

    private var recurrenceListSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.m) {
            SectionHeader(title: "Cihaz Bazında Tekrarlayan Arızalar")
            if filteredEntries.isEmpty {
                EmptyState(
                    systemImage: "magnifyingglass",
                    title: "Sonuç bulunamadı",
                    message: "Arama veya filtre kriterlerinize uygun tekrar kaydı bulunamadı."
                )
            } else {
                ForEach(filteredEntries) { entry in
                    NavigationLink {
                        FaultRecurrenceDetailView(
                            entry: entry,
                            detailRows: detailRows(entry),
                            onSelectWorkOrder: onSelectWorkOrder
                        )
                    } label: {
                        recurrenceCard(entry)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func recurrenceCard(_ entry: FaultRecurrenceEntry) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.s) {
            Text(entry.customerName)
                .font(AppFont.subtitle)
                .foregroundStyle(AppColor.primaryText)
            Text(entry.serialNumber)
                .font(AppFont.body)
                .foregroundStyle(AppColor.primaryText)
            Text("Arıza: \(entry.issueLabel)")
                .font(AppFont.caption)
                .foregroundStyle(AppColor.secondaryText)
            HStack {
                Text("Tekrar: \(entry.recurrenceCount)")
                    .font(AppFont.body)
                    .fontWeight(.bold)
                    .foregroundStyle(AppColor.brandPrimary)
                Spacer()
                Text("Son işlem: \(WorkOrderPresentationMapping.formatDate(entry.lastOccurrenceDate))")
                    .font(AppFont.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(AppColor.primaryText)
            }
            if !entry.technicianNames.isEmpty {
                Text("Teknisyenler: \(entry.technicianSummary)")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.secondaryText)
            }
        }
        .padding(AppSpacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: AppRadius.card).fill(AppColor.elevatedSurface))
    }

    @ViewBuilder
    private func analyticsListSection<Content: View>(
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
}

struct FaultRecurrenceDetailView: View {
    let entry: FaultRecurrenceEntry
    let detailRows: [FaultRecurrenceDetailRow]
    var onSelectWorkOrder: (WorkOrderID) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.l) {
                VStack(alignment: .leading, spacing: AppSpacing.s) {
                    Text(entry.customerName)
                        .font(AppFont.title)
                    Text(entry.workplace)
                        .font(AppFont.body)
                        .foregroundStyle(AppColor.secondaryText)
                    Text(entry.deviceLabel)
                        .font(AppFont.subtitle)
                    Text("Arıza: \(entry.issueLabel)")
                        .font(AppFont.body)
                    HStack {
                        Text("Tekrar: \(entry.recurrenceCount)")
                            .font(AppFont.body)
                            .fontWeight(.bold)
                            .foregroundStyle(AppColor.brandPrimary)
                        Spacer()
                        Text("Son: \(WorkOrderPresentationMapping.formatDate(entry.lastOccurrenceDate))")
                            .font(AppFont.body)
                            .fontWeight(.bold)
                    }
                    if !entry.technicianNames.isEmpty {
                        Text("Teknisyenler: \(entry.technicianSummary)")
                            .font(AppFont.caption)
                            .foregroundStyle(AppColor.secondaryText)
                    }
                }
                .padding(AppSpacing.m)
                .background(RoundedRectangle(cornerRadius: AppRadius.card).fill(AppColor.elevatedSurface))

                SectionHeader(title: "Geçmiş İş Emirleri")
                if detailRows.isEmpty {
                    EmptyState(
                        systemImage: "doc.text",
                        title: "İş emri bulunamadı",
                        message: "Bu tekrar grubuna ait iş emri kaydı bulunamadı."
                    )
                } else {
                    ForEach(detailRows) { row in
                        Button {
                            onSelectWorkOrder(row.id)
                        } label: {
                            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                                HStack {
                                    Text(row.workOrderNumber)
                                        .font(AppFont.subtitle)
                                    Spacer()
                                    StatusChip(status: WorkOrderPresentationMapping.appStatus(from: row.status))
                                }
                                Text(WorkOrderPresentationMapping.formatDateTime(row.occurredAt))
                                    .font(AppFont.caption)
                                    .foregroundStyle(AppColor.secondaryText)
                                Text("Teknisyen: \(row.technicianName)")
                                    .font(AppFont.caption)
                                Text("Yapılan işlem: \(row.issueDescription)")
                                    .font(AppFont.caption)
                                Text("Cihaz: \(row.deviceLabel)")
                                    .font(AppFont.caption)
                                    .foregroundStyle(AppColor.secondaryText)
                            }
                            .padding(AppSpacing.m)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: AppRadius.card).fill(AppColor.elevatedSurface))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, AppSpacing.l)
            .padding(.bottom, AppSpacing.xl)
        }
        .navigationTitle("Tekrar Detayı")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#if DEBUG
#Preview("Fault Recurrence") {
    NavigationStack {
        FaultRecurrenceContentView(
            phase: .ready,
            showsLoadingIndicator: false,
            hasCachedContent: true,
            kpis: FaultRecurrenceKPIs(
                recurringFaultCount: 1,
                topDeviceLabel: "POS · POS-01",
                topDeviceRecurrence: 4,
                topCustomerName: "ABC Müşterisi",
                topCustomerRecurrence: 4
            ),
            customerSummaries: [],
            workTypeSummaries: [],
            filteredEntries: FaultRecurrenceAnalysisViewModel.previewReady().entries,
            searchText: .constant(""),
            selectedWorkType: .constant(nil),
            filterDateFrom: .constant(nil),
            filterDateTo: .constant(nil),
            detailRows: { _ in [] },
            onSelectWorkOrder: { _ in },
            onReload: {}
        )
    }
}
#endif
