import SwiftUI

struct OperatorReportDetailView: View {
    @Bindable var viewModel: OperatorReportDetailViewModel
    let mediaLoader: WorkOrderMediaLoader
    var onSelectWorkOrder: ((WorkOrderID) -> Void)?

    var body: some View {
        ReportDetailContentView(
            kind: viewModel.kind,
            phase: mapPhase(viewModel.phase),
            showsLoadingIndicator: viewModel.showsLoadingIndicator,
            hasCachedContent: viewModel.hasCachedContent,
            payload: viewModel.payload,
            reportSearchText: $viewModel.reportSearchText,
            mediaLoader: mediaLoader,
            onSelectWorkOrder: onSelectWorkOrder,
            onReload: { Task { await viewModel.load() } }
        )
        .navigationTitle(viewModel.kind.title)
        .navigationBarTitleDisplayMode(.inline)
        .id(viewModel.kind)
        .task(id: viewModel.kind) { await viewModel.load() }
        .refreshable { await viewModel.load() }
    }

    private func mapPhase(_ phase: OperatorReportDetailViewModel.Phase) -> AdminReportDetailViewModel.Phase {
        switch phase {
        case .loading: return .loading
        case .loaded: return .loaded
        case .empty: return .empty
        case .error(let message): return .error(message)
        }
    }
}
