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
    var showsActiveConfirmation = false
    var showsRoleConfirmation = false
    var pendingRole: UserRole?

    private let userId: UserID
    private let actor: User
    private let dependencies: AdminDependencies

    init(userId: UserID, actor: User, dependencies: AdminDependencies) {
        self.userId = userId
        self.actor = actor
        self.dependencies = dependencies
    }

    var isViewingSelf: Bool {
        content?.user.id == actor.id
    }

    var passwordResetUnsupportedMessage: String {
        AdminUnsupportedAction.message
    }

    func load() async {
        phase = .loading
        do {
            let user = try await dependencies.getUser.execute(actor: actor, id: userId)
            content = Self.makeContent(user: user)
            phase = .loaded
        } catch is CancellationError {
            return
        } catch let error as DomainError {
            phase = .error(error.adminMessage)
        } catch {
            phase = .error("Kullanıcı yüklenemedi.")
        }
    }

    func requestToggleActive() {
        guard let user = content?.user else { return }
        if user.id == actor.id {
            actionMessage = "Kendi hesabınızın durumunu değiştiremezsiniz."
            return
        }
        actionMessage = nil
        showsActiveConfirmation = true
    }

    func confirmToggleActive() async {
        showsActiveConfirmation = false
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
            content = Self.makeContent(user: updated)
            actionMessage = updated.isActive ? "Kullanıcı aktifleştirildi." : "Kullanıcı pasifleştirildi."
        } catch let error as DomainError {
            actionMessage = error.adminMessage
        } catch {
            actionMessage = "Durum güncellenemedi."
        }
    }

    func requestRoleChange(_ role: UserRole) {
        guard let user = content?.user else { return }
        if user.id == actor.id {
            actionMessage = "Kendi rolünüzü değiştiremezsiniz."
            return
        }
        if user.role == role {
            return
        }
        pendingRole = role
        actionMessage = nil
        showsRoleConfirmation = true
    }

    func confirmRoleChange() async {
        showsRoleConfirmation = false
        guard let user = content?.user, let role = pendingRole else { return }
        pendingRole = nil
        isUpdating = true
        actionMessage = nil
        defer { isUpdating = false }
        do {
            let updated = try await dependencies.userService.assignRole(
                actor: actor,
                userId: user.id,
                role: role
            )
            content = Self.makeContent(user: updated)
            actionMessage = "Rol \(updated.role.displayName) olarak güncellendi."
        } catch let error as DomainError {
            actionMessage = error.adminMessage
        } catch {
            actionMessage = "Rol güncellenemedi."
        }
    }

    /// Kept for existing tests — performs the active toggle after confirmation path.
    func toggleActiveState() async {
        await confirmToggleActive()
    }

    private static func makeContent(user: User) -> AdminUserDetailContent {
        let granted = RoleAccessPolicyAdminUI.grantedActions(for: user.role)
        let permissions = RoleAccessPolicyAdminUI.allActions.filter { granted.contains($0) }
        return AdminUserDetailContent(user: user, permissions: permissions)
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
        vm.phase = .loaded
        vm.content = makeContent(user: AdminPreviewData.operatorUser)
        return vm
    }
}
#endif
