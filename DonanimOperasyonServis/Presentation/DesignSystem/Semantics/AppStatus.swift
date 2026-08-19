import SwiftUI

/// Visual proxy for work-order status used purely by the Design System.
///
/// - Important: This type is a UI-layer concern; the real domain
///   `WorkOrderStatus` and its state machine will be defined in Phase 2.
///   Design System components accept this enum so that previews and
///   sample data can render every status without pulling in the domain.
///   Once the domain type exists, Presentation code will map the domain
///   enum onto this one at the view boundary.
enum AppStatus: String, CaseIterable, Hashable, Sendable {
    case assigned
    case accepted
    case enRoute
    case arrived
    case inProgress
    case paused
    case completed
}

extension AppStatus {
    /// Turkish display label shown to the user.
    var displayName: String {
        switch self {
        case .assigned:   return "Atandı"
        case .accepted:   return "Kabul Edildi"
        case .enRoute:    return "Yola Çıkıldı"
        case .arrived:    return "Müşteriye Varıldı"
        case .inProgress: return "İşlemde"
        case .paused:     return "Beklemede"
        case .completed:  return "Tamamlandı"
        }
    }

    @MainActor
    var accentColor: Color {
        switch self {
        case .assigned:   return AppColor.statusAssigned
        case .accepted:   return AppColor.statusAccepted
        case .enRoute:    return AppColor.statusEnRoute
        case .arrived:    return AppColor.statusArrived
        case .inProgress: return AppColor.statusInProgress
        case .paused:     return AppColor.statusPaused
        case .completed:  return AppColor.statusCompleted
        }
    }

    /// SF Symbol name used in chips/timelines.
    var symbolName: String {
        switch self {
        case .assigned:   return "tray.and.arrow.down"
        case .accepted:   return "checkmark.circle"
        case .enRoute:    return "car"
        case .arrived:    return "mappin.and.ellipse"
        case .inProgress: return "wrench.and.screwdriver"
        case .paused:     return "pause.circle"
        case .completed:  return "checkmark.seal.fill"
        }
    }
}
