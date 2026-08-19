import Foundation

/// The four kinds of field work supported by the system.
enum WorkType: String, CaseIterable, Hashable, Sendable, Codable {
    case installation
    case maintenance
    case repair
    case delivery
}

extension WorkType {
    var displayName: String {
        switch self {
        case .installation: return "Kurulum"
        case .maintenance:  return "Bakım"
        case .repair:       return "Arıza"
        case .delivery:     return "Teslim"
        }
    }
}
