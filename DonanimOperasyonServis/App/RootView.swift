import SwiftUI

struct RootView: View {
    @Environment(\.diContainer) private var container
    @State private var authSession: AuthSessionController?

    var body: some View {
        Group {
            if let authSession {
                AuthRoutingView(session: authSession)
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
}

/// Observes `AuthSessionController.state` via `@Bindable` so logout
/// reliably swaps the role shell for `LoginView`.
private struct AuthRoutingView: View {
    @Bindable var session: AuthSessionController

    var body: some View {
        switch session.state {
        case .checkingSession:
            LoadingView(message: "Oturum kontrol ediliyor...")

        case .unauthenticated, .authenticationError:
            LoginView(session: session)

        case .authenticated(let user):
            RoleAppShellView(user: user) {
                Task { await session.signOut() }
            }
        }
    }
}

#Preview {
    RootView()
        .environment(\.diContainer, .mock())
}
