import Foundation

/// Report modules shown on the admin reports panel (prototip).
enum AdminReportKind: String, Hashable, Sendable, CaseIterable, Identifiable {
    case workOrders
    case technicianPerformance
    case pauseReasons
    case signatures
    case photos
    case customerAnalytics
    case customerSatisfaction
    case faultRecurrence
    case dailyOperations

    var id: String { rawValue }

    var title: String {
        switch self {
        case .workOrders: return "İş Emri Raporu"
        case .technicianPerformance: return "Teknisyen Performansı"
        case .pauseReasons: return "Bekleme Nedeni Raporu"
        case .signatures: return "İmza Raporu"
        case .photos: return "Fotoğraf Raporu"
        case .customerAnalytics: return "Müşteri Analizi"
        case .customerSatisfaction: return "Müşteri Memnuniyeti"
        case .faultRecurrence: return "Arıza Tekrar Analizi"
        case .dailyOperations: return "Günlük Operasyon Raporu"
        }
    }

    var systemImage: String {
        switch self {
        case .workOrders: return "doc.text"
        case .technicianPerformance: return "person.3"
        case .pauseReasons: return "pause.circle"
        case .signatures: return "signature"
        case .photos: return "photo"
        case .customerAnalytics: return "chart.line.uptrend.xyaxis"
        case .customerSatisfaction: return "star.bubble"
        case .faultRecurrence: return "arrow.triangle.2.circlepath"
        case .dailyOperations: return "calendar.badge.clock"
        }
    }

    var subtitle: String {
        switch self {
        case .workOrders: return "Durum dağılımı ve tamamlanma özeti"
        case .technicianPerformance: return "Teknisyen bazlı iş yükü"
        case .pauseReasons: return "Duraklatma nedenleri dağılımı"
        case .signatures: return "Tamamlanan imza kayıtları"
        case .photos: return "Yüklenen fotoğraf özeti"
        case .customerAnalytics: return "Müşteri geçmişi ve işlem özeti"
        case .customerSatisfaction: return "Puan dağılımı ve son değerlendirmeler"
        case .faultRecurrence: return "Tekrarlayan arıza ve cihaz geçmişi"
        case .dailyOperations: return "Seçilen güne ait operasyon özeti"
        }
    }
}
