import Foundation

/// Explicit resolution decision for a persisted `SyncConflict`.
///
/// The resolver never infers a winner: a caller must pass one of
/// these values. `unresolved` leaves the record open; it is not an
/// automatic fallback to local or remote.
enum ConflictResolutionDecision: String, CaseIterable, Hashable, Sendable, Codable {
    case useLocal
    case useRemote
    case unresolved

    /// Stored on `SyncConflict.resolution` only when the conflict
    /// is actually decided. `unresolved` does not write a choice.
    var storedResolution: SyncConflictResolutionChoice? {
        switch self {
        case .useLocal: return .useLocal
        case .useRemote: return .useRemote
        case .unresolved: return nil
        }
    }

    var displayName: String {
        switch self {
        case .useLocal:    return "Yerel Veriyi Kullan"
        case .useRemote:   return "Sunucu Verisini Kullan"
        case .unresolved:  return "Çözülmedi"
        }
    }
}

extension SyncConflictResolutionChoice {
    var asDecision: ConflictResolutionDecision {
        switch self {
        case .useLocal: return .useLocal
        case .useRemote: return .useRemote
        }
    }
}
