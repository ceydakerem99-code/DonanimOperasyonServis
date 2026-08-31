import Foundation
import FirebaseAuth
import FirebaseCore

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

    var currentEmail: String? {
        Auth.auth().currentUser?.email
    }

    var currentDisplayName: String? {
        Auth.auth().currentUser?.displayName
    }

    func signIn(email: String, password: String) async throws -> String {
        let result = try await Auth.auth().signIn(withEmail: email, password: password)
        return result.user.uid
    }

    func signOut() async throws {
        try Auth.auth().signOut()
    }

    func reauthenticate(email: String, password: String) async throws {
        guard let user = Auth.auth().currentUser else {
            throw DomainError.authenticationFailed(.sessionInvalid)
        }
        let credential = EmailAuthProvider.credential(withEmail: email, password: password)
        try await user.reauthenticate(with: credential)
    }

    func updatePassword(_ newPassword: String) async throws {
        guard let user = Auth.auth().currentUser else {
            throw DomainError.authenticationFailed(.sessionInvalid)
        }
        try await user.updatePassword(to: newPassword)
    }

    func idToken(forceRefresh: Bool) async throws -> String {
        guard let user = Auth.auth().currentUser else {
            throw DomainError.authenticationFailed(.sessionInvalid)
        }
#if DEBUG
        logAuthUserIdentity()
#endif
        let result = try await user.getIDTokenResult(forcingRefresh: forceRefresh)
#if DEBUG
        let claimKeys = result.claims.keys.sorted().joined(separator: ",")
        let rolePresent = result.claims["role"] != nil
        AppLogger.realtime.info(
            "IDTOKEN claims keys=[\(claimKeys, privacy: .public)] rolePresent=\(rolePresent, privacy: .public) forceRefresh=\(forceRefresh, privacy: .public)"
        )
#endif
        return result.token
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

#if DEBUG
    private func logAuthUserIdentity() {
        let currentUser = Auth.auth().currentUser
        let uid = currentUser?.uid ?? "-"
        let email = currentUser?.email ?? "-"
        let projectID = FirebaseApp.app()?.options.projectID ?? "-"
        AppLogger.realtime.info(
            "AUTH USER uid=\(uid, privacy: .public) email=\(email, privacy: .public) projectID=\(projectID, privacy: .public)"
        )
    }
#endif
}
