import Foundation
import FirebaseAuth
import os

/// Deterministic Firebase Auth stand-in for unit tests and previews.
/// Never touches the real SDK or network.
final class FakeFirebaseAuthService: FirebaseAuthServing, @unchecked Sendable {

    private struct State {
        var uid: String?
        var email: String?
        var displayName: String?
        var emailToUID: [String: String] = [:]
        var uidToDisplayName: [String: String] = [:]
        var passwordByEmail: [String: String] = [:]
        var continuations: [UUID: AsyncStream<String?>.Continuation] = [:]
        var signInError: Error?
    }

    private let lock = OSAllocatedUnfairLock(initialState: State())

    func register(email: String, uid: String, displayName: String? = nil, password: String = "password") {
        lock.withLock { state in
            state.emailToUID[email.lowercased()] = uid
            state.passwordByEmail[email.lowercased()] = password
            if let displayName {
                state.uidToDisplayName[uid] = displayName
            }
        }
    }

    func setUID(_ uid: String?, email: String? = nil) {
        let continuations = lock.withLock { state -> [AsyncStream<String?>.Continuation] in
            let changed = state.uid != uid
            state.uid = uid
            state.email = email
            state.displayName = uid.flatMap { state.uidToDisplayName[$0] }
            return changed ? Array(state.continuations.values) : []
        }
        for continuation in continuations {
            continuation.yield(uid)
        }
    }

    var currentUID: String? {
        lock.withLock { $0.uid }
    }

    var currentEmail: String? {
        lock.withLock { $0.email }
    }

    var currentDisplayName: String? {
        lock.withLock { $0.displayName }
    }

    func signIn(email: String, password: String) async throws -> String {
        let snapshot = lock.withLock { state -> (Error?, String?, String?) in
            if let signInError = state.signInError { return (signInError, nil, nil) }
            let key = email.lowercased()
            let resolved = state.emailToUID[key]
            let expected = state.passwordByEmail[key]
            return (nil, resolved, expected)
        }
        if let signInError = snapshot.0 { throw signInError }
        guard let resolved = snapshot.1 else {
            throw NSError(
                domain: AuthErrorDomain,
                code: AuthErrorCode.userNotFound.rawValue
            )
        }
        if let expected = snapshot.2, expected != password {
            throw NSError(
                domain: AuthErrorDomain,
                code: AuthErrorCode.wrongPassword.rawValue
            )
        }
        setUID(resolved, email: email)
        return resolved
    }

    func signOut() async throws {
        setUID(nil, email: nil)
    }

    func reauthenticate(email: String, password: String) async throws {
        guard let uid = currentUID else {
            throw DomainError.authenticationFailed(.sessionInvalid)
        }
        let expected = lock.withLock { $0.passwordByEmail[email.lowercased()] }
        guard let expected, expected == password else {
            throw NSError(
                domain: AuthErrorDomain,
                code: AuthErrorCode.wrongPassword.rawValue
            )
        }
        _ = uid
    }

    func updatePassword(_ newPassword: String) async throws {
        guard let email = currentEmail else {
            throw DomainError.authenticationFailed(.sessionInvalid)
        }
        guard newPassword.count >= PasswordPolicy.minimumLength else {
            throw NSError(
                domain: AuthErrorDomain,
                code: AuthErrorCode.weakPassword.rawValue
            )
        }
        lock.withLock { $0.passwordByEmail[email.lowercased()] = newPassword }
    }

    /// Deterministic fake JWT-like string for unit tests (not a real Firebase token).
    private(set) var idTokenForceRefreshCallCount = 0
    private(set) var idTokenForceRefreshRequests: [Bool] = []

    func idToken(forceRefresh: Bool) async throws -> String {
        if forceRefresh {
            idTokenForceRefreshCallCount += 1
        }
        idTokenForceRefreshRequests.append(forceRefresh)
        guard let uid = currentUID else {
            throw DomainError.authenticationFailed(.sessionInvalid)
        }
        return "fake-id-token.\(uid)"
    }

    func authStateChanges() -> AsyncStream<String?> {
        AsyncStream { continuation in
            let id = UUID()
            lock.withLock { state in
                state.continuations[id] = continuation
                continuation.yield(state.uid)
            }
            continuation.onTermination = { [weak self] _ in
                self?.lock.withLock { $0.continuations[id] = nil }
            }
        }
    }
}
