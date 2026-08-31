import Foundation

/// Admin user mutations with offline-first sync enqueue.
struct AdminUserService: Sendable {
    let updateUser: UpdateUserUseCase
    let createUserUseCase: CreateUserUseCase
    let remoteUsers: UserRepository
    let syncOperationRepository: SyncOperationRepository
    let networkReachability: NetworkReachabilityProviding

    func setActive(
        actor: User,
        userId: UserID,
        isActive: Bool,
        at now: Date = Date()
    ) async throws -> User {
        let updated = try await updateUser.execute(
            actor: actor,
            userId: userId,
            isActive: isActive,
            at: now
        )
        try await AdminSyncEnqueue.enqueueUpdate(
            entityType: .user,
            entityId: userId.rawValue,
            queue: syncOperationRepository,
            now: now,
            actorUserId: actor.id.rawValue
        )
        return updated
    }

    func assignRole(
        actor: User,
        userId: UserID,
        role: UserRole,
        at now: Date = Date()
    ) async throws -> User {
        let updated = try await updateUser.execute(
            actor: actor,
            userId: userId,
            role: role,
            at: now
        )
        try await AdminSyncEnqueue.enqueueUpdate(
            entityType: .user,
            entityId: userId.rawValue,
            queue: syncOperationRepository,
            now: now,
            actorUserId: actor.id.rawValue
        )
        return updated
    }

    /// Creates Auth + local profile, then writes Firestore immediately so
    /// the new user can sign in before background sync runs.
    @discardableResult
    func createUser(
        actor: User,
        email: String,
        password: String,
        fullName: String,
        role: UserRole,
        phoneNumber: String? = nil,
        at now: Date = Date()
    ) async throws -> User {
        guard await networkReachability.isReachable else {
            throw DomainError.infrastructure(underlying: "networkUnavailable")
        }

        let user = try await createUserUseCase.execute(
            actor: actor,
            email: email,
            password: password,
            fullName: fullName,
            role: role,
            phoneNumber: phoneNumber,
            at: now
        )

        do {
            try await remoteUsers.save(user)
        } catch {
            AppLogger.auth.error(
                "Remote user profile write failed after Auth create uid=\(user.id.rawValue, privacy: .public): \(String(describing: error), privacy: .public)"
            )
            throw DomainError.infrastructure(underlying: "user.remoteProfileWriteFailed")
        }

        try await AdminSyncEnqueue.enqueueCreate(
            entityType: .user,
            entityId: user.id.rawValue,
            queue: syncOperationRepository,
            now: now,
            actorUserId: actor.id.rawValue
        )
        return user
    }
}
