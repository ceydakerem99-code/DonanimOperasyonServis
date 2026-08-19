import Foundation

/// Lifecycle of a `SyncOperation`. Transitions are governed by
/// `SyncStatusStateMachine`.
enum SyncStatus: String, CaseIterable, Hashable, Sendable, Codable {
    case pending
    case inProgress
    case succeeded
    case failed
    case conflict
}

extension SyncStatus {
    var displayName: String {
        switch self {
        case .pending:    return "Bekliyor"
        case .inProgress: return "Senkronize Ediliyor"
        case .succeeded:  return "Başarılı"
        case .failed:     return "Başarısız"
        case .conflict:   return "Çakışma"
        }
    }

    /// `succeeded`, `failed`, and `conflict` do not leave through
    /// the state machine. A retry of a failed operation is a **new
    /// attempt on the same row** that 5B will reset to `pending`;
    /// that reset is not a domain transition in 5A.
    var isTerminal: Bool {
        switch self {
        case .succeeded, .failed, .conflict: return true
        case .pending, .inProgress:          return false
        }
    }
}
