import Foundation

/// Offline-first invariants for later sync phases. Not a runtime
/// service — documentation that compile-checks as a type.
///
/// - SwiftData is the **local source of truth**. The UI and use
///   cases read and write SwiftData only.
/// - Firebase is a **remote source**. No View/ViewModel talks to
///   Firestore directly.
/// - A `SyncOperation` is enqueued against the local mutation;
///   SyncManager (5C) drains the queue toward Firebase.
/// - Firestore's own offline cache is not a substitute for this
///   queue (Phase 4 already disables it on the live data source).
enum SyncPrinciples {
    static let localSourceOfTruth = "SwiftData"
    static let remoteSource = "Firebase"
}
