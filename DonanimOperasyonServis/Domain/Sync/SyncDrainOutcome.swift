import Foundation

/// Result of a manual `syncPending()` drain. Distinguishes "we did
/// not attempt remote because the device is offline" from "we ran
/// the FIFO queue" — including when every row then failed, was
/// held for a conflict, or succeeded.
enum SyncDrainOutcome: Hashable, Sendable {
    /// Reachability was true. Pending/due rows were processed
    /// sequentially through the existing state machine.
    case completed
    /// Reachability was false. No remote call was made and no
    /// `SyncOperation` retry metadata was mutated.
    case deferredOffline

    var displayName: String {
        switch self {
        case .completed:        return "Senkronizasyon Tamamlandı"
        case .deferredOffline:  return "Çevrimdışı, senkronizasyon ertelendi"
        }
    }

    var logLabel: String {
        switch self {
        case .completed: return "completed"
        case .deferredOffline: return "deferredOffline"
        }
    }
}
