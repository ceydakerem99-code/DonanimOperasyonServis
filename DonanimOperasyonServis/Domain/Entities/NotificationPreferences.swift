import Foundation

/// Stable preference keys for in-app notification display and
/// sync/network banners. Operational keys mirror `NotificationType`
/// raw values so inbox filtering stays 1:1 with stored notifications.
///
/// System sync/network keys are **display-only** preferences — they
/// do not invent new `NotificationType` cases and never suppress
/// work-order or sync data writes.
enum NotificationPreferenceKey: String, CaseIterable, Hashable, Sendable, Codable {
    case workOrderAssigned
    case workOrderStatusChanged
    case workOrderCompleted
    case editRequestCreated
    case editRequestApproved
    case editRequestRejected
    case system
    case networkDisconnected
    case syncPending
    case syncCompleted
    case syncConflict

    var displayName: String {
        switch self {
        case .workOrderAssigned: return "Yeni iş atandı"
        case .workOrderStatusChanged: return "İş emri güncellendi"
        case .workOrderCompleted: return "İş tamamlandı"
        case .editRequestCreated: return "Düzenleme talebi geldi"
        case .editRequestApproved: return "Talep onaylandı"
        case .editRequestRejected: return "Talep reddedildi"
        case .system: return "Sistem bildirimleri"
        case .networkDisconnected: return "İnternet bağlantısı"
        case .syncPending: return "Senkronizasyon bekliyor"
        case .syncCompleted: return "Senkronizasyon tamamlandı"
        case .syncConflict: return "Senkronizasyon çakışması"
        }
    }

    var isOperational: Bool {
        switch self {
        case .workOrderAssigned,
             .workOrderStatusChanged,
             .workOrderCompleted,
             .editRequestCreated,
             .editRequestApproved,
             .editRequestRejected:
            return true
        case .system,
             .networkDisconnected,
             .syncPending,
             .syncCompleted,
             .syncConflict:
            return false
        }
    }

    init?(notificationType: NotificationType) {
        self.init(rawValue: notificationType.rawValue)
    }
}

/// Per-user notification display preferences. Missing keys default to
/// **enabled** so older profiles without the map stay fully notified.
struct NotificationPreferences: Hashable, Sendable, Codable, Equatable {
    var enabledByKey: [String: Bool]

    static let `default` = NotificationPreferences(enabledByKey: [:])

    init(enabledByKey: [String: Bool] = [:]) {
        self.enabledByKey = enabledByKey
    }

    func isEnabled(_ key: NotificationPreferenceKey) -> Bool {
        enabledByKey[key.rawValue] ?? true
    }

    mutating func set(_ key: NotificationPreferenceKey, enabled: Bool) {
        enabledByKey[key.rawValue] = enabled
    }

    /// Inbox display gate for persisted `AppNotification` rows.
    func allowsDisplay(of type: NotificationType) -> Bool {
        guard let key = NotificationPreferenceKey(notificationType: type) else {
            return true
        }
        return isEnabled(key)
    }
}

/// Which preference toggles each role may configure. Derived from
/// existing `NotificationType` coverage + role product surfaces —
/// not a new RBAC matrix inventing types.
enum NotificationPreferencePolicy {
    static func visibleKeys(for role: UserRole) -> [NotificationPreferenceKey] {
        switch role {
        case .technician:
            return [
                .workOrderAssigned,
                .workOrderStatusChanged,
                .editRequestApproved,
                .editRequestRejected,
                .system,
                .networkDisconnected,
                .syncPending,
                .syncCompleted,
                .syncConflict
            ]
        case .operator:
            return [
                .workOrderAssigned,
                .workOrderStatusChanged,
                .workOrderCompleted,
                .editRequestCreated,
                .editRequestApproved,
                .editRequestRejected,
                .system,
                .networkDisconnected,
                .syncPending,
                .syncCompleted,
                .syncConflict
            ]
        case .admin:
            return [
                .system,
                .networkDisconnected,
                .syncPending,
                .syncCompleted,
                .syncConflict
            ]
        }
    }

    static func operationalKeys(for role: UserRole) -> [NotificationPreferenceKey] {
        visibleKeys(for: role).filter(\.isOperational)
    }

    static func systemKeys(for role: UserRole) -> [NotificationPreferenceKey] {
        visibleKeys(for: role).filter { !$0.isOperational }
    }
}
