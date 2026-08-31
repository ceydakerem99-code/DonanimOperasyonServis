import Foundation

/// Shared account mutations for profile screens (all roles).
struct ProfileAccountService: Sendable {
    let changePasswordUseCase: ChangePasswordUseCase
    let updateNotificationPreferencesUseCase: UpdateNotificationPreferencesUseCase
    let userRepository: UserRepository
    let syncOperationRepository: SyncOperationRepository
    let networkReachability: NetworkReachabilityProviding

    func changePassword(
        currentPassword: String,
        newPassword: String,
        confirmation: String
    ) async throws {
        try await changePasswordUseCase.execute(
            currentPassword: currentPassword,
            newPassword: newPassword,
            confirmation: confirmation
        )
    }

    @discardableResult
    func setNotificationPreference(
        actor: User,
        key: NotificationPreferenceKey,
        enabled: Bool,
        at now: Date = Date()
    ) async throws -> User {
        let updated = try await updateNotificationPreferencesUseCase.execute(
            actor: actor,
            key: key,
            enabled: enabled,
            at: now
        )
        try await TechnicianSyncEnqueue.enqueueUpdate(
            entityType: .user,
            entityId: updated.id.rawValue,
            queue: syncOperationRepository,
            now: now,
            actorUserId: actor.id.rawValue
        )
        return updated
    }

    func loadUser(id: UserID) async throws -> User {
        try await userRepository.fetch(id: id)
    }
}
