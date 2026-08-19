import Foundation

/// Classification of a work-order photo. Used by `PhotoRequirements`
/// to determine whether a work order has met its photo evidence
/// requirements for its `WorkType`.
enum PhotoCategory: String, CaseIterable, Hashable, Sendable, Codable {
    case before
    case after
    case evidenceSerialNumber
}

extension PhotoCategory {
    var displayName: String {
        switch self {
        case .before:               return "Öncesi"
        case .after:                return "Sonrası"
        case .evidenceSerialNumber: return "Seri No / Kanıt"
        }
    }
}
