import Foundation

extension DomainAction {
    /// Turkish label for the admin role-permission matrix.
    var adminDisplayName: String {
        switch self {
        case .manageUsers: return "Kullanıcı yönetimi"
        case .viewRolesMatrix: return "Rol matrisini görüntüleme"
        case .manageSystemConfiguration: return "Sistem yapılandırması"
        case .viewSystemReports: return "Sistem raporları"
        case .deleteWorkOrder: return "İş emri silme"
        case .createWorkOrder: return "İş emri oluşturma"
        case .createCustomer: return "Müşteri oluşturma"
        case .updateCustomer: return "Müşteri bilgilerini güncelleme"
        case .assignWorkOrder: return "İş emri atama"
        case .viewAllWorkOrders: return "Tüm iş emirlerini görüntüleme"
        case .viewServiceReport: return "Servis raporu görüntüleme"
        case .approveEditRequest: return "Düzenleme talebi onaylama"
        case .rejectEditRequest: return "Düzenleme talebi reddetme"
        case .resolveSyncConflict: return "Senkron çakışması çözme"
        case .createCustomerSatisfaction: return "Müşteri memnuniyeti anketi oluşturma"
        case .viewOwnAssignedWorkOrders: return "Atanan iş emirlerini görüntüleme"
        case .acceptWorkOrder: return "İş emri kabul etme"
        case .startTravelToCustomer: return "Yola çıkma"
        case .markArrivedAtCustomer: return "Müşteriye varma"
        case .startServiceWork: return "Servis işine başlama"
        case .pauseServiceWork: return "Servisi duraklatma"
        case .resumeServiceWork: return "Servise devam etme"
        case .addWorkOrderNote: return "Servis notu ekleme"
        case .addWorkOrderPhoto: return "Fotoğraf ekleme"
        case .captureLocationSample: return "Konum kaydı"
        case .captureSignature: return "İmza alma"
        case .completeWorkOrder: return "İş emrini tamamlama"
        case .createEditRequest: return "Düzenleme talebi oluşturma"
        }
    }
}

enum RoleAccessPolicyAdminUI {
    static let allActions: [DomainAction] = [
        .manageUsers, .viewRolesMatrix, .manageSystemConfiguration, .viewSystemReports, .deleteWorkOrder,
        .createWorkOrder, .createCustomer, .updateCustomer, .assignWorkOrder, .viewAllWorkOrders,
        .viewServiceReport, .approveEditRequest, .rejectEditRequest, .resolveSyncConflict,
        .createCustomerSatisfaction,
        .viewOwnAssignedWorkOrders, .acceptWorkOrder, .startTravelToCustomer,
        .markArrivedAtCustomer, .startServiceWork, .pauseServiceWork, .resumeServiceWork,
        .addWorkOrderNote, .addWorkOrderPhoto, .captureLocationSample, .captureSignature,
        .completeWorkOrder, .createEditRequest
    ]

    static func grantedActions(for role: UserRole) -> Set<DomainAction> {
        RoleAccessPolicy.permissions[role] ?? []
    }

    static func roleDescription(for role: UserRole) -> String {
        switch role {
        case .admin:
            return "Organizasyonel yönetim, kullanıcı ve sistem raporları."
        case .operator:
            return "Operasyon merkezi; iş emri oluşturma, atama ve düzenleme talepleri."
        case .technician:
            return "Saha teknisyeni; atanan iş emirlerinde servis işlemleri."
        }
    }
}
