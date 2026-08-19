import SwiftUI

struct OperatorWorkOrderReportView: View {
    let workOrderId: WorkOrderID
    @State private var viewModel: OperatorWorkOrderDetailViewModel?

    var body: some View {
        Group {
            if let viewModel {
                reportContent(viewModel)
            } else {
                LoadingView(message: "Rapor yükleniyor...")
            }
        }
        .navigationTitle("İş Emri Raporu")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel?.load()
        }
    }

    @ViewBuilder
    private func reportContent(_ viewModel: OperatorWorkOrderDetailViewModel) -> some View {
        switch viewModel.phase {
        case .loading:
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
                            Text(content.workOrder.workOrderNumber)
                                .font(AppFont.title)
                            Spacer()
                            StatusChip(status: WorkOrderPresentationMapping.appStatus(from: content.workOrder.status))
                        }

                        InfoRow(title: "Müşteri", value: content.customer.name, systemImage: "building.2")
                        InfoRow(
                            title: "Cihaz",
                            value: "\(content.workOrder.deviceCategory.displayName) · \(content.workOrder.deviceBrand)",
                            systemImage: "creditcard"
                        )

                        if content.workOrder.status == .completed, let completedAt = content.workOrder.completedAt {
                            InfoRow(
                                title: "Tamamlanma",
                                value: WorkOrderPresentationMapping.formatDateTime(completedAt),
                                systemImage: "checkmark.seal"
                            )
                        }

                        SectionHeader(title: "Ekler")
                        reportAttachmentRow(title: "Servis Notları", count: content.notes.count, systemImage: "note.text")
                        reportAttachmentRow(title: "Fotoğraflar", count: 0, systemImage: "photo")
                        reportAttachmentRow(title: "GPS Kayıtları", count: 0, systemImage: "location")
                        reportAttachmentRow(title: "İmzalar", count: 0, systemImage: "signature")
                    }
                    .padding(AppSpacing.l)
                }
            }
        }
    }

    private func reportAttachmentRow(title: String, count: Int, systemImage: String) -> some View {
        HStack {
            Image(systemName: systemImage)
                .foregroundStyle(AppColor.brandPrimary)
            Text(title)
                .font(AppFont.body)
            Spacer()
            Text("\(count)")
                .font(AppFont.caption)
                .foregroundStyle(AppColor.secondaryText)
        }
        .padding(AppSpacing.m)
        .background(RoundedRectangle(cornerRadius: AppRadius.card).fill(AppColor.elevatedSurface))
    }
}

extension OperatorWorkOrderReportView {
    init(workOrderId: WorkOrderID, dependencies: OperatorDependencies, actor: User) {
        self.workOrderId = workOrderId
        _viewModel = State(initialValue: OperatorWorkOrderDetailViewModel(
            workOrderId: workOrderId,
            actor: actor,
            dependencies: dependencies
        ))
    }
}

#if DEBUG
#Preview("WorkOrder Report") {
    NavigationStack {
        OperatorWorkOrderReportView(
            workOrderId: WorkOrderID("wo-1026"),
            dependencies: DIContainer.mock().makeOperatorDependencies(),
            actor: OperatorPreviewData.operatorUser
        )
    }
}
#endif
