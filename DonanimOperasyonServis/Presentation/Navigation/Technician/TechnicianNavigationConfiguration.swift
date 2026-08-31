import SwiftUI

enum TechnicianTab: String, Hashable, CaseIterable, Sendable {
    case home
    case workOrders
    case notifications
    case profile
}

extension TechnicianTab {
    var title: String {
        switch self {
        case .home: return "Ana Sayfa"
        case .workOrders: return "İş Emirleri"
        case .notifications: return "Bildirimler"
        case .profile: return "Profil"
        }
    }

    var systemImage: String {
        switch self {
        case .home: return "house"
        case .workOrders: return "list.bullet.rectangle"
        case .notifications: return "bell"
        case .profile: return "person.crop.circle"
        }
    }

    var accessibilityHint: String {
        switch self {
        case .home: return "Atanan işlerin özetini gösterir."
        case .workOrders: return "Atanan iş emirlerini gösterir."
        case .notifications: return "Bildirimleri gösterir."
        case .profile: return "Profil ve oturum ayarlarını gösterir."
        }
    }
}

enum TechnicianDestination: Hashable, Sendable {
    case workOrderDetail(WorkOrderID)
    case serviceReport(WorkOrderID)
    case notificationSettings
    case changePassword
    case customerSatisfactionSurvey(CustomerSatisfactionID)
    #if DEBUG
    case debugDeveloperTools
    #endif
}

extension TechnicianDestination {
    var title: String {
        switch self {
        case .workOrderDetail: return "İş Emri Detayı"
        case .serviceReport: return "Servis Raporu"
        case .notificationSettings: return "Bildirim Ayarları"
        case .changePassword: return "Şifre Değiştir"
        case .customerSatisfactionSurvey: return "Hizmet Değerlendirme"
        #if DEBUG
        case .debugDeveloperTools: return "Geliştirici / Test"
        #endif
        }
    }
}

typealias TechnicianAppRouter = BaseAppRouter<TechnicianTab, TechnicianDestination>

enum TechnicianNavigationConfiguration {
    static func tabItems(showsNotificationsUnreadIndicator: Bool = false) -> [CustomTabBarItem<TechnicianTab>] {
        TechnicianTab.allCases.map {
            CustomTabBarItem(
                tab: $0,
                title: $0.title,
                systemImage: $0.systemImage,
                showsUnreadIndicator: $0 == .notifications && showsNotificationsUnreadIndicator
            )
        }
    }
}
