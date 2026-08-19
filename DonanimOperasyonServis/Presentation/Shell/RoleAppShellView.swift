import SwiftUI

/// Authenticated entry point. Picks the role shell from `User.role`
/// so operators/technicians never see admin tabs.
struct RoleAppShellView: View {
    let user: User
    let onLogout: () -> Void

    var body: some View {
        switch user.role {
        case .admin:
            AdminAppShellView(user: user, onLogout: onLogout)
        case .operator:
            OperatorAppShellView(user: user, onLogout: onLogout)
        case .technician:
            TechnicianAppShellView(user: user, onLogout: onLogout)
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
}
#endif
