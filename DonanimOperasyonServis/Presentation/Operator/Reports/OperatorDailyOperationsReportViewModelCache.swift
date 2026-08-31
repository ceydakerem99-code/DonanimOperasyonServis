import Foundation

@MainActor
final class OperatorDailyOperationsReportViewModelCache {
    private var storage: OperatorDailyOperationsReportViewModel?
    private let actor: User
    private let dependencies: OperatorDependencies

    init(actor: User, dependencies: OperatorDependencies) {
        self.actor = actor
        self.dependencies = dependencies
    }

    func viewModel() -> OperatorDailyOperationsReportViewModel {
        if let existing = storage { return existing }
        let created = OperatorDailyOperationsReportViewModel(actor: actor, dependencies: dependencies)
        storage = created
        return created
    }
}
