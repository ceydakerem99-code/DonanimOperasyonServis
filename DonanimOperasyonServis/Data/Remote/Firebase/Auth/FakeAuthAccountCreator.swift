import Foundation
import os

/// Deterministic Auth account creator for unit tests and `DIContainer.mock()`.
final class FakeAuthAccountCreator: AuthAccountCreating, @unchecked Sendable {

    private struct State {
        var nextUID: String = "created-uid-1"
        var emailToUID: [String: String] = [:]
        var error: DomainError?
    }

    private let lock = OSAllocatedUnfairLock(initialState: State())

    func setNextUID(_ uid: String) {
        lock.withLock { $0.nextUID = uid }
    }

    func setError(_ error: DomainError?) {
        lock.withLock { $0.error = error }
    }

    func createAccount(email: String, password: String) async throws -> UserID {
        _ = password
        let result: Result<UserID, DomainError> = lock.withLock { state in
            if let error = state.error {
                return .failure(error)
            }
            let key = email.lowercased()
            if state.emailToUID[key] != nil {
                return .failure(.invalidData(reason: "user.emailAlreadyExists"))
            }
            let uid = state.nextUID
            state.emailToUID[key] = uid
            state.nextUID = "created-uid-\(state.emailToUID.count + 1)"
            return .success(UserID(uid))
        }
        switch result {
        case .success(let uid): return uid
        case .failure(let error): throw error
        }
    }
}
