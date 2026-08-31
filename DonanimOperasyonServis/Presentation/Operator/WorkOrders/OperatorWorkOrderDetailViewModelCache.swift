import Foundation

/// Keeps Operator work-order detail ViewModels stable across shell body redraws.
@MainActor
final class OperatorWorkOrderDetailViewModelCache {
    private var storage: [String: OperatorWorkOrderDetailViewModel] = [:]
    private let actor: User
    private let dependencies: OperatorDependencies

    init(actor: User, dependencies: OperatorDependencies) {
        self.actor = actor
        self.dependencies = dependencies
    }

    func viewModel(for id: WorkOrderID) -> OperatorWorkOrderDetailViewModel {
        if let existing = storage[id.rawValue] {
            return existing
        }
        let created = OperatorWorkOrderDetailViewModel(
            workOrderId: id,
            actor: actor,
            dependencies: dependencies
        )
        storage[id.rawValue] = created
        return created
    }
}
