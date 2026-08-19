import Foundation

/// Admin user mutations with offline-first sync enqueue.
struct AdminUserService: Sendable {
    let updateUser: UpdateUserUseCase
    let syncOperationRepository: SyncOperationRepository

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
            now: now
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
            now: now
        )
        return updated
    }
}
