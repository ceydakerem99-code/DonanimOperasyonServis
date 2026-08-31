import SwiftUI

/// Operator bottom tabs — Operasyon Yetkilisi mobil prototip.
enum OperatorTab: String, Hashable, CaseIterable, Sendable {
    case dashboard
    case workOrders
    case reports
    case notifications
    case profile
}

extension OperatorTab {
    var title: String {
        switch self {
        case .dashboard: return "Dashboard"
        case .workOrders: return "İş Emirleri"
        case .reports: return "Raporlar"
        case .notifications: return "Bildirimler"
        case .profile: return "Profil"
        }
    }

    var systemImage: String {
        switch self {
        case .dashboard: return "square.grid.2x2"
        case .workOrders: return "list.bullet.rectangle"
        case .reports: return "chart.bar.doc.horizontal"
        case .notifications: return "bell"
        case .profile: return "person.crop.circle"
        }
    }

    var accessibilityHint: String {
        switch self {
        case .dashboard: return "Günlük operasyon özetini gösterir."
        case .workOrders: return "İş emri listesini gösterir."
        case .reports: return "Raporları gösterir."
        case .notifications: return "Bildirimleri gösterir."
        case .profile: return "Profil ve oturum ayarlarını gösterir."
        }
    }
}

enum OperatorDestination: Hashable, Sendable {
    case workOrderDetail(WorkOrderID)
    case newWorkOrderWizard
    case editRequests
    case editRequestDetail(EditRequestID)
    case conflicts
    case conflictDetail(SyncConflictID)
    case notifications
    case reports
    case report(WorkOrderID)
    case tracking(WorkOrderID)
    case reportDetail(AdminReportKind)
    case customers
    case customerDetail(CustomerID)
    case editCustomer(CustomerID)
    case notificationSettings
    case changePassword
    case customerSatisfactionSurvey(CustomerSatisfactionID)
    case technicians
    #if DEBUG
    case debugDeveloperTools
    #endif
}

extension OperatorDestination {
    var title: String {
        switch self {
        case .workOrderDetail: return "İş Emri Detayı"
        case .newWorkOrderWizard: return "Yeni İş Emri"
        case .editRequests: return "Düzenleme Talepleri"
        case .editRequestDetail: return "Düzenleme Talep Detayı"
        case .conflicts: return "Senkron Çakışmaları"
        case .conflictDetail: return "Çakışma Detayı"
        case .notifications: return "Bildirimler"
        case .reports: return "Raporlar"
        case .report: return "İş Emri Raporu"
        case .tracking: return "Saha Takibi"
        case .reportDetail: return "Rapor Detayı"
        case .customers: return "Müşteriler"
        case .customerDetail: return "Müşteri Detayı"
        case .editCustomer: return "Müşteri Düzenle"
        case .notificationSettings: return "Bildirim Ayarları"
        case .changePassword: return "Şifre Değiştir"
        case .customerSatisfactionSurvey: return "Hizmet Değerlendirme"
        case .technicians: return "Teknisyenler"
        #if DEBUG
        case .debugDeveloperTools: return "Geliştirici / Test"
        #endif
        }
    }
}

typealias OperatorAppRouter = BaseAppRouter<OperatorTab, OperatorDestination>

enum OperatorNavigationConfiguration {
    /// Bottom tab bar: Dashboard, İş Emirleri, merkez FAB, Bildirimler, Profil.
    static let tabBarTabs: [OperatorTab] = [.dashboard, .workOrders, .notifications, .profile]

    static func tabItems(showsNotificationsUnreadIndicator: Bool = false) -> [CustomTabBarItem<OperatorTab>] {
        tabBarTabs.map {
            CustomTabBarItem(
                tab: $0,
                title: $0.title,
                systemImage: $0.systemImage,
                showsUnreadIndicator: $0 == .notifications && showsNotificationsUnreadIndicator
            )
        }
    }

    static var centerAction: CustomTabBarCenterAction {
        CustomTabBarCenterAction(
            systemImage: "plus",
            accessibilityLabel: "Yeni İş Emri",
            action: {}
        )
    }
}

/// List filter chips from the Operator prototype.
enum OperatorWorkOrderListFilter: String, CaseIterable, Hashable, Sendable {
    case all
    case assigned
    case inProgress
    case paused
    case completed

    var title: String {
        switch self {
        case .all: return "Tümü"
        case .assigned: return "Atandı"
        case .inProgress: return "Devam Eden"
        case .paused: return "Beklemede"
        case .completed: return "Tamamlandı"
        }
    }

    var status: WorkOrderStatus? {
        switch self {
        case .all: return nil
        case .assigned: return .assigned
        case .inProgress: return nil // multi-status: use `matchesActiveStatuses`
        case .paused: return .paused
        case .completed: return .completed
        }
    }

    /// "Devam Eden" maps to the shared active-status set, not only `.inProgress`.
    var matchesActiveStatuses: Bool {
        self == .inProgress
    }
}

/// Edit-request inbox filters from the prototype.
enum OperatorEditRequestFilter: String, CaseIterable, Hashable, Sendable {
    case pending
    case approved
    case rejected
    case all

    var title: String {
        switch self {
        case .pending: return "Bekliyor"
        case .approved: return "Onaylandı"
        case .rejected: return "Reddedildi"
        case .all: return "Tümü"
        }
    }

    var status: EditRequestStatus? {
        switch self {
        case .pending: return .pending
        case .approved: return .approved
        case .rejected: return .rejected
        case .all: return nil
        }
    }
}
