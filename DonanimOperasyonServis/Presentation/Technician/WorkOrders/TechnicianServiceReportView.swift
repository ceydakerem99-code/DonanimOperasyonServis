import SwiftUI

struct TechnicianServiceReportView: View {
    let workOrderId: WorkOrderID
    @State private var viewModel: TechnicianWorkOrderDetailViewModel?

    var body: some View {
        Group {
            if let viewModel {
                reportBody(viewModel)
            } else {
                LoadingView(message: "Rapor yükleniyor...")
            }
        }
        .navigationTitle("Servis Raporu")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel?.load() }
    }

    @ViewBuilder
    private func reportBody(_ viewModel: TechnicianWorkOrderDetailViewModel) -> some View {
        switch viewModel.phase {
        case .loading, .submitting:
            LoadingView(message: "Rapor yükleniyor...")
        case .error(let message):
            ErrorBanner(title: "Rapor yüklenemedi", message: message) {
                Task { await viewModel.load() }
            }
            .padding(AppSpacing.l)
        case .loaded:
            if let content = viewModel.content {
                ScrollView {
                    VStack(alignment: .leading, spacing: AppSpacing.l) {
                        HStack {
                            Text(content.workOrder.workOrderNumber).font(AppFont.title)
                            Spacer()
                            StatusChip(status: WorkOrderPresentationMapping.appStatus(from: content.workOrder.status))
                        }
                        InfoRow(title: "Müşteri", value: content.customer.name, systemImage: "building.2")
                        InfoRow(title: "İş Türü", value: content.workOrder.workType.displayName, systemImage: "briefcase")
                        if let completedAt = content.workOrder.completedAt {
                            InfoRow(
                                title: "Tamamlanma",
                                value: WorkOrderPresentationMapping.formatDateTime(completedAt),
                                systemImage: "checkmark.seal"
                            )
                        }
                        SectionHeader(title: "Rapor Özeti")
                        reportMetric("Servis Notları", content.notes.count, "note.text")
                        reportMetric("Fotoğraflar", content.photos.count, "photo")
                        reportMetric("GPS Kayıtları", content.locations.count, "location")
                        reportMetric("İmzalar", content.signatures.count, "signature")
                        if let description = content.workOrder.issueDescription {
                            InfoRow(title: "Yapılan İşlem", value: description, systemImage: "text.alignleft")
                        }
                    }
                    .padding(AppSpacing.l)
                }
            }
        }
    }

    private func reportMetric(_ title: String, _ count: Int, _ icon: String) -> some View {
        HStack {
            Label(title, systemImage: icon)
            Spacer()
            Text("\(count)").font(AppFont.caption).foregroundStyle(AppColor.secondaryText)
        }
        .padding(AppSpacing.m)
        .background(RoundedRectangle(cornerRadius: AppRadius.card).fill(AppColor.elevatedSurface))
    }
}

extension TechnicianServiceReportView {
    init(workOrderId: WorkOrderID, dependencies: TechnicianDependencies, actor: User) {
        self.workOrderId = workOrderId
        _viewModel = State(initialValue: TechnicianWorkOrderDetailViewModel(
            workOrderId: workOrderId,
            actor: actor,
            dependencies: dependencies
        ))
    }
}

#if DEBUG
#Preview("Service Report") {
    NavigationStack {
        TechnicianServiceReportView(
            workOrderId: WorkOrderID("wo-tech-1"),
            dependencies: DIContainer.mock().makeTechnicianDependencies(),
            actor: TechnicianPreviewData.technician
        )
    }
}
#endif
