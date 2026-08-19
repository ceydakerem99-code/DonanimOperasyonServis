import Foundation

/// Report modules shown on the admin reports panel (prototip).
enum AdminReportKind: String, Hashable, Sendable, CaseIterable, Identifiable {
    case workOrders
    case technicianPerformance
    case customerSummary
    case pauseReasons
    case signatures
    case photos

    var id: String { rawValue }

    var title: String {
        switch self {
        case .workOrders: return "İş Emri Raporu"
        case .technicianPerformance: return "Teknisyen Performansı"
        case .customerSummary: return "Müşteri Raporu"
        case .pauseReasons: return "Bekleme Nedeni Raporu"
        case .signatures: return "İmza Raporu"
        case .photos: return "Fotoğraf Raporu"
        }
    }

    var systemImage: String {
        switch self {
        case .workOrders: return "doc.text"
        case .technicianPerformance: return "person.3"
        case .customerSummary: return "building.2"
        case .pauseReasons: return "pause.circle"
        case .signatures: return "signature"
        case .photos: return "photo"
        }
    }

    var subtitle: String {
        switch self {
        case .workOrders: return "Durum dağılımı ve tamamlanma özeti"
        case .technicianPerformance: return "Teknisyen bazlı iş yükü"
        case .customerSummary: return "Müşteri bazlı iş emri özeti"
        case .pauseReasons: return "Duraklatma nedenleri dağılımı"
        case .signatures: return "Tamamlanan imza kayıtları"
        case .photos: return "Yüklenen fotoğraf özeti"
        }
    }
}
