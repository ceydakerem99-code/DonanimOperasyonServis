import Foundation

@MainActor
final class CustomerSatisfactionViewModelCache {
    private var storage: CustomerSatisfactionViewModel?
    private let actor: User
    private let dependencies: AdminDependencies

    init(actor: User, dependencies: AdminDependencies) {
        self.actor = actor
        self.dependencies = dependencies
    }

    func viewModel() -> CustomerSatisfactionViewModel {
        if let existing = storage { return existing }
        let created = CustomerSatisfactionViewModel(actor: actor, dependencies: dependencies)
        storage = created
        return created
    }
}
