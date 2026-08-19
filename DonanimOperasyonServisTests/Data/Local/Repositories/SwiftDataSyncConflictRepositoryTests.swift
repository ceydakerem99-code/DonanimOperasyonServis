import XCTest
@testable import DonanimOperasyonServis

final class SwiftDataSyncConflictRepositoryTests: XCTestCase {

    private let now = DomainFixtures.referenceDate

    func testSaveThenFetchRoundTripsFullValue() async throws {
        let harness = try SwiftDataTestHarness()
        let conflict = SyncConflict.unresolved(
            id: SyncConflictID("cf-1"),
            syncOperationId: SyncOperationID("op-1"),
            entityType: .workOrder,
            entityId: "wo-1",
            localVersion: 4,
            remoteVersion: 7,
            localReference: "local/wo-1/v4",
            remoteReference: "remote/wo-1/v7",
            detectedAt: now
        )

        try await harness.syncConflicts.save(conflict)
        let fetched = try await harness.syncConflicts.fetch(id: conflict.id)
        XCTAssertEqual(fetched, conflict)
        XCTAssertEqual(fetched.status, .unresolved)
        XCTAssertEqual(fetched.localVersion, 4)
        XCTAssertEqual(fetched.remoteVersion, 7)

        let byOperation = try await harness.syncConflicts.fetch(
            syncOperationId: SyncOperationID("op-1")
        )
        XCTAssertEqual(byOperation, conflict)
    }

    func testFetchUnknownIdThrowsNotFound() async throws {
        let harness = try SwiftDataTestHarness()
        await XCTAssertThrowsErrorAsync(
            try await harness.syncConflicts.fetch(id: SyncConflictID("missing"))
        ) { error in
            XCTAssertEqual(
                error as? DomainError,
                .notFound(entity: "SyncConflict", id: "missing")
            )
        }
    }

    func testListUnresolvedIsDeterministic() async throws {
        let harness = try SwiftDataTestHarness()
        let later = SyncConflict.unresolved(
            id: SyncConflictID("b"),
            syncOperationId: SyncOperationID("op-b"),
            entityType: .customer,
            entityId: "c-b",
            localVersion: 1,
            remoteVersion: 2,
            detectedAt: now.addingTimeInterval(10)
        )
        let earlyB = SyncConflict.unresolved(
            id: SyncConflictID("z"),
            syncOperationId: SyncOperationID("op-z"),
            entityType: .customer,
            entityId: "c-z",
            localVersion: 1,
            remoteVersion: 1,
            detectedAt: now
        )
        let earlyA = SyncConflict.unresolved(
            id: SyncConflictID("a"),
            syncOperationId: SyncOperationID("op-a"),
            entityType: .customer,
            entityId: "c-a",
            localVersion: 2,
            remoteVersion: 1,
            detectedAt: now
        )
        try await harness.syncConflicts.save(later)
        try await harness.syncConflicts.save(earlyB)
        try await harness.syncConflicts.save(earlyA)

        let listed = try await harness.syncConflicts.listUnresolved()
        XCTAssertEqual(listed.map(\.id.rawValue), ["a", "z", "b"])
    }

    func testOptionalReferencesRoundTrip() async throws {
        let harness = try SwiftDataTestHarness()
        let conflict = SyncConflict.unresolved(
            id: SyncConflictID("cf-nil"),
            syncOperationId: SyncOperationID("op-nil"),
            entityType: .notification,
            entityId: "n-1",
            localVersion: 1,
            remoteVersion: 0,
            localReference: nil,
            remoteReference: nil,
            detectedAt: now
        )
        try await harness.syncConflicts.save(conflict)
        let fetched = try await harness.syncConflicts.fetch(id: conflict.id)
        XCTAssertNil(fetched.localReference)
        XCTAssertNil(fetched.remoteReference)
    }

    func testCorruptStatusRawThrowsInvalidData() async throws {
        let harness = try SwiftDataTestHarness()
        let conflict = SyncConflict.unresolved(
            id: SyncConflictID("cf-bad"),
            syncOperationId: SyncOperationID("op-bad"),
            entityType: .editRequest,
            entityId: "er-1",
            localVersion: 1,
            remoteVersion: 1,
            detectedAt: now
        )
        try await harness.syncConflicts.save(conflict)
        try await harness.store.debugOverwriteSyncConflictStatusRaw(
            id: "cf-bad",
            statusRaw: "resolved"
        )

        await XCTAssertThrowsErrorAsync(
            try await harness.syncConflicts.fetch(id: conflict.id)
        ) { error in
            XCTAssertEqual(
                error as? DomainError,
                .invalidData(reason: "swiftData.SyncConflict.decodeFailed")
            )
        }
    }

    func testModelMappingDoesNotDefaultUnknownEnums() {
        let conflict = SyncConflict.unresolved(
            id: SyncConflictID("cf-map"),
            syncOperationId: SyncOperationID("op-map"),
            entityType: .workOrder,
            entityId: "wo-map",
            localVersion: 2,
            remoteVersion: 3,
            localReference: "l",
            remoteReference: "r",
            detectedAt: now
        )
        let model = SyncConflictModel(domain: conflict)
        XCTAssertEqual(model.toDomain(), conflict)

        model.entityTypeRaw = "syncConflict"
        XCTAssertNil(model.toDomain())
        model.entityTypeRaw = SyncEntityType.workOrder.rawValue

        model.statusRaw = "useLocal"
        XCTAssertNil(model.toDomain())
    }

    func testFetchByMissingSyncOperationIdReturnsNil() async throws {
        let harness = try SwiftDataTestHarness()
        let found = try await harness.syncConflicts.fetch(
            syncOperationId: SyncOperationID("none")
        )
        XCTAssertNil(found)
    }
}
