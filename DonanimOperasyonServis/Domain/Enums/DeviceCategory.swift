import Foundation

/// Categories of hardware serviced by the operations team.
enum DeviceCategory: String, CaseIterable, Hashable, Sendable, Codable {
    case pos
    case tablet
    case printer
    case barcodeScanner
    case computer
    case cashRegister
    case other
}

extension DeviceCategory {
    var displayName: String {
        switch self {
        case .pos:            return "POS"
        case .tablet:         return "Tablet"
        case .printer:        return "Yazıcı"
        case .barcodeScanner: return "Barkod Okuyucu"
        case .computer:       return "Bilgisayar"
        case .cashRegister:   return "Kasa"
        case .other:          return "Diğer"
        }
    }
}
