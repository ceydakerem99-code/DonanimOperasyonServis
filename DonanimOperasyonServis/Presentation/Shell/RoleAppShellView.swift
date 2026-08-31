import SwiftUI

/// Authenticated entry point. Picks the role shell from `User.role`
/// so operators/technicians never see admin tabs.
struct RoleAppShellView: View {
    let user: User
    let onLogout: () -> Void
    @Environment(\.diContainer) private var container

    var body: some View {
        switch user.role {
        case .admin:
            AdminAppShellView(
                user: user,
                dependencies: container.makeAdminDependencies(),
                syncProgressStore: container.syncProgressStore,
                onLogout: onLogout
            )
        case .operator:
            OperatorAppShellView(
                user: user,
                dependencies: container.makeOperatorDependencies(),
                syncProgressStore: container.syncProgressStore,
                onLogout: onLogout
            )
        case .technician:
            TechnicianAppShellView(
                user: user,
                dependencies: container.makeTechnicianDependencies(),
                syncProgressStore: container.syncProgressStore,
                onLogout: onLogout
            )
        }
    }
}

#if DEBUG
#Preview("Role shells") {
    TabView {
        RoleAppShellView(
            user: User(
                id: UserID("admin-preview"),
                email: "admin@example.com",
                fullName: "Admin",
                role: .admin,
                createdAt: Date(),
                updatedAt: Date()
            ),
            onLogout: {}
        )
        .tabItem { Text("Admin") }

        RoleAppShellView(
            user: User(
                id: UserID("operator-preview"),
                email: "operator@example.com",
                fullName: "Operasyon",
                role: .operator,
                createdAt: Date(),
                updatedAt: Date()
            ),
            onLogout: {}
        )
        .tabItem { Text("Operasyon") }

        RoleAppShellView(
            user: User(
                id: UserID("tech-preview"),
                email: "tech@example.com",
                fullName: "Teknisyen",
                role: .technician,
                createdAt: Date(),
                updatedAt: Date()
            ),
            onLogout: {}
        )
        .tabItem { Text("Teknisyen") }
    }
    .environment(\.diContainer, DIContainer.mock())
}
#endif
