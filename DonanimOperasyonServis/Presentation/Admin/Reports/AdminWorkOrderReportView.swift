import SwiftUI

struct AdminWorkOrderReportView: View {
    @Bindable var viewModel: AdminWorkOrderReportViewModel

    var body: some View {
        Group {
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
                    reportBody(content)
                }
            }
        }
        .navigationTitle("İş Emri Raporu")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load() }
    }

    @ViewBuilder
    private func reportBody(_ content: AdminWorkOrderReportContent) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.l) {
                HStack {
                    Text(content.workOrder.workOrderNumber)
                        .font(AppFont.title)
                    Spacer()
                    StatusChip(status: WorkOrderPresentationMapping.appStatus(from: content.workOrder.status))
                }

                InfoRow(title: "Müşteri", value: content.customerName, systemImage: "building.2")
                InfoRow(
                    title: "Cihaz",
                    value: "\(content.workOrder.deviceCategory.displayName) · \(content.workOrder.deviceBrand)",
                    systemImage: "creditcard"
                )
                InfoRow(title: "İş Türü", value: content.workOrder.workType.displayName, systemImage: "wrench.and.screwdriver")

                if content.workOrder.status == .completed, let completedAt = content.workOrder.completedAt {
                    InfoRow(
                        title: "Tamamlanma",
                        value: WorkOrderPresentationMapping.formatDateTime(completedAt),
                        systemImage: "checkmark.seal"
                    )
                }

                SectionHeader(title: "Ekler")
                attachmentRow(title: "Servis Notları", count: content.noteCount, systemImage: "note.text")
                attachmentRow(title: "İmzalar", count: content.signatureCount, systemImage: "pencil.and.scribble")
                attachmentRow(title: "Fotoğraflar", count: content.photoCount, systemImage: "camera")
            }
            .padding(AppSpacing.l)
        }
    }

    private func attachmentRow(title: String, count: Int, systemImage: String) -> some View {
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

#if DEBUG
#Preview("Work Order Report") {
    NavigationStack {
        AdminWorkOrderReportView(viewModel: .previewLoaded())
    }
}
#endif
