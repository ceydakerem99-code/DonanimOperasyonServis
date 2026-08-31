import Foundation

/// Customer-facing satisfaction score on a 1–5 scale.
enum CustomerSatisfactionRating: Int, CaseIterable, Hashable, Sendable, Codable {
    case one = 1
    case two = 2
    case three = 3
    case four = 4
    case five = 5
}

extension CustomerSatisfactionRating {
    var displayName: String {
        switch self {
        case .one:   return "1"
        case .two:   return "2"
        case .three: return "3"
        case .four:  return "4"
        case .five:  return "5"
        }
    }

    var sortOrder: Int { rawValue }
}
