import Foundation

extension DomainError {
    var adminMessage: String {
        switch self {
        case .invalidData:
            return "Girilen bilgiler geçersiz."
        case .unauthorized:
            return "Bu işlem için yetkiniz yok."
        case .notFound:
            return "Kayıt bulunamadı."
        case .workOrderLocked:
            return "Tamamlanan iş emirleri silinemez."
        default:
            return "Bir hata oluştu. Lütfen tekrar deneyin."
        }
    }
}
