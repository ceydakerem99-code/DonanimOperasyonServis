import Foundation

enum TechnicianWorkOrderActionMapping {

    struct PrimaryAction: Equatable, Sendable {
        let title: String
        let systemImage: String
        let targetStatus: WorkOrderStatus
        let locationEvent: LocationEvent?
    }

    static func primaryAction(for status: WorkOrderStatus) -> PrimaryAction? {
        switch status {
        case .assigned:
            return PrimaryAction(title: "Kabul Et", systemImage: "checkmark.circle", targetStatus: .accepted, locationEvent: nil)
        case .accepted:
            return PrimaryAction(title: "Yola Çık", systemImage: "car", targetStatus: .enRoute, locationEvent: .enRoute)
        case .enRoute:
            return PrimaryAction(title: "Müşteriye Vardım", systemImage: "mappin.and.ellipse", targetStatus: .arrived, locationEvent: .arrived)
        case .arrived:
            return PrimaryAction(title: "İşe Başla", systemImage: "wrench.and.screwdriver", targetStatus: .inProgress, locationEvent: nil)
        case .paused:
            return PrimaryAction(title: "İşe Devam Et", systemImage: "play.circle", targetStatus: .inProgress, locationEvent: nil)
        case .inProgress, .completed, .rejected:
            return nil
        }
    }

    static func locationEventForTransition(
        from: WorkOrderStatus,
        to: WorkOrderStatus
    ) -> LocationEvent? {
        switch (from, to) {
        case (.accepted, .enRoute): return .enRoute
        case (.enRoute, .arrived): return .arrived
        default: return nil
        }
    }
}

enum TechnicianWorkOrderListFilter: String, CaseIterable, Hashable, Sendable {
    case active
    case urgent
    case inProgress
    case paused
    case completed

    var title: String {
        switch self {
        case .active: return "Aktif İşler"
        case .urgent: return "Acil"
        case .inProgress: return "Devam Eden"
        case .paused: return "Beklemede"
        case .completed: return "Tamamlanan"
        }
    }
}
