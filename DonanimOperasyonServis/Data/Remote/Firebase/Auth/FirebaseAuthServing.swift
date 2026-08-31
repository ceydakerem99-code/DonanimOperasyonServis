import Foundation

/// Minimal Firebase Authentication surface kept inside Data/Remote.
/// Domain and Presentation never import `FirebaseAuth`.
protocol FirebaseAuthServing: Sendable {
    var currentUID: String? { get }
    /// Email of the signed-in Auth user (used only for first-admin bootstrap).
    var currentEmail: String? { get }
    /// Display name of the signed-in Auth user, if set in Console.
    var currentDisplayName: String? { get }

    func signIn(email: String, password: String) async throws -> String
    func signOut() async throws
    /// Confirms the current password before sensitive Auth mutations.
    func reauthenticate(email: String, password: String) async throws
    func updatePassword(_ newPassword: String) async throws
    /// Firebase Auth ID token for gateway hello. Never log the return value.
    func idToken(forceRefresh: Bool) async throws -> String
    func authStateChanges() -> AsyncStream<String?>
}
