import Foundation

/// Client-side password rules aligned with Firebase Auth defaults
/// (minimum length 6). Domain stays framework-agnostic.
enum PasswordPolicy {
    static let minimumLength = 6

    static func validateNewPassword(
        _ newPassword: String,
        confirmation: String,
        currentPassword: String
    ) throws {
        let trimmedNew = newPassword
        let trimmedConfirm = confirmation
        guard trimmedNew == trimmedConfirm else {
            throw DomainError.authenticationFailed(.passwordsDoNotMatch)
        }
        guard trimmedNew.count >= minimumLength else {
            throw DomainError.authenticationFailed(.weakPassword)
        }
        guard trimmedNew != currentPassword else {
            throw DomainError.authenticationFailed(.sameAsCurrentPassword)
        }
    }
}
