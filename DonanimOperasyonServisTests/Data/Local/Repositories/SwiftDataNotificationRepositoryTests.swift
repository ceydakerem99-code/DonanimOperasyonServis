import XCTest
@testable import DonanimOperasyonServis

final class SwiftDataNotificationRepositoryTests: XCTestCase {

    private func makeNotification(
        id: NotificationID,
        recipient: UserID,
        isRead: Bool = false,
        type: NotificationType = .workOrderAssigned,
        createdAt: Date = DomainFixtures.referenceDate
    ) -> AppNotification {
        AppNotification(
            id: id,
            recipientUserId: recipient,
            type: type,
            title: "Test",
            body: "gövde",
            isRead: isRead,
            createdAt: createdAt
        )
    }

    func testSaveThenList() async throws {
        let harness = try SwiftDataTestHarness()
        let recipient = UserID("u-1")
        let n1 = makeNotification(id: NotificationID("n1"), recipient: recipient)
        let n2 = makeNotification(id: NotificationID("n2"), recipient: recipient)
        try await harness.notifications.save(n1)
        try await harness.notifications.save(n2)

        let list = try await harness.notifications.list(for: recipient, unreadOnly: false)
        XCTAssertEqual(Set(list.map(\.id)), Set([n1.id, n2.id]))
    }

    func testUnreadFilter() async throws {
        let harness = try SwiftDataTestHarness()
        let recipient = UserID("u-1")
        let unread = makeNotification(id: NotificationID("a"), recipient: recipient, isRead: false)
        let read = makeNotification(id: NotificationID("b"), recipient: recipient, isRead: true)
        try await harness.notifications.save(unread)
        try await harness.notifications.save(read)

        let unreadOnly = try await harness.notifications.list(for: recipient, unreadOnly: true)
        XCTAssertEqual(unreadOnly.map(\.id), [unread.id])
    }

    func testMarkAsRead() async throws {
        let harness = try SwiftDataTestHarness()
        let recipient = UserID("u-1")
        let notification = makeNotification(id: NotificationID("x"), recipient: recipient, isRead: false)
        try await harness.notifications.save(notification)

        try await harness.notifications.markAsRead(id: notification.id)

        let unreadOnly = try await harness.notifications.list(for: recipient, unreadOnly: true)
        XCTAssertTrue(unreadOnly.isEmpty)
        let all = try await harness.notifications.list(for: recipient, unreadOnly: false)
        XCTAssertTrue(all.first?.isRead == true)
    }

    func testDelete() async throws {
        let harness = try SwiftDataTestHarness()
        let recipient = UserID("u-1")
        let notification = makeNotification(id: NotificationID("x"), recipient: recipient)
        try await harness.notifications.save(notification)

        try await harness.notifications.delete(id: notification.id)
        let all = try await harness.notifications.list(for: recipient, unreadOnly: false)
        XCTAssertTrue(all.isEmpty)
    }

    func testRecipientScoping() async throws {
        let harness = try SwiftDataTestHarness()
        let ada = UserID("ada")
        let ben = UserID("ben")
        try await harness.notifications.save(makeNotification(id: NotificationID("1"), recipient: ada))
        try await harness.notifications.save(makeNotification(id: NotificationID("2"), recipient: ben))

        let adasList = try await harness.notifications.list(for: ada, unreadOnly: false)
        XCTAssertEqual(adasList.map(\.id), [NotificationID("1")])
    }
}
