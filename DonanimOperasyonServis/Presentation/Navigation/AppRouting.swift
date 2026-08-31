import Foundation
import Observation

/// Central navigation contract. Auth state stays in
/// `AuthSessionController`; tab/stack state lives here.
@MainActor
protocol AppRouting: AnyObject, Observable {
    associatedtype Tab: Hashable
    associatedtype Destination: Hashable

    var selectedTab: Tab { get set }
    var path: [Destination] { get set }

    func push(_ destination: Destination)
    func popToRoot()
}

extension AppRouting {
    func popToRoot() {
        path.removeAll()
    }

    func pop() {
        guard !path.isEmpty else { return }
        path.removeLast()
    }
}

/// Base router shared by all role shells.
@Observable
@MainActor
class BaseAppRouter<Tab: Hashable, Destination: Hashable>: AppRouting {
    var selectedTab: Tab
    var path: [Destination] = []

    init(selectedTab: Tab) {
        self.selectedTab = selectedTab
    }

    func push(_ destination: Destination) {
        path.append(destination)
    }
}
