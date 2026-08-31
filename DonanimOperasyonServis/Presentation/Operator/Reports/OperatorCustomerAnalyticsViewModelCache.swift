import Foundation

@MainActor
final class OperatorCustomerAnalyticsViewModelCache {
    private var storage: OperatorCustomerAnalyticsViewModel?
    private let actor: User
    private let dependencies: OperatorDependencies

    init(actor: User, dependencies: OperatorDependencies) {
        self.actor = actor
        self.dependencies = dependencies
    }

    func viewModel() -> OperatorCustomerAnalyticsViewModel {
        if let existing = storage { return existing }
        let created = OperatorCustomerAnalyticsViewModel(actor: actor, dependencies: dependencies)
        storage = created
        return created
    }
}
