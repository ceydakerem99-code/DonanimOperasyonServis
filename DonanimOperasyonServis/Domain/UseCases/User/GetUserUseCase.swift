import Foundation

/// Fetches a single user for the admin surface.
struct GetUserUseCase: Sendable {
    let userRepository: UserRepository

    init(userRepository: UserRepository) {
        self.userRepository = userRepository
    }

    func execute(actor: User, id: UserID) async throws -> User {
        guard RoleAccessPolicy.can(.manageUsers, as: actor.role) else {
            throw DomainError.unauthorized(action: .manageUsers)
        }
        return try await userRepository.fetch(id: id)
    }
}
