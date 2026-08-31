import Foundation

@MainActor
final class OperatorFaultRecurrenceAnalysisViewModelCache {
    private var storage: OperatorFaultRecurrenceAnalysisViewModel?
    private let actor: User
    private let dependencies: OperatorDependencies

    init(actor: User, dependencies: OperatorDependencies) {
        self.actor = actor
        self.dependencies = dependencies
    }

    func viewModel() -> OperatorFaultRecurrenceAnalysisViewModel {
        if let existing = storage { return existing }
        let created = OperatorFaultRecurrenceAnalysisViewModel(actor: actor, dependencies: dependencies)
        storage = created
        return created
    }
}
