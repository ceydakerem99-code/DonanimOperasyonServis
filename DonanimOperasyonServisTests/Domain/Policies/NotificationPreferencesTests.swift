import XCTest
@testable import DonanimOperasyonServis

final class NotificationPreferencesTests: XCTestCase {

    func testMissingKeysDefaultToEnabled() {
        let prefs = NotificationPreferences.default
        XCTAssertTrue(prefs.isEnabled(.workOrderAssigned))
        XCTAssertTrue(prefs.allowsDisplay(of: .workOrderCompleted))
    }

    func testDisabledTypeIsHiddenFromDisplay() {
        var prefs = NotificationPreferences.default
        prefs.set(.workOrderAssigned, enabled: false)
        XCTAssertFalse(prefs.allowsDisplay(of: .workOrderAssigned))
        XCTAssertTrue(prefs.allowsDisplay(of: .workOrderCompleted))
    }

    func testRoleVisibleKeysMatrix() {
        let tech = Set(NotificationPreferencePolicy.visibleKeys(for: .technician))
        XCTAssertTrue(tech.contains(.workOrderAssigned))
        XCTAssertFalse(tech.contains(.workOrderCompleted))
        XCTAssertFalse(tech.contains(.editRequestCreated))

        let op = Set(NotificationPreferencePolicy.visibleKeys(for: .operator))
        XCTAssertTrue(op.contains(.workOrderCompleted))
        XCTAssertTrue(op.contains(.editRequestCreated))

        let admin = Set(NotificationPreferencePolicy.visibleKeys(for: .admin))
        XCTAssertFalse(admin.contains(.workOrderAssigned))
        XCTAssertTrue(admin.contains(.system))
        XCTAssertTrue(admin.contains(.syncConflict))
    }
}

final class UpdateNotificationPreferencesUseCaseTests: XCTestCase {

    func testTogglePersistsLocallyAndSurvivesReload() async throws {
        let users = InMemoryUserRepository()
        var user = DomainFixtures.technicianUser()
        try await users.save(user)

        let useCase = UpdateNotificationPreferencesUseCase(userRepository: users)
        user = try await useCase.execute(
            actor: user,
            key: .workOrderAssigned,
            enabled: false
        )
        XCTAssertFalse(user.notificationPreferences.isEnabled(.workOrderAssigned))

        let reloaded = try await users.fetch(id: user.id)
        XCTAssertFalse(reloaded.notificationPreferences.isEnabled(.workOrderAssigned))
    }

    func testHiddenKeyForRoleIsRejected() async throws {
        let users = InMemoryUserRepository()
        let user = DomainFixtures.technicianUser()
        try await users.save(user)
        let useCase = UpdateNotificationPreferencesUseCase(userRepository: users)

        do {
            _ = try await useCase.execute(
                actor: user,
                key: .workOrderCompleted,
                enabled: false
            )
            XCTFail("technician should not see completed preference")
        } catch let error as DomainError {
            XCTAssertEqual(error, .invalidData(reason: "notificationPreference.notVisibleForRole"))
        }
    }
}

@MainActor
final class ChangePasswordViewModelTests: XCTestCase {

    func testSubmitDisabledUntilValid() async throws {
        let container = DIContainer.mock()
        let auth = try XCTUnwrap(container.authRepository as? FakeAuthRepository)
        let user = DomainFixtures.technicianUser()
        auth.seed(user: user, password: "old-pass-1")
        _ = try await auth.signIn(email: user.email, password: "old-pass-1")

        let vm = ChangePasswordViewModel(accountService: container.makeProfileAccountService())
        XCTAssertFalse(vm.canSubmit)

        vm.currentPassword = "old-pass-1"
        vm.newPassword = "new-pass-1"
        vm.confirmation = "new-pass-1"
        XCTAssertTrue(vm.canSubmit)

        await vm.submit()
        XCTAssertEqual(vm.phase, .success)
    }

    func testDuplicateSubmitWhileSubmittingIsBlocked() async throws {
        let container = DIContainer.mock()
        let auth = try XCTUnwrap(container.authRepository as? FakeAuthRepository)
        let user = DomainFixtures.operatorUser()
        auth.seed(user: user, password: "old-pass-1")
        _ = try await auth.signIn(email: user.email, password: "old-pass-1")

        let vm = ChangePasswordViewModel(accountService: container.makeProfileAccountService())
        vm.currentPassword = "old-pass-1"
        vm.newPassword = "new-pass-1"
        vm.confirmation = "new-pass-1"

        async let first: Void = vm.submit()
        var blockedDuplicate = false
        for _ in 0..<20 {
            if vm.phase == .submitting || !vm.canSubmit {
                blockedDuplicate = true
                break
            }
            await Task.yield()
        }
        XCTAssertTrue(blockedDuplicate)
        await first
        XCTAssertEqual(vm.phase, .success)
    }
}

@MainActor
final class NotificationPreferenceInboxFilterTests: XCTestCase {

    func testDisabledPreferenceHidesFromOperatorInboxButRecordRemains() async throws {
        let container = DIContainer.mock()
        let deps = container.makeOperatorDependencies()
        let op = DomainFixtures.operatorUser()
        try await deps.userRepository.save(op)

        let notification = DomainFixtures.notification(
            recipientUserId: op.id,
            type: .workOrderAssigned
        )
        try await deps.notificationRepository.save(notification)

        _ = try await deps.profileAccountService.setNotificationPreference(
            actor: op,
            key: .workOrderAssigned,
            enabled: false
        )

        let vm = OperatorNotificationListViewModel(actor: op, dependencies: deps)
        await vm.load()
        XCTAssertEqual(vm.phase, .empty)
        XCTAssertTrue(vm.notifications.isEmpty)

        let stored = try await deps.notificationRepository.list(for: op.id, unreadOnly: false)
        XCTAssertEqual(stored.count, 1)
    }
}
