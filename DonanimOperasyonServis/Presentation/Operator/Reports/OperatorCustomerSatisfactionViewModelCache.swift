import Foundation

@MainActor
final class OperatorCustomerSatisfactionViewModelCache {
    private var storage: OperatorCustomerSatisfactionViewModel?
    private let actor: User
    private let dependencies: OperatorDependencies

    init(actor: User, dependencies: OperatorDependencies) {
        self.actor = actor
        self.dependencies = dependencies
    }

    func viewModel() -> OperatorCustomerSatisfactionViewModel {
        if let existing = storage { return existing }
        let created = OperatorCustomerSatisfactionViewModel(actor: actor, dependencies: dependencies)
        storage = created
        return created
    }
}
