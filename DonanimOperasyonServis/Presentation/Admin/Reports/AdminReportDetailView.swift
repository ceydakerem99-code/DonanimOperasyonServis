import SwiftUI

struct AdminReportDetailView: View {
    @Bindable var viewModel: AdminReportDetailViewModel
    let mediaLoader: WorkOrderMediaLoader
    var onSelectWorkOrder: ((WorkOrderID) -> Void)?

    var body: some View {
        ReportDetailContentView(
            kind: viewModel.kind,
            phase: viewModel.phase,
            showsLoadingIndicator: viewModel.showsLoadingIndicator,
            hasCachedContent: viewModel.hasCachedContent,
            payload: viewModel.payload,
            reportSearchText: $viewModel.reportSearchText,
            mediaLoader: mediaLoader,
            onSelectWorkOrder: viewModel.isSelectionMode ? nil : onSelectWorkOrder,
            onReload: { Task { await viewModel.load() } },
            isSelectionMode: viewModel.isSelectionMode,
            selectedOrderIDs: viewModel.selectedOrderIDs,
            canSelectWorkOrder: viewModel.canBulkDelete ? { viewModel.canSelect($0) } : nil,
            onToggleWorkOrderSelection: viewModel.canBulkDelete ? { viewModel.toggleSelection($0) } : nil,
            selectionSummaryText: viewModel.isSelectionMode ? viewModel.selectionSummaryText : nil,
            onSelectAllEligible: viewModel.canBulkDelete ? { viewModel.selectAllEligible() } : nil,
            onClearSelection: viewModel.canBulkDelete ? { viewModel.clearSelection() } : nil
        )
        .navigationTitle(viewModel.kind.title)
        .navigationBarTitleDisplayMode(.inline)
        .id(viewModel.kind)
        .task(id: viewModel.kind) { await viewModel.load() }
        .refreshable { await viewModel.load() }
        .toolbar {
            if viewModel.canBulkDelete {
                ToolbarItem(placement: .topBarLeading) {
                    if viewModel.isSelectionMode {
                        Button("Bitti") {
                            viewModel.setSelectionMode(false)
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        viewModel.setSelectionMode(!viewModel.isSelectionMode)
                    } label: {
                        Image(systemName: viewModel.isSelectionMode ? "checkmark.circle.fill" : "checklist")
                    }
                    .accessibilityLabel(viewModel.isSelectionMode ? "Seçim modunu kapat" : "Seçim modu")
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if viewModel.canPerformBulkDelete {
                bulkDeleteBar
            }
        }
        .confirmationDialog(
            "İş Emirlerini Sil",
            isPresented: $viewModel.showsBulkDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Sil", role: .destructive) {
                Task { await viewModel.confirmBulkDelete() }
            }
            Button("Vazgeç", role: .cancel) {
                viewModel.cancelBulkDeleteConfirmation()
            }
        } message: {
            Text(viewModel.bulkDeleteConfirmationMessage)
        }
        .alert(
            "Silme Sonucu",
            isPresented: Binding(
                get: { viewModel.bulkResultSummary != nil },
                set: { if !$0 { viewModel.dismissBulkResult() } }
            )
        ) {
            Button("Tamam", role: .cancel) { viewModel.dismissBulkResult() }
        } message: {
            Text(viewModel.bulkResultDetailMessage)
        }
    }

    private var bulkDeleteBar: some View {
        VStack(spacing: AppSpacing.s) {
            Text(viewModel.selectionSummaryText)
                .font(AppFont.caption)
                .foregroundStyle(AppColor.secondaryText)
            Button(role: .destructive) {
                viewModel.requestBulkDeleteConfirmation()
            } label: {
                HStack {
                    if viewModel.isPerformingBulkDelete {
                        ProgressView()
                            .tint(.white)
                    }
                    Image(systemName: "trash")
                    Text("Sil")
                }
                .font(AppFont.subtitle)
                .frame(maxWidth: .infinity)
                .padding(.vertical, AppSpacing.m)
            }
            .buttonStyle(.borderedProminent)
            .tint(AppColor.statusUrgent)
            .disabled(viewModel.isPerformingBulkDelete)
        }
        .padding(AppSpacing.m)
        .background(.ultraThinMaterial)
    }
}

#if DEBUG
#Preview("Report Detail — Work Orders") {
    NavigationStack {
        AdminReportDetailView(
            viewModel: .previewWorkOrders(),
            mediaLoader: WorkOrderMediaLoader(),
            onSelectWorkOrder: nil
        )
    }
}
#endif
