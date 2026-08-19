import Foundation

/// SwiftData-backed implementation of `UserRepository`. Delegates all
/// storage work to the shared `LocalPersistence` actor so writes and
/// reads observe the same `ModelContext`.
struct SwiftDataUserRepository: UserRepository {

    let store: LocalPersistence

    init(store: LocalPersistence) {
        self.store = store
    }

    func fetch(id: UserID) async throws -> User {
        guard let user = try await store.fetchUser(id: id.rawValue) else {
            throw DomainError.notFound(entity: "User", id: id.rawValue)
        }
        return user
    }

    func findByEmail(_ email: String) async throws -> User? {
        try await store.findUserByEmail(email)
    }

    func list(role: UserRole?, isActive: Bool?) async throws -> [User] {
        var users = try await store.listUsers()
        if let role { users = users.filter { $0.role == role } }
        if let isActive { users = users.filter { $0.isActive == isActive } }
        return users
    }

    func save(_ user: User) async throws {
        try await store.upsertUser(user)
    }

    func delete(id: UserID) async throws {
        try await store.deleteUser(id: id.rawValue)
    }
}
