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
            case "photo.dataEmpty":
                return "Fotoğraf verisi boş olamaz."
            case "signature.dataEmpty":
                return "İmza boş olamaz. Lütfen imzalayın."
            case "workOrder.useCompleteWorkOrderUseCase":
                return "Tamamlama işlemi uygun akış üzerinden yapılmalı."
            case "editRequest.reasonEmpty":
                return "Gerekçe boş olamaz."
            case "workOrder.priorityInvalid":
                return "Geçerli bir öncelik seçin."
            case "workOrder.scheduledDateInvalid":
                return "Geçerli bir tarih girin."
            default:
                return operatorMessage
            }
        case .invalidEditRequest(let reason):
            switch reason {
            case .noChange:
                return "Yeni değer mevcut değerden farklı olmalıdır."
            case .workOrderNotCompleted:
                return "Düzenleme talebi yalnızca tamamlanan iş emirleri için açılabilir."
            case .fieldNotEditable:
                return "Bu alan düzenleme talebi ile değiştirilemez."
            case .selfReview:
                return "Kendi talebinizi inceleyemezsiniz."
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
            return "\(event.displayName) GPS kaydı gerekli"
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

extension WorkOrderPhoto {
    var isUploadPending: Bool {
        PendingStoragePath.isPending(storagePath)
    }
}

extension Signature {
    var isUploadPending: Bool {
        PendingStoragePath.isPending(storagePath)
    }
}
