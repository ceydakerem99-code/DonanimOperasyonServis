import Foundation

/// Specific notification kinds that can be delivered to a user.
enum NotificationType: String, CaseIterable, Hashable, Sendable, Codable {
    case workOrderAssigned
    case workOrderStatusChanged
    case workOrderCompleted
    case editRequestCreated
    case editRequestApproved
    case editRequestRejected
    case system
}

extension NotificationType {
    var category: NotificationCategory {
        switch self {
        case .workOrderAssigned,
             .workOrderStatusChanged,
             .workOrderCompleted:
            return .workOrder
        case .editRequestCreated,
             .editRequestApproved,
             .editRequestRejected:
            return .editRequest
        case .system:
            return .system
        }
    }

    var displayName: String {
        switch self {
        case .workOrderAssigned:       return "İş Emri Atandı"
        case .workOrderStatusChanged:  return "İş Emri Durumu Değişti"
        case .workOrderCompleted:      return "İş Emri Tamamlandı"
        case .editRequestCreated:      return "Yeni Düzenleme Talebi"
        case .editRequestApproved:     return "Düzenleme Talebi Onaylandı"
        case .editRequestRejected:     return "Düzenleme Talebi Reddedildi"
        case .system:                  return "Sistem Bildirimi"
        }
    }
}
