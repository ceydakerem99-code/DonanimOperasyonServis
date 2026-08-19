import Foundation

/// Firestore-backed implementation of `UserRepository`. Delegates
/// every storage call to `FirestoreDataSource`; never talks to the
/// Firebase SDK directly. Thrown errors are always `DomainError`.
struct FirebaseUserRepository: UserRepository {

    let dataSource: any FirestoreDataSource

    init(dataSource: any FirestoreDataSource) {
        self.dataSource = dataSource
    }

    func fetch(id: UserID) async throws -> User {
        try await FirebaseRepositoryMapper.run(entity: "User", id: id.rawValue) {
            guard let dto = try await dataSource.fetch(
                FirestoreUserDTO.self,
                collection: .users,
                id: id.rawValue
            ) else {
                throw DomainError.notFound(entity: "User", id: id.rawValue)
            }
            return try FirebaseRepositoryMapper.requireDomain(dto, entity: "User") { $0.toDomain() }
        }
    }

    func findByEmail(_ email: String) async throws -> User? {
        try await FirebaseRepositoryMapper.run(entity: "User", id: email) {
            let dtos = try await dataSource.list(
                FirestoreUserDTO.self,
                collection: .users,
                predicates: [.equal("email", .string(email))],
                orderBy: []
            )
            guard let dto = dtos.first else { return nil }
            return try FirebaseRepositoryMapper.requireDomain(dto, entity: "User") { $0.toDomain() }
        }
    }

    func list(role: UserRole?, isActive: Bool?) async throws -> [User] {
        try await FirebaseRepositoryMapper.run(entity: "User") {
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
    }

    func save(_ user: User) async throws {
        try await FirebaseRepositoryMapper.run(entity: "User", id: user.id.rawValue) {
            try await dataSource.set(
                FirestoreUserDTO(domain: user),
                collection: .users,
                id: user.id.rawValue
            )
        }
    }

    func delete(id: UserID) async throws {
        try await FirebaseRepositoryMapper.run(entity: "User", id: id.rawValue) {
            try await dataSource.delete(collection: .users, id: id.rawValue)
        }
    }
}
