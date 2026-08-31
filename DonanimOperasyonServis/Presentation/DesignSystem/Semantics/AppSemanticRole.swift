import SwiftUI

/// Semantic visual roles for KPI cards, badges, and accent surfaces.
///
/// Maps operational meaning to centralized `AppColor` tokens. Views
/// should prefer this enum over ad-hoc color selection.
enum AppSemanticRole: Hashable, Sendable, CaseIterable {
    case primary
    case urgent
    case overdue
    case paused
    case priorityHigh
    case available
    case busy
    case completed
    case error
    case neutral

    var accentColor: Color {
        switch self {
        case .primary: return AppColor.primary
        case .urgent: return AppColor.statusUrgent
        case .overdue: return AppColor.statusOverdue
        case .paused: return AppColor.statusPaused
        case .priorityHigh: return AppColor.priorityHighAccent
        case .available: return AppColor.statusAvailable
        case .busy: return AppColor.statusBusy
        case .completed: return AppColor.statusCompleted
        case .error: return AppColor.statusError
        case .neutral: return AppColor.secondaryText
        }
    }

    /// KPI / list cards use a neutral surface; accent is stripe + icon only.
    var surfaceColor: Color {
        AppColor.elevatedSurface
    }

    /// Infers a semantic role from localized metric / KPI titles.
    static func metricRole(forTitle title: String) -> AppSemanticRole {
        let lower = title.lowercased(with: Locale(identifier: "tr_TR"))
        if lower.contains("acil") { return .urgent }
        if lower.contains("gecik") || lower.contains("süresi geç") { return .overdue }
        if lower.contains("beklemede") || lower.contains("bekleme") { return .paused }
        if lower.contains("müsait") { return .available }
        if lower.contains("meşgul") || lower.contains("devam") { return .busy }
        if lower.contains("tamamlan") || lower.contains("tamamlandı") { return .completed }
        if lower.contains("redded") || lower.contains("hata") || lower.contains("conflict") { return .error }
        if lower.contains("açık") || lower.contains("açılan") || lower.contains("toplam") { return .primary }
        return .neutral
    }
}

extension TechnicianWorkingStatus {
    var semanticRole: AppSemanticRole {
        switch self {
        case .available: return .available
        case .busy: return .busy
        case .paused: return .paused
        }
    }
}

extension OperatorTechnicianListFilter {
    var semanticRole: AppSemanticRole {
        switch self {
        case .all: return .primary
        case .available: return .available
        case .busy: return .busy
        }
    }
}

extension AdminReportKind {
    /// Subtle accent variation for report hub tiles — icon level only.
    var hubAccentRole: AppSemanticRole {
        switch self {
        case .workOrders: return .primary
        case .technicianPerformance: return .busy
        case .pauseReasons: return .paused
        case .signatures: return .completed
        case .photos: return .primary
        case .customerAnalytics: return .primary
        case .customerSatisfaction: return .completed
        case .faultRecurrence: return .urgent
        case .dailyOperations: return .overdue
        }
    }
}

extension WorkOrderCardData {
    /// Left accent stripe follows work-order priority only.
    var priorityAccentRole: AppSemanticRole {
        switch priority {
        case .urgent: return .urgent
        case .high: return .priorityHigh
        case .normal: return .primary
        }
    }
}
