import SwiftUI

struct AdminWorkOrderReportView: View {
    let workOrderId: WorkOrderID
    let actor: User
    let dependencies: AdminDependencies
    var onDeleted: (() -> Void)?

    @State private var viewModel: AdminWorkOrderReportViewModel

    init(
        workOrderId: WorkOrderID,
        actor: User,
        dependencies: AdminDependencies,
        onDeleted: (() -> Void)? = nil
    ) {
        self.workOrderId = workOrderId
        self.actor = actor
        self.dependencies = dependencies
        self.onDeleted = onDeleted
        _viewModel = State(
            initialValue: AdminWorkOrderReportViewModel(
                workOrderId: workOrderId,
                actor: actor,
                dependencies: dependencies
            )
        )
    }

    var body: some View {
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
                    VStack(alignment: .leading, spacing: AppSpacing.m) {
                        if let deleteError = viewModel.deleteError {
                            ErrorBanner(title: "Silme hatası", message: deleteError)
                        }
                        WorkOrderReportDetailSections(
                            snapshot: content.snapshot,
                            mediaLoader: viewModel.mediaLoader
                        )
                    }
                    .padding(AppSpacing.l)
                }
            }
        }
        .navigationTitle("İş Emri Raporu")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .id(workOrderId)
        .task(id: workOrderId) { await viewModel.load() }
        .confirmationDialog(
            "İş Emrini Sil",
            isPresented: $viewModel.showsDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Sil", role: .destructive) {
                Task {
                    if await viewModel.confirmDelete() {
                        onDeleted?()
                    }
                }
            }
            Button("Vazgeç", role: .cancel) {
                viewModel.cancelDeleteConfirmation()
            }
        } message: {
            Text(viewModel.deleteConfirmationMessage)
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            if let url = viewModel.pdfFileURL {
                ShareLink(item: url) {
                    Label("PDF Paylaş", systemImage: "square.and.arrow.up")
                }
            } else {
                Button {
                    Task { await viewModel.exportPDF() }
                } label: {
                    if viewModel.isExportingPDF {
                        ProgressView()
                    } else {
                        Label("PDF", systemImage: "doc.richtext")
                    }
                }
                .disabled(viewModel.content == nil || viewModel.isExportingPDF)
            }
        }

        if viewModel.canDeleteWorkOrder {
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) {
                    viewModel.requestDeleteConfirmation()
                } label: {
                    if viewModel.isDeleting {
                        ProgressView()
                    } else {
                        Label("Sil", systemImage: "trash")
                    }
                }
                .disabled(viewModel.isDeleting)
            }
        }
    }
}

#if DEBUG
#Preview("Work Order Report") {
    NavigationStack {
        AdminWorkOrderReportView(
            workOrderId: WorkOrderID("wo-preview"),
            actor: AdminPreviewData.adminUser,
            dependencies: DIContainer.mock().makeAdminDependencies()
        )
    }
}
#endif
