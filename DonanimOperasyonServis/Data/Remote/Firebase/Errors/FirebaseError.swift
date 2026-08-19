import Foundation
import FirebaseFirestore

/// Data-layer error type for every Firebase-backed operation.
///
/// Repositories catch Firebase SDK errors (`NSError` with domains
/// like `FIRFirestoreErrorDomain`) and translate them here so the
/// upper layers only ever see either a `DomainError` (for well-known
/// cases like "not found") or a `FirebaseError` (for
/// infrastructure/plumbing failures). The raw SDK error is never
/// leaked upward.
enum FirebaseError: Error, Hashable, Sendable {

    /// Firestore reports a document does not exist.
    case notFound

    /// Firestore reports the caller is not permitted for this write.
    /// In v4 (no auth yet) this usually means the security rules
    /// rejected the operation because there is no signed-in user.
    case permissionDenied

    /// The device is offline or Firestore could not reach the
    /// backend within its timeouts.
    case networkUnavailable

    /// The document exists but its shape is not what our DTO
    /// expects (missing fields, wrong types, ...).
    case invalidDocument(reason: String)

    /// Our DTO could not be encoded to a Firestore payload. This is
    /// almost always a programmer error.
    case encodingFailed(reason: String)

    /// The Firestore payload could not be decoded to our DTO.
    case decodingFailed(reason: String)

    /// Firebase Storage returned an error while uploading,
    /// downloading, or deleting an object.
    case storageError(reason: String)

    /// Firebase is not configured (no `GoogleService-Info.plist` in
    /// the bundle). The default in Phase 4 while credentials are not
    /// checked in.
    case notConfigured

    /// Anything else. Includes the SDK's localized description so
    /// operators can still see it in logs and crash reports.
    case unknown(reason: String)
}

// MARK: - Firestore SDK error mapping

extension FirebaseError {

    /// Maps a raw error from the Firestore SDK (usually an `NSError`
    /// with domain `FIRFirestoreErrorDomain`) to our data-layer
    /// error taxonomy.
    ///
    /// Errors that come from our own encode/decode pipeline
    /// (`DecodingError`, `EncodingError`) are surfaced as
    /// `.decodingFailed` / `.encodingFailed` respectively. Anything
    /// unrecognised falls back to `.unknown`.
    static func map(_ error: Error) -> FirebaseError {
        if let already = error as? FirebaseError { return already }

        if let decoding = error as? DecodingError {
            return .decodingFailed(reason: String(describing: decoding))
        }
        if let encoding = error as? EncodingError {
            return .encodingFailed(reason: String(describing: encoding))
        }

        let nsError = error as NSError
        if nsError.domain == FirestoreErrorDomain,
           let code = FirestoreErrorCode.Code(rawValue: nsError.code) {
            switch code {
            case .notFound:         return .notFound
            case .permissionDenied: return .permissionDenied
            case .unauthenticated:  return .permissionDenied
            case .unavailable:      return .networkUnavailable
            case .deadlineExceeded: return .networkUnavailable
            case .cancelled:        return .networkUnavailable
            case .alreadyExists,
                 .failedPrecondition,
                 .aborted,
                 .outOfRange,
                 .invalidArgument,
                 .dataLoss:
                return .invalidDocument(reason: nsError.localizedDescription)
            default:
                return .unknown(reason: nsError.localizedDescription)
            }
        }

        return .unknown(reason: nsError.localizedDescription)
    }
}
