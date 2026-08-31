import Foundation
import Observation
import UserNotifications

@Observable
@MainActor
final class NotificationSettingsViewModel {
    enum Phase: Equatable {
        case loading
        case loaded
        case saving
        case error(String)
    }

    private(set) var phase: Phase = .loading
    private(set) var preferences: NotificationPreferences = .default
    private(set) var systemAuthStatusDescription = "Kontrol ediliyor…"
    private(set) var systemAuthDenied = false

    private let actor: User
    private let accountService: ProfileAccountService
    private let asyncLoad = AsyncLoadSession()

    var showsLoadingIndicator: Bool { asyncLoad.showsLoadingIndicator }
    var hasCachedContent: Bool { phase == .loaded || phase == .saving }

    init(actor: User, accountService: ProfileAccountService) {
        self.actor = actor
        self.accountService = accountService
    }

    var operationalKeys: [NotificationPreferenceKey] {
        NotificationPreferencePolicy.operationalKeys(for: actor.role)
    }

    var systemKeys: [NotificationPreferenceKey] {
        NotificationPreferencePolicy.systemKeys(for: actor.role)
    }

    func isEnabled(_ key: NotificationPreferenceKey) -> Bool {
        preferences.isEnabled(key)
    }

    func load() async {
        let context = asyncLoad.start(hadCachedContent: hasCachedContent)
        if !context.hadCachedContentAtStart { phase = .loading }
        defer { asyncLoad.finish(generation: context.generation) }
        let generation = context.generation
        await refreshSystemAuthorizationStatus()
        do {
            let user = try await accountService.loadUser(id: actor.id)
            guard asyncLoad.isCurrent(generation) else { return }
            preferences = user.notificationPreferences
            phase = .loaded
        } catch is CancellationError {
            if let settled = asyncLoad.settleCancelledLoad(
                context: context,
                phase: phase,
                loadingPhase: Phase.loading,
                loadedPhase: Phase.loaded,
                emptyPhase: Phase.error("Bildirim ayarları yüklenemedi.")
            ) {
                phase = settled
            }
        } catch {
            guard asyncLoad.isCurrent(generation) else { return }
            phase = .error("Bildirim ayarları yüklenemedi.")
        }
    }

    func set(_ key: NotificationPreferenceKey, enabled: Bool) async {
        guard phase != .saving else { return }
        let previous = preferences
        var optimistic = preferences
        optimistic.set(key, enabled: enabled)
        preferences = optimistic
        phase = .saving
        do {
            let user = try await accountService.setNotificationPreference(
                actor: actor,
                key: key,
                enabled: enabled
            )
            preferences = user.notificationPreferences
            phase = .loaded
        } catch {
            preferences = previous
            phase = .error("Ayar kaydedilemedi. Tekrar deneyin.")
        }
    }

    func requestSystemPermission() async {
        _ = try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge])
        await refreshSystemAuthorizationStatus()
    }

    private func refreshSystemAuthorizationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            systemAuthDenied = false
            systemAuthStatusDescription = "iOS bildirimleri açık"
        case .denied:
            systemAuthDenied = true
            systemAuthStatusDescription = "iOS bildirimleri kapalı (Sistem Ayarları)"
        case .notDetermined:
            systemAuthDenied = false
            systemAuthStatusDescription = "iOS bildirim izni henüz sorulmadı"
        @unknown default:
            systemAuthDenied = false
            systemAuthStatusDescription = "iOS bildirim durumu bilinmiyor"
        }
    }
}
