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
        RoleAppShellView(user: user) {
            Task { await session.signOut() }
        }
    }
}

#Preview {
    RootView()
        .environment(\.diContainer, .mock())
}
