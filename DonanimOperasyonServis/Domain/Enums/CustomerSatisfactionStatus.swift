import Foundation

/// Lifecycle of a post-service customer satisfaction survey tied to a
/// completed work order.
enum CustomerSatisfactionStatus: String, CaseIterable, Hashable, Sendable, Codable {
    case pending
    case submitted
    case expired
}

extension CustomerSatisfactionStatus {
    var displayName: String {
        switch self {
        case .pending:   return "Bekliyor"
        case .submitted: return "Yanıtlandı"
        case .expired:   return "Süresi Doldu"
        }
    }

    var isTerminal: Bool { self != .pending }
}
