import Foundation

/// Updates the signed-in user's notification display preferences.
/// Persistence only — sync enqueue belongs to the presentation
/// account service so Domain stays free of Sync helpers.
struct UpdateNotificationPreferencesUseCase: Sendable {
    let userRepository: UserRepository

    init(userRepository: UserRepository) {
        self.userRepository = userRepository
    }

    @discardableResult
    func execute(
        actor: User,
        key: NotificationPreferenceKey,
        enabled: Bool,
        at now: Date = Date()
    ) async throws -> User {
        guard NotificationPreferencePolicy.visibleKeys(for: actor.role).contains(key) else {
            throw DomainError.invalidData(reason: "notificationPreference.notVisibleForRole")
        }

        var user = try await userRepository.fetch(id: actor.id)
        guard user.id == actor.id else {
            throw DomainError.invalidData(reason: "notificationPreference.selfOnly")
        }

        var prefs = user.notificationPreferences
        prefs.set(key, enabled: enabled)
        user.notificationPreferences = prefs
        user.updatedAt = now
        try await userRepository.save(user)
        return user
    }
}
