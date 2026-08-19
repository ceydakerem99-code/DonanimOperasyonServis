import Foundation

/// Lists users for the admin surface.
struct ListUsersUseCase: Sendable {
    let userRepository: UserRepository

    init(userRepository: UserRepository) {
        self.userRepository = userRepository
    }

    func execute(
        actor: User,
        role: UserRole? = nil,
        isActive: Bool? = nil
    ) async throws -> [User] {
        guard RoleAccessPolicy.can(.manageUsers, as: actor.role) else {
            throw DomainError.unauthorized(action: .manageUsers)
        }
        return try await userRepository.list(role: role, isActive: isActive)
    }
}
