import XCTest
@testable import DonanimOperasyonServis

final class FirebaseNotificationRepositoryTests: XCTestCase {

    private func makeNotification(
        id: NotificationID,
        recipient: UserID,
        isRead: Bool = false,
        createdAt: Date = DomainFixtures.referenceDate
    ) -> AppNotification {
        AppNotification(
            id: id,
            recipientUserId: recipient,
            type: .workOrderAssigned,
            title: "T",
            body: "B",
            isRead: isRead,
            createdAt: createdAt
        )
    }

    func testSaveListUnreadMarkAsReadDelete() async throws {
        let harness = FirebaseTestHarness()
        let recipient = UserID("u-1")
        let other = UserID("u-2")
        let unread = makeNotification(id: NotificationID("a"), recipient: recipient, isRead: false)
        let read = makeNotification(
            id: NotificationID("b"),
            recipient: recipient,
            isRead: true,
            createdAt: DomainFixtures.referenceDate.addingTimeInterval(-60)
        )
        let foreign = makeNotification(id: NotificationID("c"), recipient: other)
        try await harness.notifications.save(unread)
        try await harness.notifications.save(read)
        try await harness.notifications.save(foreign)

        let all = try await harness.notifications.list(for: recipient, unreadOnly: false)
        XCTAssertEqual(Set(all.map(\.id)), Set([unread.id, read.id]))

        let unreadOnly = try await harness.notifications.list(for: recipient, unreadOnly: true)
        XCTAssertEqual(unreadOnly.map(\.id), [unread.id])

        try await harness.notifications.markAsRead(id: unread.id)
        let afterRead = try await harness.notifications.list(for: recipient, unreadOnly: true)
        XCTAssertTrue(afterRead.isEmpty)

        try await harness.notifications.delete(id: unread.id)
        let remaining = try await harness.notifications.list(for: recipient, unreadOnly: false)
        XCTAssertEqual(remaining.map(\.id), [read.id])
    }

    func testMarkAsReadUnknownThrowsNotFound() async throws {
        let harness = FirebaseTestHarness()
        await XCTAssertThrowsErrorAsync(
            try await harness.notifications.markAsRead(id: NotificationID("missing"))
        ) { error in
            XCTAssertEqual(error as? DomainError, .notFound(entity: "AppNotification", id: "missing"))
        }
    }
}
