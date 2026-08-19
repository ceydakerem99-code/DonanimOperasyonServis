import Foundation
import FirebaseAuth
import os

/// Deterministic Firebase Auth stand-in for unit tests and previews.
/// Never touches the real SDK or network.
final class FakeFirebaseAuthService: FirebaseAuthServing, @unchecked Sendable {

    private struct State {
        var uid: String?
        var emailToUID: [String: String] = [:]
        var continuations: [UUID: AsyncStream<String?>.Continuation] = [:]
        var signInError: Error?
    }

    private let lock = OSAllocatedUnfairLock(initialState: State())

    func register(email: String, uid: String) {
        lock.withLock { $0.emailToUID[email.lowercased()] = uid }
    }

    func setUID(_ uid: String?) {
        let continuations = lock.withLock { state -> [AsyncStream<String?>.Continuation] in
            let changed = state.uid != uid
            state.uid = uid
            return changed ? Array(state.continuations.values) : []
        }
        for continuation in continuations {
            continuation.yield(uid)
        }
    }

    var currentUID: String? {
        lock.withLock { $0.uid }
    }

    func signIn(email: String, password: String) async throws -> String {
        _ = password
        let snapshot = lock.withLock { state -> (Error?, String?) in
            if let signInError = state.signInError { return (signInError, nil) }
            let resolved = state.emailToUID[email.lowercased()]
            return (nil, resolved)
        }
        if let signInError = snapshot.0 { throw signInError }
        guard let resolved = snapshot.1 else {
            throw NSError(
                domain: AuthErrorDomain,
                code: AuthErrorCode.userNotFound.rawValue
            )
        }
        setUID(resolved)
        return resolved
    }

    func signOut() async throws {
        setUID(nil)
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
