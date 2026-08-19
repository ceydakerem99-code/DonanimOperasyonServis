import Foundation

/// Lifecycle of an `EditRequest`. Transitions are governed by
/// `EditRequestStateMachine`. Both `approved` and `rejected` are
/// terminal — a decided edit request cannot be re-decided.
enum EditRequestStatus: String, CaseIterable, Hashable, Sendable, Codable {
    case pending
    case approved
    case rejected
}

extension EditRequestStatus {
    var displayName: String {
        switch self {
        case .pending:  return "Bekliyor"
        case .approved: return "Onaylandı"
        case .rejected: return "Reddedildi"
        }
    }

    var isTerminal: Bool { self != .pending }
}
