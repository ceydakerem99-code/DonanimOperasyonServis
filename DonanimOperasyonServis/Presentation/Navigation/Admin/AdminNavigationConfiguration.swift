import SwiftUI

/// Admin bottom tabs — terminology from Admin mobil prototip.
enum AdminTab: String, Hashable, CaseIterable, Sendable {
    case dashboard
    case users
    case roles
    case system
    case reports
}

extension AdminTab {
    var title: String {
        switch self {
        case .dashboard: return "Dashboard"
        case .users: return "Kullanıcılar"
        case .roles: return "Roller"
        case .system: return "Sistem"
        case .reports: return "Raporlar"
        }
    }

    var systemImage: String {
        switch self {
        case .dashboard: return "square.grid.2x2"
        case .users: return "person.2"
        case .roles: return "shield"
        case .system: return "gearshape"
        case .reports: return "chart.bar"
        }
    }

    var accessibilityHint: String {
        switch self {
        case .dashboard: return "Sistem özetini gösterir."
        case .users: return "Kullanıcı listesini gösterir."
        case .roles: return "Rol yönetimini gösterir."
        case .system: return "Sistem ayarlarını gösterir."
        case .reports: return "Rapor panelini gösterir."
        }
    }
}

/// Stack destinations reachable from Admin tabs.
enum AdminDestination: Hashable, Sendable {
    case createUser
    case userDetail(UserID)
    case roleDetail(UserRole)
    case workTypes
    case pauseReasons
    case reportDetail(AdminReportKind)
    case workOrderReport(WorkOrderID)
    case conflicts
}

extension AdminDestination {
    var title: String {
        switch self {
        case .createUser: return "Yeni Kullanıcı"
        case .userDetail: return "Kullanıcı Detayı"
        case .roleDetail: return "Rol Detayı"
        case .workTypes: return "İş Türleri Yönetimi"
        case .pauseReasons: return "Bekleme Nedenleri"
        case .reportDetail(let kind): return kind.title
        case .workOrderReport: return "İş Emri Raporu"
        case .conflicts: return "Senkron Çakışmaları"
        }
    }
}

typealias AdminAppRouter = BaseAppRouter<AdminTab, AdminDestination>

enum AdminNavigationConfiguration {
    static func tabItems() -> [CustomTabBarItem<AdminTab>] {
        AdminTab.allCases.map {
            CustomTabBarItem(tab: $0, title: $0.title, systemImage: $0.systemImage)
        }
    }
}
