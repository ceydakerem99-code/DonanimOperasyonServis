import XCTest
@testable import DonanimOperasyonServis

/// Regression tests for Firebase sync payload/rules alignment.
final class FirebaseSyncRegressionTests: XCTestCase {

    private let now = DomainFixtures.referenceDate

    // TEST 1 — technician notification preference update patches only allowed fields.
    func testTechnicianSelfUpdatePatchesOnlyNotificationPreferencesAndUpdatedAt() async throws {
        let harness = FirebaseTestHarness()
        var user = DomainFixtures.technicianUser()
        try await harness.users.save(user)

        user.notificationPreferences = NotificationPreferences(
            enabledByKey: [NotificationPreferenceKey.workOrderAssigned.rawValue: false]
        )
        user.updatedAt = now.addingTimeInterval(60)
        try await harness.users.updateSelfServiceProfile(user)

        let dto = try await harness.firestore.fetch(
            FirestoreUserDTO.self,
            collection: .users,
            id: user.id.rawValue
        )
        let stored = try XCTUnwrap(dto)
        XCTAssertEqual(stored.email, "tech@example.com")
        XCTAssertEqual(stored.fullName, "Teknisyen Kullanıcı")
        XCTAssertEqual(stored.role, UserRole.technician.rawValue)
        XCTAssertEqual(
            stored.notificationPreferences,
            [NotificationPreferenceKey.workOrderAssigned.rawValue: false]
        )
        XCTAssertEqual(stored.updatedAt, user.updatedAt)
    }

    // TEST 2 — remote parent missing → child write is not attempted.
    func testChildSyncHeldWhenRemoteWorkOrderMissing() async throws {
        let env = try makeEnvironment(authUID: DomainFixtures.technicianUser().id.rawValue)
        let tech = DomainFixtures.technicianUser()
        let order = DomainFixtures.workOrder(
            assignedTechnicianId: tech.id,
            status: .inProgress
        )
        let location = DomainFixtures.location(
            workOrderId: order.id,
            event: .arrived,
            capturedByUserId: tech.id
        )
        try await env.local.users.save(tech)
        try await env.local.workOrders.save(order)
        try await env.local.locations.save(location)

        let operation = try SyncOperation.pending(
            id: SyncOperationID("op-loc-missing-parent"),
            entityType: .workOrderLocation,
            entityId: location.id,
            operationType: .create,
            payloadReference: order.id.rawValue,
            createdAt: now,
            localVersion: 1,
            actorUserId: tech.id.rawValue
        )
        _ = try await env.queue.enqueue(operation)
        try await env.manager.sync(operation: operation, now: now)

        let stored = try await env.queue.fetch(id: operation.id)
        XCTAssertEqual(stored.status, .pending)
        let writes = await env.probe.recordedWrites()
        XCTAssertTrue(writes.isEmpty)
    }

    // TEST 3 — remote parent exists and is assigned → child write succeeds.
    func testChildSyncSucceedsWhenRemoteWorkOrderReady() async throws {
        let env = try makeEnvironment(authUID: DomainFixtures.technicianUser().id.rawValue)
        let tech = DomainFixtures.technicianUser()
        let order = DomainFixtures.workOrder(
            assignedTechnicianId: tech.id,
            status: .inProgress
        )
        let note = DomainFixtures.note(workOrderId: order.id, authorUserId: tech.id)
        try await env.local.users.save(tech)
        try await env.local.workOrders.save(order)
        try await env.local.notes.save(note)
        try await SyncManagerTestFactory.seedRemoteWorkOrder(order, on: env.remoteWorkOrders)

        let operation = try SyncOperation.pending(
            id: SyncOperationID("op-note-ready-parent"),
            entityType: .workOrderNote,
            entityId: note.id,
            operationType: .create,
            payloadReference: order.id.rawValue,
            createdAt: now,
            localVersion: 1,
            actorUserId: tech.id.rawValue
        )
        _ = try await env.queue.enqueue(operation)
        try await env.manager.sync(operation: operation, now: now)

        let stored = try await env.queue.fetch(id: operation.id)
        XCTAssertEqual(stored.status, .succeeded)
        let writes = await env.probe.recordedWrites()
        XCTAssertEqual(writes, [.save(.workOrderNote, note.id)])
    }

