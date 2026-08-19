import Foundation

/// The set of photo categories that must be present on a work order
/// of a given `WorkType` before it can be completed.
///
/// This is a pure lookup — it does not talk to the photo store; it
/// merely tells `CompletionRequirements` which categories to look
/// for in the caller-provided evidence bundle.
///
/// Requirements per work type:
///
///     installation → [before, after]
///     maintenance  → [before, after]
///     repair       → [before, after, evidenceSerialNumber]
///     delivery     → [evidenceSerialNumber]
enum PhotoRequirements {

    static let requirements: [WorkType: [PhotoCategory]] = [
        .installation: [.before, .after],
        .maintenance:  [.before, .after],
        .repair:       [.before, .after, .evidenceSerialNumber],
        .delivery:     [.evidenceSerialNumber]
    ]

    /// The required photo categories for a given work type. Returns
    /// an empty array for work types that have no photo requirement
    /// (there are none in v1, but the API tolerates future
    /// additions).
    static func requiredCategories(for workType: WorkType) -> [PhotoCategory] {
        requirements[workType] ?? []
    }

    /// Given a set of already-captured photos, returns the
    /// categories that are still missing for the specified
    /// work type. Order matches `requiredCategories(for:)`.
    static func missingCategories(
        for workType: WorkType,
        given photos: [WorkOrderPhoto]
    ) -> [PhotoCategory] {
        let presentCategories = Set(photos.map(\.category))
        return requiredCategories(for: workType).filter { !presentCategories.contains($0) }
    }
}
