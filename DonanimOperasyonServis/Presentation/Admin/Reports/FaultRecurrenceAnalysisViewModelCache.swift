import Foundation

@MainActor
final class FaultRecurrenceAnalysisViewModelCache {
    private var storage: FaultRecurrenceAnalysisViewModel?
    private let actor: User
    private let dependencies: AdminDependencies

    init(actor: User, dependencies: AdminDependencies) {
        self.actor = actor
        self.dependencies = dependencies
    }

    func viewModel() -> FaultRecurrenceAnalysisViewModel {
        if let existing = storage { return existing }
        let created = FaultRecurrenceAnalysisViewModel(actor: actor, dependencies: dependencies)
        storage = created
        return created
    }
}
