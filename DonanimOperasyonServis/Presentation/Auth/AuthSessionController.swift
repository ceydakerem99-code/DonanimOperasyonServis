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
    private let realtimeCoordinator: RealtimeCoordinator?
    private let localDirectoryCacheRefresh: LocalDirectoryCacheRefresh?
    private var observationTask: Task<Void, Never>?
    private var restoreSessionTask: Task<Void, Never>?

    init(
        authRepository: any AuthRepository,
        realtimeCoordinator: RealtimeCoordinator? = nil,
        localDirectoryCacheRefresh: LocalDirectoryCacheRefresh? = nil
    ) {
        self.authRepository = authRepository
        self.realtimeCoordinator = realtimeCoordinator
        self.localDirectoryCacheRefresh = localDirectoryCacheRefresh
    }

    func start() async {
        await restoreSession()
        await startObservingAuthChanges()
    }

    func restoreSession() async {
        restoreSessionTask?.cancel()
        restoreSessionTask = Task { [weak self] in
            await self?.performRestoreSession(showChecking: true)
        }
        await restoreSessionTask?.value
    }

    private func performRestoreSession(showChecking: Bool) async {
        if showChecking, !Task.isCancelled {
            state = .checkingSession
        }
        do {
            if let user = try await authRepository.restoreSession() {
                guard !Task.isCancelled else { return }
                state = .authenticated(user)
                realtimeCoordinator?.handleAuthenticatedSession()
                await refreshRemoteDirectory()
            } else {
                guard !Task.isCancelled else { return }
                state = .unauthenticated
                realtimeCoordinator?.handleSignedOut()
            }
        } catch let error as DomainError {
            guard !Task.isCancelled else { return }
            state = .authenticationError(error)
        } catch {
            guard !Task.isCancelled else { return }
            state = .authenticationError(.authenticationFailed(.unknown))
        }
    }

    func signIn(email: String, password: String) async {
        isSigningIn = true
        defer { isSigningIn = false }
        // Cancel any in-flight restore kicked off by the Auth listener so it
        // cannot flash `.checkingSession` or sign the user out mid-login.
        restoreSessionTask?.cancel()
        restoreSessionTask = nil
        do {
            let user = try await authRepository.signIn(
                email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                password: password
            )
            guard !Task.isCancelled else { return }
            state = .authenticated(user)
            realtimeCoordinator?.handleAuthenticatedSession()
            await refreshRemoteDirectory()
        } catch let error as DomainError {
            state = .authenticationError(error)
        } catch {
            state = .authenticationError(.authenticationFailed(.unknown))
        }
    }

    func signOut() async {
        restoreSessionTask?.cancel()
        restoreSessionTask = nil
        do {
            try await authRepository.signOut()
            realtimeCoordinator?.handleSignedOut()
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
                realtimeCoordinator?.handleAuthenticatedSession()
            } else {
                state = .unauthenticated
                realtimeCoordinator?.handleSignedOut()
            }
        } catch let error as DomainError {
            state = .authenticationError(error)
        } catch {
            state = .authenticationError(.authenticationFailed(.unknown))
        }
    }

    private func refreshRemoteDirectory() async {
        guard let localDirectoryCacheRefresh else { return }

        print("🔥 DIRECTORY REFRESH START")

        await localDirectoryCacheRefresh.refreshUsers()
        await localDirectoryCacheRefresh.refreshCustomers()
        await localDirectoryCacheRefresh.refreshWorkOrders()

        print("🔥 DIRECTORY REFRESH COMPLETE")
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
        // Login owns the transition while credentials are in flight. Listener
        // restores here race with `signIn` and briefly bounce through
        // `.checkingSession` → login (often after clearing the real error).
        if isSigningIn { return }

        switch event {
        case .signedIn:
            if case .authenticated = state { return }
            restoreSessionTask?.cancel()
            restoreSessionTask = Task { [weak self] in
                // Keep the current screen (usually login); avoid a full-screen
                // "Oturum kontrol ediliyor..." flash on every Auth UID event.
                await self?.performRestoreSession(showChecking: false)
            }
            await restoreSessionTask?.value
        case .signedOut:
            restoreSessionTask?.cancel()
            restoreSessionTask = nil
            realtimeCoordinator?.handleSignedOut()
            state = .unauthenticated
        }
    }
}
