import SwiftUI

struct CustomerSatisfactionView: View {
    @Bindable var viewModel: CustomerSatisfactionViewModel

    var body: some View {
        CustomerSatisfactionContentView(
            phase: mapPhase(viewModel.phase),
            showsLoadingIndicator: viewModel.showsLoadingIndicator,
            hasCachedContent: viewModel.hasCachedContent,
            summary: viewModel.summary,
            ratingBars: viewModel.ratingBars,
            technicianSummaries: viewModel.technicianSummaries,
            recentEntries: viewModel.recentEntries,
            onReload: { Task { await viewModel.load() } }
        )
        .navigationTitle("Müşteri Memnuniyeti")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load() }
        .refreshable { await viewModel.load() }
    }

    private func mapPhase(_ phase: CustomerSatisfactionViewModel.Phase) -> CustomerSatisfactionContentView.Phase {
        switch phase {
        case .loading: return .loading
        case .ready: return .ready
        case .empty: return .empty
        case .error(let message): return .error(message)
        }
    }
}

struct OperatorCustomerSatisfactionView: View {
    @Bindable var viewModel: OperatorCustomerSatisfactionViewModel

    var body: some View {
        CustomerSatisfactionContentView(
            phase: mapPhase(viewModel.phase),
            showsLoadingIndicator: viewModel.showsLoadingIndicator,
            hasCachedContent: viewModel.hasCachedContent,
            summary: viewModel.summary,
            ratingBars: viewModel.ratingBars,
            technicianSummaries: viewModel.technicianSummaries,
            recentEntries: viewModel.recentEntries,
            onReload: { Task { await viewModel.load() } }
        )
        .navigationTitle("Müşteri Memnuniyeti")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load() }
        .refreshable { await viewModel.load() }
    }

    private func mapPhase(_ phase: OperatorCustomerSatisfactionViewModel.Phase) -> CustomerSatisfactionContentView.Phase {
        switch phase {
        case .loading: return .loading
        case .ready: return .ready
        case .empty: return .empty
        case .error(let message): return .error(message)
        }
    }
}

#if DEBUG
#Preview("Customer Satisfaction") {
    NavigationStack {
        CustomerSatisfactionView(
            viewModel: .previewReady()
        )
    }
}
#endif
