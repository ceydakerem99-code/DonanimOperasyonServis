import SwiftUI

struct CustomerAnalyticsView: View {
    @Bindable var viewModel: CustomerAnalyticsViewModel

    var body: some View {
        CustomerAnalyticsContentView(
            phase: mapPhase(viewModel.phase),
            showsLoadingIndicator: viewModel.showsLoadingIndicator,
            hasCachedContent: viewModel.hasCachedContent,
            summary: viewModel.summary,
            filteredCustomers: viewModel.filteredCustomers,
            customerPickerCards: viewModel.customerPickerCards,
            customerSearchText: $viewModel.customerSearchText,
            technicianHistory: viewModel.technicianHistory,
            operationHistory: viewModel.operationHistory,
            deviceHistory: viewModel.deviceHistory,
            timeline: viewModel.timeline,
            onSelectCustomer: { viewModel.selectCustomer($0) },
            onClearSelection: { viewModel.clearSelection() },
            onReload: { Task { await viewModel.load() } }
        )
        .navigationTitle("Müşteri Analizi")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load() }
        .refreshable { await viewModel.load() }
    }

    private func mapPhase(_ phase: CustomerAnalyticsViewModel.Phase) -> CustomerAnalyticsContentView.Phase {
        switch phase {
        case .loading: return .loading
        case .ready: return .ready
        case .empty: return .empty
        case .error(let message): return .error(message)
        }
    }
}

struct OperatorCustomerAnalyticsView: View {
    @Bindable var viewModel: OperatorCustomerAnalyticsViewModel

    var body: some View {
        CustomerAnalyticsContentView(
            phase: mapPhase(viewModel.phase),
            showsLoadingIndicator: viewModel.showsLoadingIndicator,
            hasCachedContent: viewModel.hasCachedContent,
            summary: viewModel.summary,
            filteredCustomers: viewModel.filteredCustomers,
            customerPickerCards: viewModel.customerPickerCards,
            customerSearchText: $viewModel.customerSearchText,
            technicianHistory: viewModel.technicianHistory,
            operationHistory: viewModel.operationHistory,
            deviceHistory: viewModel.deviceHistory,
            timeline: viewModel.timeline,
            onSelectCustomer: { viewModel.selectCustomer($0) },
            onClearSelection: { viewModel.clearSelection() },
            onReload: { Task { await viewModel.load() } }
        )
        .navigationTitle("Müşteri Analizi")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load() }
        .refreshable { await viewModel.load() }
    }

    private func mapPhase(_ phase: OperatorCustomerAnalyticsViewModel.Phase) -> CustomerAnalyticsContentView.Phase {
        switch phase {
        case .loading: return .loading
        case .ready: return .ready
        case .empty: return .empty
        case .error(let message): return .error(message)
        }
    }
}

#if DEBUG
#Preview("Customer Analytics") {
    NavigationStack {
        CustomerAnalyticsView(viewModel: .previewReady())
    }
}
#endif
