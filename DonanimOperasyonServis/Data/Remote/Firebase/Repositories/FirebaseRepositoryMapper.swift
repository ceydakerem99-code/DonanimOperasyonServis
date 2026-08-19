import Foundation

/// Shared helpers used by every Firebase repository. Kept as a
/// small enum so the mapping / error-translation logic lives in
/// one place rather than being copy-pasted across 10 types.
enum FirebaseRepositoryMapper {

    /// Reconstructs a Domain value from a DTO. Throws
    /// `.invalidDocument` when the DTO's `toDomain()` returns `nil`
    /// (unknown enum raw value, etc.).
    static func requireDomain<DTO, Domain>(
        _ dto: DTO,
        entity: String,
        _ convert: (DTO) -> Domain?
    ) throws -> Domain {
        guard let domain = convert(dto) else {
            throw FirebaseError.invalidDocument(reason: "\(entity).decodeFailed")
        }
        return domain
    }

    /// Translates a `.notFound` from the data source into the
    /// Domain-level `.notFound` so use cases keep seeing the same
    /// error they already handle from SwiftData repositories.
    static func mapNotFound(_ error: Error, entity: String, id: String) -> Error {
        if case .notFound = error as? FirebaseError {
            return DomainError.notFound(entity: entity, id: id)
        }
        return error
    }
}
