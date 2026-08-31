import Foundation

/// Keeps Operator report panel ViewModels stable across shell body redraws.
@MainActor
final class OperatorReportDetailViewModelCache {
    private var storage: [AdminReportKind: OperatorReportDetailViewModel] = [:]
    private let actor: User
    private let dependencies: OperatorDependencies

    init(actor: User, dependencies: OperatorDependencies) {
        self.actor = actor
        self.dependencies = dependencies
    }

    func viewModel(for kind: AdminReportKind) -> OperatorReportDetailViewModel {
        if let existing = storage[kind] {
            return existing
        }
        let created = OperatorReportDetailViewModel(
            kind: kind,
            actor: actor,
            dependencies: dependencies
        )
        storage[kind] = created
        return created
    }
}
