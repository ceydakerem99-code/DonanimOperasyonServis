import SwiftUI

/// Visual proxy for work-order priority used purely by the Design System.
///
/// - Important: The real domain `WorkOrderPriority` will be defined in
///   Phase 2. This UI-layer enum lets components render every priority
///   in previews without pulling in the domain layer.
enum AppPriority: String, CaseIterable, Hashable, Sendable {
    case normal
    case high
    case urgent
}

extension AppPriority {
    /// Turkish display label.
    var displayName: String {
        switch self {
        case .normal: return "Normal"
        case .high:   return "Yüksek"
        case .urgent: return "Acil"
        }
    }

    var accentColor: Color {
        switch self {
        case .normal: return AppColor.priorityNormal
        case .high:   return AppColor.priorityHigh
        case .urgent: return AppColor.priorityUrgent
        }
    }

    /// SF Symbol used on the priority badge.
    var symbolName: String {
        switch self {
        case .normal: return "circle.fill"
        case .high:   return "exclamationmark.circle.fill"
        case .urgent: return "exclamationmark.triangle.fill"
        }
    }
}
