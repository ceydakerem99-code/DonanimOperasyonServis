import Foundation

/// Keeps technician work-order detail ViewModels stable across shell body redraws.
@MainActor
final class TechnicianWorkOrderDetailViewModelCache {
    private var storage: [String: TechnicianWorkOrderDetailViewModel] = [:]
    private let actor: User
    private let dependencies: TechnicianDependencies
    private let locationSampler: LocationSampling

    init(
        actor: User,
        dependencies: TechnicianDependencies,
        locationSampler: LocationSampling
    ) {
        self.actor = actor
        self.dependencies = dependencies
        self.locationSampler = locationSampler
    }

    func viewModel(for id: WorkOrderID) -> TechnicianWorkOrderDetailViewModel {
        if let existing = storage[id.rawValue] {
            return existing
        }
        let created = TechnicianWorkOrderDetailViewModel(
            workOrderId: id,
            actor: actor,
            dependencies: dependencies,
            locationSampler: locationSampler
        )
        storage[id.rawValue] = created
        return created
    }
}
