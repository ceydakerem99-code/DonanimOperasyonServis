import Foundation

extension DomainError {
    var technicianMessage: String {
        switch self {
        case .invalidStateTransition(let from, let to):
            return "Durum geçişi geçersiz: \(from.displayName) → \(to.displayName)"
        case .workOrderLocked:
            return "Tamamlanan iş emri yeniden açılamaz veya doğrudan değiştirilemez."
        case .incompleteWorkOrder(let items):
            return "Tamamlama için eksik gereksinimler var."
        case .invalidData(let reason):
            switch reason {
            case "workOrder.pauseReasonRequired":
                return "Duraklatma nedeni seçin."
            case "note.textEmpty":
                return "Not metni boş olamaz."
            case "workOrder.useCompleteWorkOrderUseCase":
                return "Tamamlama işlemi uygun akış üzerinden yapılmalı."
            default:
                return operatorMessage
            }
        case .unauthorized:
            return "Bu işlem için yetkiniz yok."
        default:
            return operatorMessage
        }
    }
}

extension MissingRequirement {
    var technicianDisplayName: String {
        switch self {
        case .missingNote:
            return "En az bir servis notu"
        case .missingPhoto(let category):
            return "\(category.displayName) fotoğrafı"
        case .missingLocation(let event):
            return "\(event.displayName) GPS kaydı"
        case .missingTechnicianSignature:
            return "Teknisyen imzası"
        case .missingCustomerSignature:
            return "Müşteri imzası"
        }
    }
}

extension SyncStatus {
    var technicianDisplayName: String {
        switch self {
        case .pending: return "Senkronizasyon bekliyor"
        case .inProgress: return "Senkronize ediliyor"
        case .succeeded: return "Senkronize edildi"
        case .failed: return "Senkronizasyon başarısız"
        case .conflict: return "Çakışma"
        }
    }
}
