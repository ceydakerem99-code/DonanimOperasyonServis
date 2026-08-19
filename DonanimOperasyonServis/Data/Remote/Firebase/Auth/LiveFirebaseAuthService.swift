import Foundation
import FirebaseAuth

/// Production wrapper around `FirebaseAuth`. Credentials and ID
/// tokens are never logged or persisted manually — the SDK owns
/// session storage.
final class LiveFirebaseAuthService: FirebaseAuthServing, @unchecked Sendable {

    private final class ListenerToken: @unchecked Sendable {
        let handle: NSObjectProtocol
        init(_ handle: NSObjectProtocol) { self.handle = handle }
    }

    var currentUID: String? {
        Auth.auth().currentUser?.uid
    }

    func signIn(email: String, password: String) async throws -> String {
        let result = try await Auth.auth().signIn(withEmail: email, password: password)
        return result.user.uid
    }

    func signOut() async throws {
        try Auth.auth().signOut()
    }

    func authStateChanges() -> AsyncStream<String?> {
        AsyncStream { continuation in
            let token = ListenerToken(
                Auth.auth().addStateDidChangeListener { _, user in
                    continuation.yield(user?.uid)
                }
            )
            continuation.yield(Auth.auth().currentUser?.uid)
            continuation.onTermination = { _ in
                Auth.auth().removeStateDidChangeListener(token.handle)
            }
        }
    }
}
