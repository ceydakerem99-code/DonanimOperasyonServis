import Foundation

/// Keeps Admin report panel ViewModels stable across shell body redraws and
/// nested report → work-order report navigation.
@MainActor
final class AdminReportDetailViewModelCache {
    private var storage: [AdminReportKind: AdminReportDetailViewModel] = [:]
    private let actor: User
    private let dependencies: AdminDependencies

    init(actor: User, dependencies: AdminDependencies) {
        self.actor = actor
        self.dependencies = dependencies
    }

    func viewModel(for kind: AdminReportKind) -> AdminReportDetailViewModel {
        if let existing = storage[kind] {
            return existing
        }
        let created = AdminReportDetailViewModel(
            kind: kind,
            actor: actor,
            dependencies: dependencies
        )
        storage[kind] = created
        return created
    }
}
