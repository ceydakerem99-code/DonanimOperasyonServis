import Foundation

/// Admin updates for a user's active flag and/or fixed role assignment.
struct UpdateUserUseCase: Sendable {
    let userRepository: UserRepository

    init(userRepository: UserRepository) {
        self.userRepository = userRepository
    }

    @discardableResult
    func execute(
        actor: User,
        userId: UserID,
        isActive: Bool? = nil,
        role: UserRole? = nil,
        at now: Date = Date()
    ) async throws -> User {
        guard RoleAccessPolicy.can(.manageUsers, as: actor.role) else {
            throw DomainError.unauthorized(action: .manageUsers)
        }

        var user = try await userRepository.fetch(id: userId)
        if let isActive { user.isActive = isActive }
        if let role { user.role = role }
        user.updatedAt = now
        try await userRepository.save(user)
        return user
    }
}
