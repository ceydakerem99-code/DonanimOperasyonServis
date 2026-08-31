import Foundation

/// Changes the signed-in user's Firebase Auth password after
/// verifying the current password (re-authentication).
struct ChangePasswordUseCase: Sendable {
    let authRepository: AuthRepository
    let networkReachability: NetworkReachabilityProviding

    init(
        authRepository: AuthRepository,
        networkReachability: NetworkReachabilityProviding
    ) {
        self.authRepository = authRepository
        self.networkReachability = networkReachability
    }

    func execute(
        currentPassword: String,
        newPassword: String,
        confirmation: String
    ) async throws {
        guard await networkReachability.isReachable else {
            throw DomainError.authenticationFailed(.networkUnavailable)
        }
        try PasswordPolicy.validateNewPassword(
            newPassword,
            confirmation: confirmation,
            currentPassword: currentPassword
        )
        try await authRepository.changePassword(
            currentPassword: currentPassword,
            newPassword: newPassword
        )
    }
}