    // TEST 4 — completed parent blocks technician child create before Firebase.
    func testChildSyncHeldWhenRemoteWorkOrderCompleted() async throws {
        let env = try makeEnvironment(authUID: DomainFixtures.technicianUser().id.rawValue)
        let tech = DomainFixtures.technicianUser()
        var order = DomainFixtures.workOrder(
            assignedTechnicianId: tech.id,
            status: .completed,
            completedAt: now
        )
        let location = DomainFixtures.location(
            workOrderId: order.id,
            event: .arrived,
            capturedByUserId: tech.id
        )
        try await env.local.users.save(tech)
        try await env.local.workOrders.save(order)
        try await env.local.locations.save(location)
        try await SyncManagerTestFactory.seedRemoteWorkOrder(order, on: env.remoteWorkOrders)

        let operation = try SyncOperation.pending(
            id: SyncOperationID("op-loc-completed-parent"),
            entityType: .workOrderLocation,
            entityId: location.id,
            operationType: .create,
            payloadReference: order.id.rawValue,
            createdAt: now,
            localVersion: 1,
            actorUserId: tech.id.rawValue
        )
        _ = try await env.queue.enqueue(operation)
        try await env.manager.sync(operation: operation, now: now)

        let stored = try await env.queue.fetch(id: operation.id)
        XCTAssertEqual(stored.status, .pending)
        let writes = await env.probe.recordedWrites()
        XCTAssertTrue(writes.isEmpty)
        _ = order
    }

    // TEST 5 — networkUnavailable is not mapped to unauthorized.
    func testNetworkUnavailableIsNotMappedToUnauthorized() {
        let mapped = SyncErrorMapping.from(
            DomainError.infrastructure(underlying: "firebase.networkUnavailable")
        )
        XCTAssertEqual(mapped, .networkUnavailable)
        XCTAssertNotEqual(mapped, .unauthorized)
    }

    // TEST 6 — permissionDenied is not mapped to networkUnavailable.
    func testPermissionDeniedIsNotMappedToNetworkUnavailable() {
        let mapped = SyncErrorMapping.from(
            DomainError.infrastructure(underlying: "firebase.permissionDenied")
        )
        XCTAssertEqual(mapped, .unauthorized)
        XCTAssertNotEqual(mapped, .networkUnavailable)
    }

    // TEST 7 — new queue rows preserve actor UID.
    func testPendingOperationPreservesActorUserId() throws {
        let operation = try SyncOperation.pending(
            entityType: .workOrderNote,
            entityId: "note-actor",
            operationType: .create,
            payloadReference: "wo-1",
            createdAt: now,
            localVersion: 1,
            actorUserId: "firebase-tech-uid"
        )
        XCTAssertEqual(operation.actorUserId, "firebase-tech-uid")
    }

    func testSelfServiceUserDispatchUsesPatchPath() async throws {
        let env = try makeEnvironment(authUID: DomainFixtures.technicianUser().id.rawValue)
        let tech = DomainFixtures.technicianUser()
        try await env.local.users.save(tech)

        let operation = try SyncOperation.pending(
            id: SyncOperationID("op-user-self"),
            entityType: .user,
            entityId: tech.id.rawValue,
            operationType: .update,
            createdAt: now,
            localVersion: 2,
            actorUserId: tech.id.rawValue
        )
        _ = try await env.queue.enqueue(operation)
        try await env.manager.sync(operation: operation, now: now)

        let writes = await env.probe.recordedWrites()
        XCTAssertEqual(writes, [.patchSelfService(.user, tech.id.rawValue)])
    }

    // MARK: - Environment

    private struct Environment {
        let local: SwiftDataTestHarness
        let queue: SwiftDataSyncOperationRepository
        let probe: SyncRemoteProbe
        let remoteWorkOrders: InMemoryWorkOrderRepository
        let manager: LocalToRemoteSyncManager
    }

    private func makeEnvironment(authUID: String?) throws -> Environment {
        let local = try SwiftDataTestHarness()
        let probe = SyncRemoteProbe()
        let remote = SyncManagerTestFactory.remoteBundle(probe: probe)
        let auth = FakeFirebaseAuthService()
        if let authUID { auth.setUID(authUID) }
        let localEntities = SyncEntityRepositories(
            users: local.users,
            customers: local.customers,
            workOrders: local.workOrders,
            notes: local.notes,
            photos: local.photos,
            locations: local.locations,
            statusHistory: local.statusHistory,
            signatures: local.signatures,
            editRequests: local.editRequests,
            customerSatisfactions: local.customerSatisfactions,
            notifications: local.notifications
        )
        let manager = LocalToRemoteSyncManager(
            queue: local.syncOperations,
            conflicts: local.syncConflicts,
            local: localEntities,
            remote: remote.repositories,
            reachability: FakeNetworkReachability(),
            authService: auth
        )
        return Environment(
            local: local,
            queue: local.syncOperations,
            probe: probe,
            remoteWorkOrders: remote.workOrders,
            manager: manager
        )
    }
}
