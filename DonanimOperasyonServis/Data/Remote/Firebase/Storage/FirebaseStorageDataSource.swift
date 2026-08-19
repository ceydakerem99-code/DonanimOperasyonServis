import Foundation

/// Thin, testable abstraction over Firebase Storage.
///
/// Two conforming implementations exist:
///
/// - `LiveFirebaseStorageDataSource` — wraps the real Storage SDK.
/// - `FakeFirebaseStorageDataSource` (test target) — an in-memory
///   actor that stores `Data` blobs keyed by path.
///
/// Phase 4 only exposes the primitive operations. The Technician
/// capture / upload workflow (UI, camera, signature canvas) is
/// explicitly out of scope and lands in a later phase.
protocol FirebaseStorageDataSource: Sendable {

    /// Uploads `data` to `path`. Overwrites an existing object at
    /// the same path. Returns the canonical path so callers can
    /// persist it as `storagePath` on the related Firestore DTO.
    @discardableResult
    func upload(data: Data, to path: FirebaseStoragePath) async throws -> String

    /// Downloads the object at `path`. Throws `.notFound` when the
    /// object does not exist.
    func download(from path: FirebaseStoragePath) async throws -> Data

    /// Deletes the object at `path`. A missing object is treated as
    /// success (idempotent delete).
    func delete(_ path: FirebaseStoragePath) async throws
}
