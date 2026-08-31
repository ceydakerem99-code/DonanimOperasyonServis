import Foundation

@MainActor
final class CustomerAnalyticsViewModelCache {
    private var storage: CustomerAnalyticsViewModel?
    private let actor: User
    private let dependencies: AdminDependencies

    init(actor: User, dependencies: AdminDependencies) {
        self.actor = actor
        self.dependencies = dependencies
    }

    func viewModel() -> CustomerAnalyticsViewModel {
        if let existing = storage { return existing }
        let created = CustomerAnalyticsViewModel(actor: actor, dependencies: dependencies)
        storage = created
        return created
    }
}
