import SwiftUI

struct OperatorWorkOrderReportView: View {
    let workOrderId: WorkOrderID
    let dependencies: OperatorDependencies
    let actor: User
    @State private var viewModel: OperatorWorkOrderDetailViewModel
    @State private var pdfFileURL: URL?
    @State private var isExportingPDF = false

    init(workOrderId: WorkOrderID, dependencies: OperatorDependencies, actor: User) {
        self.workOrderId = workOrderId
        self.dependencies = dependencies
        self.actor = actor
        _viewModel = State(initialValue: OperatorWorkOrderDetailViewModel(
            workOrderId: workOrderId,
            actor: actor,
            dependencies: dependencies
        ))
    }

    var body: some View {
        reportContent(viewModel)
            .navigationTitle("İş Emri Raporu")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { pdfToolbar }
            .id(workOrderId)
            .task(id: workOrderId) { await viewModel.load() }
    }

    @ViewBuilder
    private func reportContent(_ viewModel: OperatorWorkOrderDetailViewModel) -> some View {
        AsyncLoadContainerView(
            isLoading: viewModel.phase == .loading,
            showsLoadingIndicator: viewModel.showsLoadingIndicator,
            hasCachedContent: viewModel.hasCachedContent,
            errorMessage: AsyncLoadPhaseParsing.errorMessage(viewModel.phase),
            isEmpty: false,
            loadingMessage: "Rapor yükleniyor...",
            errorTitle: "Rapor yüklenemedi",
            onRetry: { Task { await viewModel.load() } }
        ) {
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
        guard let snapshot = viewModel.content?.reportSnapshot, !isExportingPDF else { return }
        isExportingPDF = true
        defer { isExportingPDF = false }
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
