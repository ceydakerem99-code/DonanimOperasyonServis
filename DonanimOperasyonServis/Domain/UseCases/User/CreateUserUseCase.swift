import Foundation

/// Admin creates a new Auth account + local `User` profile.
///
/// Auth provisioning must not touch the signed-in admin session.
/// Remote Firestore write / sync enqueue stay in `AdminUserService`.
struct CreateUserUseCase: Sendable {
    let userRepository: UserRepository
    let authAccounts: AuthAccountCreating

    init(userRepository: UserRepository, authAccounts: AuthAccountCreating) {
        self.userRepository = userRepository
        self.authAccounts = authAccounts
    }

    func execute(
        actor: User,
        email: String,
        password: String,
        fullName: String,
        role: UserRole,
        phoneNumber: String? = nil,
        at now: Date = Date()
    ) async throws -> User {
        guard RoleAccessPolicy.can(.manageUsers, as: actor.role) else {
            throw DomainError.unauthorized(action: .manageUsers)
        }

        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let trimmedName = fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPhone = phoneNumber?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalizedEmail.isEmpty, normalizedEmail.contains("@") else {
            throw DomainError.invalidData(reason: "user.invalidEmail")
        }
        guard password.count >= 6 else {
            throw DomainError.invalidData(reason: "user.weakPassword")
        }
        guard !trimmedName.isEmpty else {
            throw DomainError.invalidData(reason: "user.fullNameRequired")
        }

        if let existing = try await userRepository.findByEmail(normalizedEmail) {
            throw DomainError.invalidData(
                reason: "user.emailAlreadyExists:\(existing.id.rawValue)"
            )
        }

        let phone: PhoneNumber?
        if let trimmedPhone, !trimmedPhone.isEmpty {
            let candidate = PhoneNumber(trimmedPhone)
            guard candidate.isPlausible else {
                throw DomainError.invalidData(reason: "user.invalidPhone")
            }
            phone = candidate
        } else {
            phone = nil
        }

        let uid = try await authAccounts.createAccount(
            email: normalizedEmail,
            password: password
        )

        let user = User(
            id: uid,
            email: normalizedEmail,
            fullName: trimmedName,
            role: role,
            phoneNumber: phone,
            isActive: true,
            createdAt: now,
            updatedAt: now
        )
        try await userRepository.save(user)
        return user
    }
}
