import Foundation

/// Raised by the remote dispatcher when a completed-work-order
/// divergence is detected. `SyncManager` persists a `SyncConflict`
/// and marks the operation `.conflict`. Nothing here chooses
/// `useLocal` / `useRemote`.
struct SyncConflictDetected: Error, Hashable, Sendable {
    var localVersion: Int
    var remoteVersion: Int
    var localReference: String?
    var remoteReference: String?
}
