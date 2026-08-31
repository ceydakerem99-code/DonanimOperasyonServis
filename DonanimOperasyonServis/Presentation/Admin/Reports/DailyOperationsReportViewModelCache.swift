import Foundation

@MainActor
final class DailyOperationsReportViewModelCache {
    private var storage: DailyOperationsReportViewModel?
    private let actor: User
    private let dependencies: AdminDependencies

    init(actor: User, dependencies: AdminDependencies) {
        self.actor = actor
        self.dependencies = dependencies
    }

    func viewModel() -> DailyOperationsReportViewModel {
        if let existing = storage { return existing }
        let created = DailyOperationsReportViewModel(actor: actor, dependencies: dependencies)
        storage = created
        return created
    }
}
