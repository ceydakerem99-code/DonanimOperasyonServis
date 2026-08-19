import Foundation

/// Application-level authentication state consumed by `RootView`.
/// Keeps routing decisions in one place instead of scattering
/// `if loggedIn` checks across screens.
enum AuthState: Equatable, Sendable {
    /// Session restore / first launch probe is in flight. UI must not
    /// route to a role shell until this resolves.
    case checkingSession

    /// No authenticated Firebase session (or Firestore profile missing).
    case unauthenticated

    /// Firebase session + Firestore `users/{uid}` profile resolved.
    case authenticated(User)

    /// Sign-in failed or session restore hit a hard auth error.
    case authenticationError(DomainError)
}
