import Foundation

/// The three fixed roles supported by the system. New roles cannot be
/// created at runtime — permission changes require a code change plus
/// a new deploy of `RoleAccessPolicy` and Firestore Security Rules.
///
/// The `operator` case represents the Turkish "Operasyon Yetkilisi"
/// role. The alternative name "Servis Yetkilisi" is not used anywhere
/// in the app; there is exactly one operator role.
enum UserRole: String, CaseIterable, Hashable, Sendable, Codable {
    case admin
    case `operator`
    case technician
}

extension UserRole {
    /// Turkish label displayed to end users.
    var displayName: String {
        switch self {
        case .admin:      return "Admin"
        case .operator:   return "Operasyon Yetkilisi"
        case .technician: return "Teknisyen"
        }
    }
}
