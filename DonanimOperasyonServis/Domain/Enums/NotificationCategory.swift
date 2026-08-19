import Foundation

/// High-level grouping for user-facing notifications. Used by the
/// notifications inbox to route/filter items.
enum NotificationCategory: String, CaseIterable, Hashable, Sendable, Codable {
    case workOrder
    case editRequest
    case system
}

extension NotificationCategory {
    var displayName: String {
        switch self {
        case .workOrder:   return "İş Emri"
        case .editRequest: return "Düzenleme Talebi"
        case .system:      return "Sistem"
        }
    }
}
