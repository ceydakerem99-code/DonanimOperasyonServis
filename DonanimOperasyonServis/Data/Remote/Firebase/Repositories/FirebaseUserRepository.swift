import Foundation

/// Firestore-backed implementation of `UserRepository`. Delegates
/// every storage call to `FirestoreDataSource`; never talks to the
/// Firebase SDK directly. The SwiftData counterpart
/// (`SwiftDataUserRepository`) is left untouched.
struct FirebaseUserRepository: UserRepository {

    let dataSource: any FirestoreDataSource

    init(dataSource: any FirestoreDataSource) {
        self.dataSource = dataSource
    }

    func fetch(id: UserID) async throws -> User {
        do {
            guard let dto = try await dataSource.fetch(
                FirestoreUserDTO.self,
                collection: .users,
                id: id.rawValue
            ) else {
                throw DomainError.notFound(entity: "User", id: id.rawValue)
            }
            return try FirebaseRepositoryMapper.requireDomain(dto, entity: "User") { $0.toDomain() }
        } catch {
            throw FirebaseRepositoryMapper.mapNotFound(error, entity: "User", id: id.rawValue)
        }
    }

    func findByEmail(_ email: String) async throws -> User? {
        let dtos = try await dataSource.list(
            FirestoreUserDTO.self,
            collection: .users,
            predicates: [.equal("email", .string(email))],
            orderBy: []
        )
        guard let dto = dtos.first else { return nil }
        return try FirebaseRepositoryMapper.requireDomain(dto, entity: "User") { $0.toDomain() }
    }

    func list(role: UserRole?, isActive: Bool?) async throws -> [User] {
        var predicates: [FirestorePredicate] = []
        if let role {
            predicates.append(.equal("role", .string(role.rawValue)))
        }
        if let isActive {
            predicates.append(.equal("isActive", .bool(isActive)))
        }
        let dtos = try await dataSource.list(
            FirestoreUserDTO.self,
            collection: .users,
            predicates: predicates,
            orderBy: [.ascending("fullName")]
        )
        return try dtos.map {
            try FirebaseRepositoryMapper.requireDomain($0, entity: "User") { $0.toDomain() }
        }
    }

    func save(_ user: User) async throws {
        try await dataSource.set(
            FirestoreUserDTO(domain: user),
            collection: .users,
            id: user.id.rawValue
        )
    }

    func delete(id: UserID) async throws {
        try await dataSource.delete(collection: .users, id: id.rawValue)
    }
}
