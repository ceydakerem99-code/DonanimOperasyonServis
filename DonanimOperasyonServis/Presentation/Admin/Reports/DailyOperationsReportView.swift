import SwiftUI

struct DailyOperationsReportView: View {
    @Bindable var viewModel: DailyOperationsReportViewModel
    var onSelectWorkOrder: ((WorkOrderID) -> Void)?

    var body: some View {
        DailyOperationsContentView(
            phase: mapPhase(viewModel.phase),
            showsLoadingIndicator: viewModel.showsLoadingIndicator,
            hasCachedContent: viewModel.hasCachedContent,
            report: viewModel.report,
            selectedDay: Binding(
                get: { viewModel.selectedDay },
                set: { viewModel.selectDay($0) }
            ),
            onPreviousDay: { viewModel.selectPreviousDay() },
            onNextDay: { viewModel.selectNextDay() },
            onReload: { Task { await viewModel.load() } },
            onSelectWorkOrder: onSelectWorkOrder
        )
        .navigationTitle("Günlük Operasyon Raporu")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load() }
        .refreshable { await viewModel.load() }
    }

    private func mapPhase(_ phase: DailyOperationsReportViewModel.Phase) -> DailyOperationsContentView.Phase {
        switch phase {
        case .loading: return .loading
        case .ready: return .ready
        case .empty: return .empty
        case .error(let message): return .error(message)
        }
    }
}

struct OperatorDailyOperationsReportView: View {
    @Bindable var viewModel: OperatorDailyOperationsReportViewModel
    var onSelectWorkOrder: ((WorkOrderID) -> Void)?

    var body: some View {
        DailyOperationsContentView(
            phase: mapPhase(viewModel.phase),
            showsLoadingIndicator: viewModel.showsLoadingIndicator,
            hasCachedContent: viewModel.hasCachedContent,
            report: viewModel.report,
            selectedDay: Binding(
                get: { viewModel.selectedDay },
                set: { viewModel.selectDay($0) }
            ),
            onPreviousDay: { viewModel.selectPreviousDay() },
            onNextDay: { viewModel.selectNextDay() },
            onReload: { Task { await viewModel.load() } },
            onSelectWorkOrder: onSelectWorkOrder
        )
        .navigationTitle("Günlük Operasyon Raporu")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load() }
        .refreshable { await viewModel.load() }
    }

    private func mapPhase(_ phase: OperatorDailyOperationsReportViewModel.Phase) -> DailyOperationsContentView.Phase {
        switch phase {
        case .loading: return .loading
        case .ready: return .ready
        case .empty: return .empty
        case .error(let message): return .error(message)
        }
    }
}

#if DEBUG
#Preview("Daily Operations Report") {
    NavigationStack {
        DailyOperationsReportView(
            viewModel: .previewReady(),
            onSelectWorkOrder: nil
        )
    }
}
#endif
