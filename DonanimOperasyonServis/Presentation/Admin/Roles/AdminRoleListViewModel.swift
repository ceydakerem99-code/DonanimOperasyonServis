import Foundation
import Observation

struct AdminRoleRowData: Identifiable, Equatable, Sendable {
    let role: UserRole
    let userCount: Int

    var id: String { role.rawValue }
    var title: String { role.displayName }
    var subtitle: String { RoleAccessPolicyAdminUI.roleDescription(for: role) }
}

@Observable
@MainActor
final class AdminRoleListViewModel {
    enum Phase: Equatable {
        case loading
        case loaded
        case empty
        case error(String)
    }

    private(set) var phase: Phase = .loading
    private(set) var rows: [AdminRoleRowData] = []

    private let actor: User
    private let dependencies: AdminDependencies

    init(actor: User, dependencies: AdminDependencies) {
        self.actor = actor
        self.dependencies = dependencies
    }

    func load() async {
        phase = .loading
        do {
            guard RoleAccessPolicy.can(.viewRolesMatrix, as: actor.role) else {
                throw DomainError.unauthorized(action: .viewRolesMatrix)
            }
            let users = try await dependencies.listUsers.execute(actor: actor)
            rows = UserRole.allCases.map { role in
                AdminRoleRowData(
                    role: role,
                    userCount: users.filter { $0.role == role && $0.isActive }.count
                )
            }
            phase = .loaded
        } catch let error as DomainError {
            phase = .error(error.adminMessage)
        } catch {
            phase = .error("Roller yüklenemedi.")
        }
    }
}

#if DEBUG
extension AdminRoleListViewModel {
    static func previewLoaded() -> AdminRoleListViewModel {
        let vm = AdminRoleListViewModel(
            actor: AdminPreviewData.adminUser,
            dependencies: DIContainer.mock().makeAdminDependencies()
        )
        vm.phase = .loaded
        vm.rows = [
            AdminRoleRowData(role: .admin, userCount: 2),
            AdminRoleRowData(role: .operator, userCount: 6),
            AdminRoleRowData(role: .technician, userCount: 24)
        ]
        return vm
    }
}
#endif
