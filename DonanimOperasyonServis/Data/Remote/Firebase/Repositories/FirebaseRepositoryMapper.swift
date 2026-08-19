import Foundation

/// Shared helpers used by every Firebase repository. Kept as a
/// small enum so the mapping / error-translation logic lives in
/// one place rather than being copy-pasted across 10 types.
///
/// The public repository API (Domain protocols) never surfaces
/// `FirebaseError`. Every thrown error is a `DomainError`.
enum FirebaseRepositoryMapper {

    /// Reconstructs a Domain value from a DTO. Throws
    /// `DomainError.invalidData` when the DTO's `toDomain()` returns
    /// `nil` (unknown enum raw value, invalid time range, etc.).
    static func requireDomain<DTO, Domain>(
        _ dto: DTO,
        entity: String,
        _ convert: (DTO) -> Domain?
    ) throws -> Domain {
        guard let domain = convert(dto) else {
            throw DomainError.invalidData(reason: "\(entity).decodeFailed")
        }
        return domain
    }

    /// Maps a Data-layer or SDK error onto `DomainError` so Domain
    /// and Presentation never observe `FirebaseError`.
    static func mapToDomain(_ error: Error, entity: String, id: String = "") -> Error {
        if let domain = error as? DomainError { return domain }

        let firebase: FirebaseError
        if let already = error as? FirebaseError {
            firebase = already
        } else {
            firebase = FirebaseError.map(error)
        }

        switch firebase {
        case .notFound:
            return DomainError.notFound(entity: entity, id: id)
        case .invalidDocument(let reason):
            return DomainError.invalidData(reason: reason)
        case .encodingFailed(let reason):
            return DomainError.infrastructure(underlying: "firebase.encodingFailed: \(reason)")
        case .decodingFailed(let reason):
            return DomainError.infrastructure(underlying: "firebase.decodingFailed: \(reason)")
        case .networkUnavailable:
            return DomainError.infrastructure(underlying: "firebase.networkUnavailable")
        case .permissionDenied:
            return DomainError.infrastructure(underlying: "firebase.permissionDenied")
        case .storageError(let reason):
            return DomainError.infrastructure(underlying: "firebase.storageError: \(reason)")
        case .notConfigured:
            return DomainError.infrastructure(underlying: "firebase.notConfigured")
        case .unknown(let reason):
            return DomainError.infrastructure(underlying: "firebase.unknown: \(reason)")
        }
    }

    /// Runs a Firestore-backed body and guarantees the thrown type
    /// is `DomainError`.
    static func run<T>(
        entity: String,
        id: String = "",
        _ body: () async throws -> T
    ) async throws -> T {
        do {
            return try await body()
        } catch {
            throw mapToDomain(error, entity: entity, id: id)
        }
    }
}
