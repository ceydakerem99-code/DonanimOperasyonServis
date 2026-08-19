import SwiftUI

struct RootView: View {
    @Environment(\.diContainer) private var container
    @State private var authSession: AuthSessionController?

    var body: some View {
        Group {
            if let authSession {
                routedContent(for: authSession)
            } else {
                LoadingView(message: "Oturum kontrol ediliyor...")
            }
        }
        .task {
            if authSession == nil {
                let controller = container.makeAuthSessionController()
                authSession = controller
                await controller.start()
            }
        }
    }

    @ViewBuilder
    private func routedContent(for session: AuthSessionController) -> some View {
        switch session.state {
        case .checkingSession:
            LoadingView(message: "Oturum kontrol ediliyor...")

        case .unauthenticated, .authenticationError:
            LoginView(session: session)

        case .authenticated(let user):
            authenticatedRoot(for: user, session: session)
        }
    }

    @ViewBuilder
    private func authenticatedRoot(for user: User, session: AuthSessionController) -> some View {
        let logout: () -> Void = {
            Task { await session.signOut() }
        }
        switch user.role {
        case .admin:
            AdminRootPlaceholder(user: user, onLogout: logout)
        case .operator:
            OperatorRootPlaceholder(user: user, onLogout: logout)
        case .technician:
            TechnicianRootPlaceholder(user: user, onLogout: logout)
        }
    }
}

#Preview {
    RootView()
        .environment(\.diContainer, .mock())
}
