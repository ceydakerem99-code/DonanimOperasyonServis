import Foundation

/// Minimal Firebase Authentication surface kept inside Data/Remote.
/// Domain and Presentation never import `FirebaseAuth`.
protocol FirebaseAuthServing: Sendable {
    var currentUID: String? { get }

    func signIn(email: String, password: String) async throws -> String
    func signOut() async throws
    func authStateChanges() -> AsyncStream<String?>
}
