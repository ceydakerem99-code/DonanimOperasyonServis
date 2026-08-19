import Foundation
import Observation

enum AdminUserListFilter: String, CaseIterable, Sendable {
    case all
    case active
    case passive

    var title: String {
        switch self {
        case .all: return "Tümü"
        case .active: return "Aktif"
        case .passive: return "Pasif"
        }
    }

    var isActive: Bool? {
        switch self {
        case .all: return nil
        case .active: return true
        case .passive: return false
        }
    }
}

struct AdminUserRowData: Identifiable, Equatable, Sendable {
    let id: String
    let fullName: String
    let email: String
    let roleLabel: String
    let isActive: Bool
}

@Observable
@MainActor
final class AdminUserListViewModel {
    enum Phase: Equatable {
        case loading
        case loaded
        case empty
        case error(String)
    }

    private(set) var phase: Phase = .loading
    private(set) var rows: [AdminUserRowData] = []
    var searchText = ""
    private(set) var selectedFilter: AdminUserListFilter = .all

    private let actor: User
    private let dependencies: AdminDependencies
    private var allRows: [AdminUserRowData] = []

    init(actor: User, dependencies: AdminDependencies) {
        self.actor = actor
        self.dependencies = dependencies
    }

    func load() async {
        phase = .loading
        do {
            let users = try await dependencies.listUsers.execute(
                actor: actor,
                isActive: selectedFilter.isActive
            )
            allRows = users.map(Self.mapRow)
            applySearch()
            phase = rows.isEmpty ? .empty : .loaded
        } catch let error as DomainError {
            phase = .error(error.adminMessage)
        } catch {
            phase = .error("Kullanıcılar yüklenemedi.")
        }
    }

    func selectFilter(_ filter: AdminUserListFilter) async {
        selectedFilter = filter
        await load()
    }

    private func applySearch() {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else {
            rows = allRows
            return
        }
        rows = allRows.filter {
            $0.fullName.lowercased().contains(query) ||
            $0.email.lowercased().contains(query) ||
            $0.roleLabel.lowercased().contains(query)
        }
        if case .loaded = phase, rows.isEmpty {
            phase = .empty
        }
    }

    func refreshSearch() {
        applySearch()
        if rows.isEmpty, !allRows.isEmpty, searchText.isEmpty {
            phase = .loaded
        }
    }

    private static func mapRow(_ user: User) -> AdminUserRowData {
        AdminUserRowData(
            id: user.id.rawValue,
            fullName: user.fullName,
            email: user.email,
            roleLabel: user.role.displayName,
            isActive: user.isActive
        )
    }
}

#if DEBUG
extension AdminUserListViewModel {
    static func previewLoaded() -> AdminUserListViewModel {
        let vm = AdminUserListViewModel(
            actor: AdminPreviewData.adminUser,
            dependencies: DIContainer.mock().makeAdminDependencies()
        )
        vm.phase = .loaded
        vm.rows = AdminPreviewData.users().map {
            AdminUserRowData(
                id: $0.id.rawValue,
                fullName: $0.fullName,
                email: $0.email,
                roleLabel: $0.role.displayName,
                isActive: $0.isActive
            )
        }
        return vm
    }

    static func previewEmpty() -> AdminUserListViewModel {
        let vm = AdminUserListViewModel(
            actor: AdminPreviewData.adminUser,
            dependencies: DIContainer.mock().makeAdminDependencies()
        )
        vm.phase = .empty
        return vm
    }
}
#endif
