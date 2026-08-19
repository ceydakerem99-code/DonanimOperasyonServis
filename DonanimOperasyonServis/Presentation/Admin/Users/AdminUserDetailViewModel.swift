import Foundation
import Observation

struct AdminUserDetailContent: Equatable, Sendable {
    let user: User
    let permissions: [DomainAction]
}

@Observable
@MainActor
final class AdminUserDetailViewModel {
    enum Phase: Equatable {
        case loading
        case loaded
        case error(String)
    }

    private(set) var phase: Phase = .loading
    private(set) var content: AdminUserDetailContent?
    private(set) var actionMessage: String?
    private(set) var isUpdating = false

    private let userId: UserID
    private let actor: User
    private let dependencies: AdminDependencies

    init(userId: UserID, actor: User, dependencies: AdminDependencies) {
        self.userId = userId
        self.actor = actor
        self.dependencies = dependencies
    }

    func load() async {
        phase = .loading
        do {
            let user = try await dependencies.getUser.execute(actor: actor, id: userId)
            let granted = RoleAccessPolicyAdminUI.grantedActions(for: user.role)
            let permissions = RoleAccessPolicyAdminUI.allActions.filter { granted.contains($0) }
            content = AdminUserDetailContent(user: user, permissions: permissions)
            phase = .loaded
        } catch let error as DomainError {
            phase = .error(error.adminMessage)
        } catch {
            phase = .error("Kullanıcı yüklenemedi.")
        }
    }

    func toggleActiveState() async {
        guard let user = content?.user else { return }
        isUpdating = true
        actionMessage = nil
        defer { isUpdating = false }
        do {
            let updated = try await dependencies.userService.setActive(
                actor: actor,
                userId: user.id,
                isActive: !user.isActive
            )
            let granted = RoleAccessPolicyAdminUI.grantedActions(for: updated.role)
            let permissions = RoleAccessPolicyAdminUI.allActions.filter { granted.contains($0) }
            content = AdminUserDetailContent(user: updated, permissions: permissions)
            actionMessage = updated.isActive ? "Kullanıcı aktifleştirildi." : "Kullanıcı pasifleştirildi."
        } catch let error as DomainError {
            actionMessage = error.adminMessage
        } catch {
            actionMessage = "Durum güncellenemedi."
        }
    }
}

#if DEBUG
extension AdminUserDetailViewModel {
    static func previewLoaded() -> AdminUserDetailViewModel {
        let vm = AdminUserDetailViewModel(
            userId: AdminPreviewData.operatorUser.id,
            actor: AdminPreviewData.adminUser,
            dependencies: DIContainer.mock().makeAdminDependencies()
        )
        let granted = RoleAccessPolicyAdminUI.grantedActions(for: .operator)
        vm.phase = .loaded
        vm.content = AdminUserDetailContent(
            user: AdminPreviewData.operatorUser,
            permissions: RoleAccessPolicyAdminUI.allActions.filter { granted.contains($0) }
        )
        return vm
    }
}
#endif
