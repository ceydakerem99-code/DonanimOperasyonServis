import SwiftUI

struct AdminReportDetailView: View {
    @Bindable var viewModel: AdminReportDetailViewModel
    var onSelectWorkOrder: ((WorkOrderID) -> Void)?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.l) {
                switch viewModel.phase {
                case .loading:
                    LoadingView(message: "Rapor yükleniyor...")
                        .frame(minHeight: 240)

                case .error(let message):
                    ErrorBanner(title: "Rapor yüklenemedi", message: message) {
                        Task { await viewModel.load() }
                    }

                case .empty:
                    EmptyState(
                        systemImage: viewModel.kind.systemImage,
                        title: "Rapor verisi yok",
                        message: "İş emri verileri eklendiğinde rapor burada görünecek."
                    )

                case .loaded:
                    metricsSection
                    if !viewModel.statusBreakdown.isEmpty {
                        statusBreakdownSection
                    }
                    if !viewModel.relatedWorkOrders.isEmpty {
                        relatedWorkOrdersSection
                    }
                }
            }
            .padding(.horizontal, AppSpacing.l)
            .padding(.bottom, AppSpacing.xl)
        }
        .navigationTitle(viewModel.kind.title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load() }
        .refreshable { await viewModel.load() }
    }

    private var metricsSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.m) {
            SectionHeader(title: "Özet Metrikler")
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: AppSpacing.m) {
                ForEach(viewModel.metrics) { metric in
                    VStack(alignment: .leading, spacing: AppSpacing.xs) {
                        Text(metric.title)
                            .font(AppFont.caption)
                            .foregroundStyle(AppColor.secondaryText)
                        Text(metric.value)
                            .font(AppFont.body)
                            .foregroundStyle(AppColor.primaryText)
                            .lineLimit(3)
                            .minimumScaleFactor(0.8)
                    }
                    .padding(AppSpacing.m)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: AppRadius.card).fill(AppColor.elevatedSurface))
                }
            }
        }
    }

    private var statusBreakdownSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.m) {
            SectionHeader(title: "Durum Dağılımı")
            ForEach(viewModel.statusBreakdown) { item in
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    HStack {
                        StatusChip(status: WorkOrderPresentationMapping.appStatus(from: item.status))
                        Spacer()
                        Text("\(item.count) · \(String(format: "%.0f%%", item.percentage))")
                            .font(AppFont.caption)
                            .foregroundStyle(AppColor.secondaryText)
                    }
                    GeometryReader { geo in
                        RoundedRectangle(cornerRadius: 4)
                            .fill(AppColor.brandPrimary.opacity(0.2))
                            .overlay(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(AppColor.brandPrimary)
                                    .frame(width: geo.size.width * item.percentage / 100)
                            }
                    }
                    .frame(height: 8)
                }
                .padding(AppSpacing.m)
                .background(RoundedRectangle(cornerRadius: AppRadius.card).fill(AppColor.elevatedSurface))
            }
        }
    }

    private var relatedWorkOrdersSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.m) {
            SectionHeader(title: relatedSectionTitle)
            ForEach(viewModel.relatedWorkOrders) { item in
                Button {
                    onSelectWorkOrder?(item.id)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: AppSpacing.xs) {
                            Text(item.workOrderNumber)
                                .font(AppFont.subtitle)
                                .foregroundStyle(AppColor.primaryText)
                            Text(item.subtitle)
                                .font(AppFont.caption)
                                .foregroundStyle(AppColor.secondaryText)
                        }
                        Spacer()
                        if item.count > 0 {
                            Text("\(item.count)")
                                .font(AppFont.caption)
                                .foregroundStyle(AppColor.secondaryText)
                        }
                        Image(systemName: "chevron.right")
                            .font(AppFont.label)
                            .foregroundStyle(AppColor.secondaryText)
                    }
                    .padding(AppSpacing.m)
                    .background(RoundedRectangle(cornerRadius: AppRadius.card).fill(AppColor.elevatedSurface))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var relatedSectionTitle: String {
        switch viewModel.kind {
        case .signatures: return "İmzalı İş Emirleri"
        case .photos: return "Fotoğraflı İş Emirleri"
        case .workOrders: return "İş Emirleri"
        default: return "İlgili Kayıtlar"
        }
    }
}

#if DEBUG
#Preview("Report Detail — Work Orders") {
    NavigationStack {
        AdminReportDetailView(viewModel: .previewWorkOrders(), onSelectWorkOrder: nil)
    }
}
#endif
