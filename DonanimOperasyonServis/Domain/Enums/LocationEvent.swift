import Foundation

/// Named GPS capture events associated with a work order. Used by
/// `CompletionRequirements` to verify that mandatory location samples
/// have been recorded.
enum LocationEvent: String, CaseIterable, Hashable, Sendable, Codable {
    case enRoute
    case arrived
    case completed
}

extension LocationEvent {
    var displayName: String {
        switch self {
        case .enRoute:   return "Yola Çıkış"
        case .arrived:   return "Varış"
        case .completed: return "Tamamlanma"
        }
    }
}
