import Foundation
import Observation

@Observable
@MainActor
final class ChangePasswordViewModel {
    enum Phase: Equatable {
        case idle
        case submitting
        case success
        case error(String)
    }

    var currentPassword = ""
    var newPassword = ""
    var confirmation = ""
    var showCurrentPassword = false
    var showNewPassword = false
    var showConfirmation = false

    private(set) var phase: Phase = .idle

    private let accountService: ProfileAccountService

    init(accountService: ProfileAccountService) {
        self.accountService = accountService
    }

    var canSubmit: Bool {
        guard phase != .submitting else { return false }
        guard !currentPassword.isEmpty else { return false }
        guard newPassword.count >= PasswordPolicy.minimumLength else { return false }
        guard newPassword == confirmation else { return false }
        guard newPassword != currentPassword else { return false }
        return true
    }

    var offlineHint: String? {
        // Evaluated at submit time for accuracy; UI can show static hint.
        nil
    }

    func submit() async {
        guard canSubmit else { return }
        phase = .submitting
        do {
            try await accountService.changePassword(
                currentPassword: currentPassword,
                newPassword: newPassword,
                confirmation: confirmation
            )
            currentPassword = ""
            newPassword = ""
            confirmation = ""
            phase = .success
        } catch let error as DomainError {
            if case .authenticationFailed(let reason) = error {
                phase = .error(
                    AuthErrorMessages.message(for: error)
                        ?? AuthErrorMessages.title(for: error)
                )
                if reason == .invalidCredentials {
                    // Wrong current password — keep fields for correction.
                }
            } else {
                phase = .error(error.operatorMessage)
            }
        } catch {
            phase = .error("Şifre değiştirilemedi.")
        }
    }
}
