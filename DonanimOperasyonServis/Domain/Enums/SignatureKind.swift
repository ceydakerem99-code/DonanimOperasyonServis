import Foundation

/// Whose signature is being captured on a work order.
enum SignatureKind: String, CaseIterable, Hashable, Sendable, Codable {
    case technician
    case customer
}

extension SignatureKind {
    var displayName: String {
        switch self {
        case .technician: return "Teknisyen İmzası"
        case .customer:   return "Müşteri İmzası"
        }
    }
}
