import Foundation

/// Bundle of evidence associated with a work order at the moment
/// completion is being considered. Constructed by the caller from
/// its repositories and passed into `CompletionRequirements.check`.
///
/// Kept as a plain struct so tests can construct it with fixtures.
struct CompletionContext: Hashable, Sendable {
    let workType: WorkType
    let notes: [WorkOrderNote]
    let photos: [WorkOrderPhoto]
    let locations: [WorkOrderLocation]
    let signatures: [Signature]

    init(
        workType: WorkType,
        notes: [WorkOrderNote] = [],
        photos: [WorkOrderPhoto] = [],
        locations: [WorkOrderLocation] = [],
        signatures: [Signature] = []
    ) {
        self.workType = workType
        self.notes = notes
        self.photos = photos
        self.locations = locations
        self.signatures = signatures
    }
}

/// Pure domain policy that decides whether a work order is
/// completeness-ready.
///
/// The rules verified for v1 are:
///
/// 1. At least one service note is present.
/// 2. Every `PhotoCategory` returned by `PhotoRequirements` for the
///    work type is represented by at least one photo.
/// 3. GPS samples are captured for every `LocationEvent` case
///    (`enRoute`, `arrived`, `completed`).
/// 4. A technician signature is present.
/// 5. A customer signature is present.
///
/// Rather than short-circuiting on the first failure, all missing
/// items are collected so the UI can render one accurate checklist
/// instead of forcing the technician round-trip once per gap.
enum CompletionRequirements {

    /// Result type returned by `check(_:)`. Kept separate from
    /// `DomainError` so callers can decide whether to translate it
    /// into `DomainError.incompleteWorkOrder` or handle it inline.
    struct MissingRequirements: Error, Hashable, Sendable {
        let items: [MissingRequirement]
    }

    /// Validates a completion context and either returns success or
    /// a `MissingRequirements` error listing every gap.
    static func check(_ context: CompletionContext) -> Result<Void, MissingRequirements> {
        var missing: [MissingRequirement] = []

        // 1. Notes
        if context.notes.isEmpty {
            missing.append(.missingNote)
        }

        // 2. Photos (per work-type)
        let missingPhotos = PhotoRequirements.missingCategories(
            for: context.workType,
            given: context.photos
        )
        for category in missingPhotos {
            missing.append(.missingPhoto(category))
        }

        // 3. GPS samples per event
        let capturedEvents = Set(context.locations.map(\.event))
        for event in LocationEvent.allCases where !capturedEvents.contains(event) {
            missing.append(.missingLocation(event))
        }

        // 4 & 5. Signatures
        let capturedSignatureKinds = Set(context.signatures.map(\.kind))
        if !capturedSignatureKinds.contains(.technician) {
            missing.append(.missingTechnicianSignature)
        }
        if !capturedSignatureKinds.contains(.customer) {
            missing.append(.missingCustomerSignature)
        }

        if missing.isEmpty {
            return .success(())
        } else {
            return .failure(MissingRequirements(items: missing))
        }
    }
}
