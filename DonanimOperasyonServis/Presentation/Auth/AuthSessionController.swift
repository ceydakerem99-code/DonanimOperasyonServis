import Foundation
import Observation
import SwiftUI

/// Owns `AuthState` and bridges `AuthRepository` to SwiftUI routing.
/// Lives on the main actor; Firebase listeners stay in Data layer.
@Observable
@MainActor
final class AuthSessionController {

    private(set) var state: AuthState = .checkingSession
    private(set) var isSigningIn = false

    private let authRepository: any AuthRepository
    private var observationTask: Task<Void, Never>?

    init(authRepository: any AuthRepository) {
        self.authRepository = authRepository
    }

    func start() async {
        await restoreSession()
        await startObservingAuthChanges()
    }

    func restoreSession() async {
        state = .checkingSession
        do {
            if let user = try await authRepository.restoreSession() {
                state = .authenticated(user)
            } else {
                state = .unauthenticated
            }
        } catch let error as DomainError {
            state = .authenticationError(error)
        } catch {
            state = .authenticationError(.authenticationFailed(.unknown))
        }
    }

    func signIn(email: String, password: String) async {
        isSigningIn = true
        defer { isSigningIn = false }
        do {
            let user = try await authRepository.signIn(
                email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                password: password
            )
            state = .authenticated(user)
        } catch let error as DomainError {
            state = .authenticationError(error)
        } catch {
            state = .authenticationError(.authenticationFailed(.unknown))
        }
    }

    func signOut() async {
        do {
            try await authRepository.signOut()
            state = .unauthenticated
        } catch let error as DomainError {
            state = .authenticationError(error)
        } catch {
            state = .authenticationError(.authenticationFailed(.unknown))
        }
    }

    func refreshCurrentUser() async {
        guard case .authenticated = state else { return }
        do {
            if let user = try await authRepository.refreshCurrentUser() {
                state = .authenticated(user)
            } else {
                state = .unauthenticated
            }
        } catch let error as DomainError {
            state = .authenticationError(error)
        } catch {
            state = .authenticationError(.authenticationFailed(.unknown))
        }
    }

    func clearAuthenticationError() {
        if case .authenticationError = state {
            state = .unauthenticated
        }
    }

    private func startObservingAuthChanges() async {
        guard observationTask == nil else { return }
        let stream = await authRepository.authStateChanges()
        observationTask = Task { [weak self] in
            var previous: AuthSessionEvent?
            for await event in stream {
                let prior = previous
                previous = event
                guard prior != nil else { continue }
                await self?.handleAuthEvent(event)
            }
        }
    }

    private func handleAuthEvent(_ event: AuthSessionEvent) async {
        switch event {
        case .signedIn:
            await restoreSession()
        case .signedOut:
            state = .unauthenticated
        }
    }
}
