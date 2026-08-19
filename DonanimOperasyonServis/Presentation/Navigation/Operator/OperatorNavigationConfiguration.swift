import SwiftUI

/// Operator bottom tabs — Operasyon Yetkilisi mobil prototip.
enum OperatorTab: String, Hashable, CaseIterable, Sendable {
    case dashboard
    case workOrders
    case notifications
    case profile
}

extension OperatorTab {
    var title: String {
        switch self {
        case .dashboard: return "Dashboard"
        case .workOrders: return "İş Emirleri"
        case .notifications: return "Bildirimler"
        case .profile: return "Profil"
        }
    }

    var systemImage: String {
        switch self {
        case .dashboard: return "square.grid.2x2"
        case .workOrders: return "list.bullet.rectangle"
        case .notifications: return "bell"
        case .profile: return "person.crop.circle"
        }
    }

    var accessibilityHint: String {
        switch self {
        case .dashboard: return "Günlük operasyon özetini gösterir."
        case .workOrders: return "İş emri listesini gösterir."
        case .notifications: return "Bildirimleri gösterir."
        case .profile: return "Profil ve oturum ayarlarını gösterir."
        }
    }
}

enum OperatorDestination: String, Hashable, Sendable, CaseIterable {
    case workOrderDetail
    case newWorkOrderWizard
    case editRequests
    case editRequestDetail
    case report
}

extension OperatorDestination {
    var title: String {
        switch self {
        case .workOrderDetail: return "İş Emri Detayı"
        case .newWorkOrderWizard: return "Yeni İş Emri"
        case .editRequests: return "Düzenleme Talepleri"
        case .editRequestDetail: return "Düzenleme Talep Detayı"
        case .report: return "İş Emri Raporu"
        }
    }
}

typealias OperatorAppRouter = BaseAppRouter<OperatorTab, OperatorDestination>

enum OperatorNavigationConfiguration {
    static func tabItems() -> [CustomTabBarItem<OperatorTab>] {
        OperatorTab.allCases.map {
            CustomTabBarItem(tab: $0, title: $0.title, systemImage: $0.systemImage)
        }
    }

    static var centerAction: CustomTabBarCenterAction {
        CustomTabBarCenterAction(
            systemImage: "plus",
            accessibilityLabel: "Yeni İş Emri",
            action: {}
        )
    }

    static func rootSubtitle(for tab: OperatorTab) -> String {
        "Operasyon Yetkilisi — \(tab.title) navigation skeleton (Faz 7)."
    }

    static func destinationSubtitle(for destination: OperatorDestination) -> String {
        "Operasyon Yetkilisi — \(destination.title) placeholder."
    }
}
