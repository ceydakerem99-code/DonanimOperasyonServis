import Foundation
import FirebaseFirestore

/// Live Firestore runtime policy.
///
/// SwiftData is the local source of truth. Firestore is a remote
/// source only — its own disk persistence / offline cache must not
/// stand in for the Phase 5 SyncManager.
enum LiveFirestoreConfiguration {

    /// Disk-backed Firestore cache is disabled.
    static let isPersistentCacheEnabled = false

    /// Settings use an in-memory SDK cache, never `PersistentCacheSettings`.
    static var usesMemoryCacheSettings: Bool {
        makeSettings().cacheSettings is MemoryCacheSettings
    }

    /// Document reads go to the backend, not a local Firestore cache.
    static let usesServerReadSource = true

    /// `set` waits for the SDK write to complete, matching `delete`
    /// and `commit`.
    static let awaitsDocumentWrites = true

    /// Source used by every live read.
    static var readSource: FirestoreSource { .server }

    /// Settings applied to `Firestore.firestore()` before any I/O.
    /// Memory cache may still exist inside the SDK process; it is
    /// not a durable local store and is never treated as source of
    /// truth.
    static func makeSettings() -> FirestoreSettings {
        let settings = FirestoreSettings()
        settings.cacheSettings = MemoryCacheSettings()
        return settings
    }

    /// Encodes a DTO with `Firestore.Encoder` so `Date` fields become
    /// native `Timestamp` values. Used by both single-document `set`
    /// and batch `commit` so the two write paths produce the same
    /// payload shape.
    static func encode<T: Encodable>(_ value: T) throws -> [String: Any] {
        do {
            return try Firestore.Encoder().encode(value)
        } catch {
            throw FirebaseError.map(error)
        }
    }

    /// True when `key` in an encoded payload is a Firestore Timestamp
    /// (as opposed to a `Date`, ISO string, or millisecond number).
    static func isTimestamp(_ value: Any?) -> Bool {
        value is Timestamp
    }
}
