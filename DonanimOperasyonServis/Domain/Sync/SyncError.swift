import Foundation

/// Domain-level sync failure taxonomy. Independent of
/// `FirebaseError` and of any SDK. Data-layer mappers (later
/// phases) translate remote/transport errors into this type
/// **before** they re-enter Domain.
enum SyncError: Error, Hashable, Sendable {
    /// Device is offline or the remote call timed out.
    case networkUnavailable

    /// Caller is not permitted to apply this operation remotely.
    case unauthorized

    /// The target entity no longer exists on the remote.
    case notFound

    /// The queued payload cannot be applied (shape, validation).
    case invalidPayload

    /// Local and remote versions/state cannot be merged automatically.
    case conflict

    /// Transient remote failure (5xx, unavailable backend).
    case serverError

    /// Catch-all. Carries a diagnostic string for logs.
    case unknown(reason: String)
}
