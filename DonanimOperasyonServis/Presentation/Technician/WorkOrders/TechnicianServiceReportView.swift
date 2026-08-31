import SwiftUI

struct TechnicianServiceReportView: View {
    let workOrderId: WorkOrderID
    let dependencies: TechnicianDependencies
    let actor: User
    @State private var viewModel: TechnicianWorkOrderDetailViewModel
    @State private var pdfFileURL: URL?
    @State private var isExportingPDF = false

    init(workOrderId: WorkOrderID, dependencies: TechnicianDependencies, actor: User) {
        self.workOrderId = workOrderId
        self.dependencies = dependencies
        self.actor = actor
        _viewModel = State(initialValue: TechnicianWorkOrderDetailViewModel(
            workOrderId: workOrderId,
            actor: actor,
            dependencies: dependencies
        ))
    }

    var body: some View {
        reportBody(viewModel)
            .navigationTitle("Servis Raporu")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { pdfToolbar }
            .task { await viewModel.load() }
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
                    WorkOrderReportDetailSections(
                        snapshot: content.reportSnapshot,
                        mediaLoader: WorkOrderMediaLoader(storage: dependencies.storageDataSource)
                    )
                    .padding(AppSpacing.l)
                }
            }
        }
    }

    @ToolbarContentBuilder
    private var pdfToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            if let pdfFileURL {
                ShareLink(item: pdfFileURL) {
                    Label("PDF Paylaş", systemImage: "square.and.arrow.up")
                }
            } else {
                Button {
                    Task { await exportPDF() }
                } label: {
                    if isExportingPDF {
                        ProgressView()
                    } else {
                        Label("PDF", systemImage: "doc.richtext")
                    }
                }
                .disabled(viewModel.content == nil || isExportingPDF)
            }
        }
    }

    private func exportPDF() async {
        guard let content = viewModel.content, !isExportingPDF else { return }
        isExportingPDF = true
        defer { isExportingPDF = false }
        let snapshot = content.reportSnapshot
        let loader = WorkOrderMediaLoader(storage: dependencies.storageDataSource)
        let media = await WorkOrderReportPDFExporter.collectMedia(snapshot: snapshot, loader: loader)
        let data = WorkOrderReportPDFExporter.makePDF(snapshot: snapshot, media: media)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(snapshot.workOrder.workOrderNumber)-rapor.pdf")
        try? data.write(to: url, options: .atomic)
        pdfFileURL = url
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
