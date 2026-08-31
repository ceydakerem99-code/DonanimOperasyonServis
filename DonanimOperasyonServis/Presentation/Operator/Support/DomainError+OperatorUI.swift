import Foundation

extension DomainError {
    var operatorMessage: String {
        switch self {
        case .invalidData(let reason):
            switch reason {
            case "workOrder.requiredFieldEmpty":
                return "Zorunlu alanları doldurun."
            case "workOrder.deviceBrandEmpty":
                return "Cihaz markası boş olamaz."
            case "workOrder.deviceModelEmpty":
                return "Cihaz modeli boş olamaz."
            case "workOrder.serialNumberEmpty":
                return "Seri numarası boş olamaz."
            case "customer.nameEmpty":
                return "Müşteri adı boş olamaz."
            case "customer.addressEmpty":
                return "Adres boş olamaz."
            case "conflict.completedWorkOrderMustStayUnresolved":
                return "Tamamlanan iş emri çakışması bu ekrandan çözülemez. Düzenleme talebi sürecini kullanın."
            case "conflict.editRequestWorkflowRequired":
                return "Düzenleme talebi çakışması onay/red akışı üzerinden çözülmelidir."
            case "conflict.alreadyResolved":
                return "Bu çakışma zaten çözülmüş."
            case "conflict.resolveInFlight":
                return "Çakışma çözümü zaten devam ediyor."
            case "conflict.missingStoredResolution":
                return "Çözüm kaydı tamamlanamadı."
            default:
                return "Girilen bilgiler geçersiz."
            }
        case .unauthorized:
            return "Bu işlem için yetkiniz yok."
        case .workOrderLocked:
            return "Tamamlanan iş emirleri doğrudan düzenlenemez. Düzenleme talebi sürecini kullanın."
        case .notFound:
            return "Kayıt bulunamadı."
        case .invalidEditRequest(let reason):
            switch reason {
            case .selfReview:
                return "Kendi talebinizi inceleyemezsiniz."
            default:
                return "Düzenleme talebi geçersiz."
            }
        default:
            return "Bir hata oluştu. Lütfen tekrar deneyin."
        }
    }
}
