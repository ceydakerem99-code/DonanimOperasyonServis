import SwiftUI

struct FaultRecurrenceAnalysisView: View {
    @Bindable var viewModel: FaultRecurrenceAnalysisViewModel
    var onSelectWorkOrder: (WorkOrderID) -> Void

    var body: some View {
        FaultRecurrenceContentView(
            phase: mapPhase(viewModel.phase),
            showsLoadingIndicator: viewModel.showsLoadingIndicator,
            hasCachedContent: viewModel.hasCachedContent,
            kpis: viewModel.kpis,
            customerSummaries: viewModel.customerSummaries,
            workTypeSummaries: viewModel.workTypeSummaries,
            filteredEntries: viewModel.filteredEntries,
            searchText: $viewModel.searchText,
            selectedWorkType: $viewModel.selectedWorkType,
            filterDateFrom: $viewModel.filterDateFrom,
            filterDateTo: $viewModel.filterDateTo,
            detailRows: { viewModel.detailRows(for: $0) },
            onSelectWorkOrder: onSelectWorkOrder,
            onReload: { Task { await viewModel.load() } }
        )
        .navigationTitle("Arıza Tekrar Analizi")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load() }
        .refreshable { await viewModel.load() }
    }

    private func mapPhase(_ phase: FaultRecurrenceAnalysisViewModel.Phase) -> FaultRecurrenceContentView.Phase {
        switch phase {
        case .loading: return .loading
        case .ready: return .ready
        case .empty: return .empty
        case .error(let message): return .error(message)
        }
    }
}

struct OperatorFaultRecurrenceAnalysisView: View {
    @Bindable var viewModel: OperatorFaultRecurrenceAnalysisViewModel
    var onSelectWorkOrder: (WorkOrderID) -> Void

    var body: some View {
        FaultRecurrenceContentView(
            phase: mapPhase(viewModel.phase),
            showsLoadingIndicator: viewModel.showsLoadingIndicator,
            hasCachedContent: viewModel.hasCachedContent,
            kpis: viewModel.kpis,
            customerSummaries: viewModel.customerSummaries,
            workTypeSummaries: viewModel.workTypeSummaries,
            filteredEntries: viewModel.filteredEntries,
            searchText: $viewModel.searchText,
            selectedWorkType: $viewModel.selectedWorkType,
            filterDateFrom: $viewModel.filterDateFrom,
            filterDateTo: $viewModel.filterDateTo,
            detailRows: { viewModel.detailRows(for: $0) },
            onSelectWorkOrder: onSelectWorkOrder,
            onReload: { Task { await viewModel.load() } }
        )
        .navigationTitle("Arıza Tekrar Analizi")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load() }
        .refreshable { await viewModel.load() }
    }

    private func mapPhase(_ phase: OperatorFaultRecurrenceAnalysisViewModel.Phase) -> FaultRecurrenceContentView.Phase {
        switch phase {
        case .loading: return .loading
        case .ready: return .ready
        case .empty: return .empty
        case .error(let message): return .error(message)
        }
    }
}

#if DEBUG
#Preview("Fault Recurrence Analysis") {
    NavigationStack {
        FaultRecurrenceAnalysisView(
            viewModel: .previewReady(),
            onSelectWorkOrder: { _ in }
        )
    }
}
#endif
