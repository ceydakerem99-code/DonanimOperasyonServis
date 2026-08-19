import Foundation

/// Version triple used by reconciliation. These are **not** a new
/// versioning scheme — they are the Phase 5A `SyncOperation`
/// meanings, supplied as facts:
///
/// - `localVersion`: local revision of the entity
/// - `remoteVersion`: current remote revision
/// - `lastSyncedRemoteVersion`: last remote revision this device
///   observed (`SyncOperation.remoteVersion` at enqueue / last sync)
///
/// `nil` or a negative value is **invalid**. Invalid versions never
/// auto-prefer remote.
struct ReconciliationVersionState: Hashable, Sendable {
    var localVersion: Int?
    var remoteVersion: Int?
    var lastSyncedRemoteVersion: Int?

    static let unknown = ReconciliationVersionState(
        localVersion: nil,
        remoteVersion: nil,
        lastSyncedRemoteVersion: nil
    )
}

enum EntityVersionPolicy {

    /// `0` is valid ("never synced"). Negative and `nil` are not.
    static func isValid(_ version: Int?) -> Bool {
        guard let version else { return false }
        return version >= 0
    }

    enum RemoteProgress: Hashable, Sendable {
        case unknown
        case unchanged
        case newer
        case older
    }

    static func remoteProgress(
        current remoteVersion: Int?,
        lastSynced lastSyncedRemoteVersion: Int?
    ) -> RemoteProgress {
        guard isValid(remoteVersion), isValid(lastSyncedRemoteVersion),
              let remoteVersion, let lastSynced = lastSyncedRemoteVersion
        else { return .unknown }
        if remoteVersion == lastSynced { return .unchanged }
        if remoteVersion > lastSynced { return .newer }
        return .older
    }

    static func allValid(_ state: ReconciliationVersionState) -> Bool {
        isValid(state.localVersion)
            && isValid(state.remoteVersion)
            && isValid(state.lastSyncedRemoteVersion)
    }
}
