import XCTest
@testable import DonanimOperasyonServis

final class SwiftDataSyncOperationRepositoryTests: XCTestCase {

    private let now = DomainFixtures.referenceDate

    // MARK: - Enqueue / fetch / update / delete

    func testEnqueueThenFetchRoundTripsFullValue() async throws {
        let harness = try SwiftDataTestHarness()
        let operation = try makeOperation(
            id: "op-1",
            entityId: "cust-1",
            createdAt: now,
            payloadReference: "customers/cust-1",
            localVersion: 3,
            remoteVersion: 2
        )

        let outcome = try await harness.syncOperations.enqueue(operation)
        guard case .inserted(let inserted) = outcome else {
            return XCTFail("expected inserted")
        }
        XCTAssertEqual(inserted, operation)

        let fetched = try await harness.syncOperations.fetch(id: operation.id)
        XCTAssertEqual(fetched, operation)
        XCTAssertEqual(fetched.idempotencyKey.rawValue, "customer:cust-1:create:v3")
        XCTAssertEqual(fetched.status, .pending)
        XCTAssertEqual(fetched.retryCount, 0)
        XCTAssertNil(fetched.lastAttemptAt)
        XCTAssertNil(fetched.nextRetryAt)
        XCTAssertEqual(fetched.localVersion, 3)
        XCTAssertEqual(fetched.remoteVersion, 2)
        XCTAssertEqual(fetched.payloadReference, "customers/cust-1")
    }

    func testFetchUnknownIdThrowsNotFound() async throws {
        let harness = try SwiftDataTestHarness()
        await XCTAssertThrowsErrorAsync(
            try await harness.syncOperations.fetch(id: SyncOperationID("missing"))
        ) { error in
            XCTAssertEqual(
                error as? DomainError,
                .notFound(entity: "SyncOperation", id: "missing")
            )
        }
    }

    func testUpdatePersistsRetryFieldsWithoutStatusChange() async throws {
        let harness = try SwiftDataTestHarness()
        var operation = try makeOperation(id: "op-retry", entityId: "e-1", createdAt: now)
        try await harness.syncOperations.enqueue(operation)

        operation.retryCount = 1
        operation.lastAttemptAt = now.addingTimeInterval(10)
        operation.nextRetryAt = now.addingTimeInterval(20)
        operation.errorMessage = "networkUnavailable"
        operation.updatedAt = now.addingTimeInterval(10)

        try await harness.syncOperations.update(operation)
        let fetched = try await harness.syncOperations.fetch(id: operation.id)
        XCTAssertEqual(fetched.retryCount, 1)
        XCTAssertEqual(fetched.lastAttemptAt, operation.lastAttemptAt)
        XCTAssertEqual(fetched.nextRetryAt, operation.nextRetryAt)
        XCTAssertEqual(fetched.errorMessage, "networkUnavailable")
        XCTAssertEqual(fetched.status, .pending)
    }

    func testDeleteSucceededRemovesRow() async throws {
        let harness = try SwiftDataTestHarness()
        let operation = try makeOperation(id: "op-done", entityId: "e-done", createdAt: now)
        try await harness.syncOperations.enqueue(operation)
        try await advance(operation, through: harness, to: .succeeded)

        try await harness.syncOperations.delete(id: operation.id)
        await XCTAssertThrowsErrorAsync(
            try await harness.syncOperations.fetch(id: operation.id)
        ) { error in
            XCTAssertEqual(
                error as? DomainError,
                .notFound(entity: "SyncOperation", id: "op-done")
            )
        }
    }

    func testDeletePendingIsRejected() async throws {
        let harness = try SwiftDataTestHarness()
        let operation = try makeOperation(id: "op-pend", entityId: "e-pend", createdAt: now)
        try await harness.syncOperations.enqueue(operation)

        await XCTAssertThrowsErrorAsync(
            try await harness.syncOperations.delete(id: operation.id)
        ) { error in
            XCTAssertEqual(
                error as? DomainError,
                .invalidData(reason: "syncOperation.deleteOnlySucceeded")
            )
        }
        let stillThere = try await harness.syncOperations.fetch(id: operation.id)
        XCTAssertEqual(stillThere.status, .pending)
    }

    // MARK: - Idempotency

    func testDuplicateIdempotencyKeyDoesNotInsertOrOverwrite() async throws {
        let harness = try SwiftDataTestHarness()
        let key = SyncIdempotencyKey.make(
            entityType: .customer,
            entityId: "cust-dup",
            operationType: .create,
            localVersion: 1
        )
        let first = try makeOperation(
            id: "first",
            entityId: "cust-dup",
            createdAt: now,
            payloadReference: "original",
            idempotencyKey: key
        )
        var second = try makeOperation(
            id: "second",
            entityId: "cust-dup",
            createdAt: now.addingTimeInterval(60),
            payloadReference: "should-not-write",
            idempotencyKey: key
        )
        second.retryCount = 9

        let firstOutcome = try await harness.syncOperations.enqueue(first)
        let secondOutcome = try await harness.syncOperations.enqueue(second)

        guard case .inserted = firstOutcome else { return XCTFail("first should insert") }
        guard case .duplicate(let existing) = secondOutcome else {
            return XCTFail("second should be duplicate")
        }
        XCTAssertEqual(existing.id, first.id)
        XCTAssertEqual(existing.payloadReference, "original")
        XCTAssertEqual(existing.retryCount, 0)

        await XCTAssertThrowsErrorAsync(
            try await harness.syncOperations.fetch(id: SyncOperationID("second"))
        ) { error in
            XCTAssertEqual(
                error as? DomainError,
                .notFound(entity: "SyncOperation", id: "second")
            )
        }
        let stored = try await harness.syncOperations.fetch(id: first.id)
        XCTAssertEqual(stored.payloadReference, "original")
        let pendingCount = try await harness.syncOperations.countPending(now: now)
        XCTAssertEqual(pendingCount, 1)
    }

    func testConcurrentEnqueueOfSameKeyYieldsSingleRow() async throws {
        let harness = try SwiftDataTestHarness()
        let key = SyncIdempotencyKey.make(
            entityType: .user,
            entityId: "u-race",
            operationType: .update,
            localVersion: 4
        )
        let a = try makeOperation(
            id: "race-a",
            entityType: .user,
            entityId: "u-race",
            operationType: .update,
            createdAt: now,
            localVersion: 4,
            idempotencyKey: key
        )
        let b = try makeOperation(
            id: "race-b",
            entityType: .user,
            entityId: "u-race",
            operationType: .update,
            createdAt: now,
            localVersion: 4,
            idempotencyKey: key
        )

        async let first = harness.syncOperations.enqueue(a)
        async let second = harness.syncOperations.enqueue(b)
        let outcomes = [try await first, try await second]

        let inserted = outcomes.compactMap { outcome -> SyncOperation? in
            if case .inserted(let op) = outcome { return op }
            return nil
        }
        let duplicates = outcomes.compactMap { outcome -> SyncOperation? in
            if case .duplicate(let op) = outcome { return op }
            return nil
        }
        XCTAssertEqual(inserted.count, 1)
        XCTAssertEqual(duplicates.count, 1)
        XCTAssertEqual(duplicates.first?.id, inserted.first?.id)
        let pendingCount = try await harness.syncOperations.countPending(now: now)
        XCTAssertEqual(pendingCount, 1)
    }

    // MARK: - FIFO ordering

    func testPendingFetchIsFIFOByCreatedAtThenId() async throws {
        let harness = try SwiftDataTestHarness()
        let t1 = now
        let t2 = now.addingTimeInterval(10)
        let later = try makeOperation(id: "z-later", entityId: "e-later", createdAt: t2)
        let earlyB = try makeOperation(id: "b-early", entityId: "e-b", createdAt: t1)
        let earlyA = try makeOperation(id: "a-early", entityId: "e-a", createdAt: t1)

        try await harness.syncOperations.enqueue(later)
        try await harness.syncOperations.enqueue(earlyB)
        try await harness.syncOperations.enqueue(earlyA)

        let pending = try await harness.syncOperations.fetchPending(now: t2)
        XCTAssertEqual(
            pending.map(\.id.rawValue),
            ["a-early", "b-early", "z-later"]
        )
    }

    // MARK: - Pending / retry window

    func testFetchPendingExcludesFutureNextRetryAt() async throws {
        let harness = try SwiftDataTestHarness()
        var waiting = try makeOperation(id: "wait", entityId: "e-wait", createdAt: now)
        let ready = try makeOperation(id: "ready", entityId: "e-ready", createdAt: now)
        try await harness.syncOperations.enqueue(waiting)
        try await harness.syncOperations.enqueue(ready)

        waiting.nextRetryAt = now.addingTimeInterval(120)
        waiting.updatedAt = now
        try await harness.syncOperations.update(waiting)

        let pending = try await harness.syncOperations.fetchPending(now: now)
        XCTAssertEqual(pending.map(\.id.rawValue), ["ready"])
        let pendingCount = try await harness.syncOperations.countPending(now: now)
        XCTAssertEqual(pendingCount, 1)
    }

    func testFetchPendingIncludesFailedWhenRetryTimeHasArrived() async throws {
        let harness = try SwiftDataTestHarness()
        let due = try makeOperation(id: "due", entityId: "e-due", createdAt: now)
        let waiting = try makeOperation(id: "not-due", entityId: "e-not", createdAt: now)
        try await harness.syncOperations.enqueue(due)
        try await harness.syncOperations.enqueue(waiting)

        try await fail(
            due,
            through: harness,
            retryCount: 1,
            nextRetryAt: now.addingTimeInterval(-1)
        )
        try await fail(
            waiting,
            through: harness,
            retryCount: 1,
            nextRetryAt: now.addingTimeInterval(60)
        )

        let pending = try await harness.syncOperations.fetchPending(now: now)
        XCTAssertEqual(pending.map(\.id.rawValue), ["due"])

        let failed = try await harness.syncOperations.fetchFailed()
        XCTAssertEqual(Set(failed.map(\.id.rawValue)), ["due", "not-due"])
    }

    func testFailedWithoutNextRetryAtIsNotPending() async throws {
        let harness = try SwiftDataTestHarness()
        let exhausted = try makeOperation(id: "cap", entityId: "e-cap", createdAt: now)
        try await harness.syncOperations.enqueue(exhausted)
        try await fail(exhausted, through: harness, retryCount: 5, nextRetryAt: nil)

        let pending = try await harness.syncOperations.fetchPending(now: now)
        XCTAssertEqual(pending, [])
        let failedIds = try await harness.syncOperations.fetchFailed().map(\.id.rawValue)
        XCTAssertEqual(failedIds, ["cap"])
    }

    // MARK: - Status transitions

    func testValidStatusTransitionsPersist() async throws {
        let harness = try SwiftDataTestHarness()
        let operation = try makeOperation(id: "op-sm", entityId: "e-sm", createdAt: now)
        try await harness.syncOperations.enqueue(operation)

        try await advance(operation, through: harness, to: .inProgress)
        let inProgress = try await harness.syncOperations.fetch(id: operation.id)
        XCTAssertEqual(inProgress.status, .inProgress)

        try await advance(operation, through: harness, to: .succeeded)
        let succeeded = try await harness.syncOperations.fetch(id: operation.id)
        XCTAssertEqual(succeeded.status, .succeeded)
    }

    func testInvalidTransitionIsRejectedAndNotPersisted() async throws {
        let harness = try SwiftDataTestHarness()
        var operation = try makeOperation(id: "op-bad", entityId: "e-bad", createdAt: now)
        try await harness.syncOperations.enqueue(operation)

        operation.status = .succeeded
        operation.updatedAt = now.addingTimeInterval(1)
        await XCTAssertThrowsErrorAsync(
            try await harness.syncOperations.update(operation)
        ) { error in
            XCTAssertEqual(
                error as? DomainError,
                .invalidSyncStatusTransition(from: .pending, to: .succeeded)
            )
        }
        let stillPending = try await harness.syncOperations.fetch(id: operation.id)
        XCTAssertEqual(stillPending.status, .pending)
    }

    func testTerminalStatusCannotTransition() async throws {
        let harness = try SwiftDataTestHarness()
        let operation = try makeOperation(id: "op-term", entityId: "e-term", createdAt: now)
        try await harness.syncOperations.enqueue(operation)
        try await advance(operation, through: harness, to: .failed)

        var stored = try await harness.syncOperations.fetch(id: operation.id)
        stored.status = .pending
        await XCTAssertThrowsErrorAsync(
            try await harness.syncOperations.update(stored)
        ) { error in
            XCTAssertEqual(
                error as? DomainError,
                .invalidSyncStatusTransition(from: .failed, to: .pending)
            )
        }
    }

    func testEnqueueRejectsNonPendingStatus() async throws {
        let harness = try SwiftDataTestHarness()
        var operation = try makeOperation(id: "op-np", entityId: "e-np", createdAt: now)
        operation.status = .inProgress
        await XCTAssertThrowsErrorAsync(
            try await harness.syncOperations.enqueue(operation)
        ) { error in
            XCTAssertEqual(
                error as? DomainError,
                .invalidData(reason: "syncOperation.enqueueRequiresPending")
            )
        }
    }

    // MARK: - Recovery queries

    func testFetchInProgressFailedAndConflicts() async throws {
        let harness = try SwiftDataTestHarness()
        let pending = try makeOperation(id: "p", entityId: "e-p", createdAt: now)
        let progress = try makeOperation(id: "i", entityId: "e-i", createdAt: now)
        let failed = try makeOperation(id: "f", entityId: "e-f", createdAt: now)
        let conflicted = try makeOperation(id: "c", entityId: "e-c", createdAt: now)
        for op in [pending, progress, failed, conflicted] {
            try await harness.syncOperations.enqueue(op)
        }
        try await advance(progress, through: harness, to: .inProgress)
        try await fail(failed, through: harness, retryCount: 1, nextRetryAt: now.addingTimeInterval(30))
        try await advance(conflicted, through: harness, to: .conflict)

        let inProgressIds = try await harness.syncOperations.fetchInProgress().map(\.id.rawValue)
        XCTAssertEqual(inProgressIds, ["i"])
        let failedIds = try await harness.syncOperations.fetchFailed().map(\.id.rawValue)
        XCTAssertEqual(failedIds, ["f"])
        let conflictIds = try await harness.syncOperations.fetchConflicts().map(\.id.rawValue)
        XCTAssertEqual(conflictIds, ["c"])
        let pendingIds = try await harness.syncOperations.fetchPending(now: now).map(\.id.rawValue)
        XCTAssertEqual(pendingIds, ["p"])
    }

    // MARK: - Cleanup

    func testDeleteCompletedRemovesOnlySucceeded() async throws {
        let harness = try SwiftDataTestHarness()
        let pending = try makeOperation(id: "keep-p", entityId: "e-kp", createdAt: now)
        let failed = try makeOperation(id: "keep-f", entityId: "e-kf", createdAt: now)
        let conflicted = try makeOperation(id: "keep-c", entityId: "e-kc", createdAt: now)
        let progress = try makeOperation(id: "keep-i", entityId: "e-ki", createdAt: now)
        let done = try makeOperation(id: "drop", entityId: "e-d", createdAt: now)
        for op in [pending, failed, conflicted, progress, done] {
            try await harness.syncOperations.enqueue(op)
        }
        try await fail(failed, through: harness, retryCount: 1, nextRetryAt: now.addingTimeInterval(10))
        try await advance(conflicted, through: harness, to: .conflict)
        try await advance(progress, through: harness, to: .inProgress)
        try await advance(done, through: harness, to: .succeeded)

        try await harness.syncOperations.deleteCompleted()

        await XCTAssertThrowsErrorAsync(
            try await harness.syncOperations.fetch(id: done.id)
        ) { _ in }

        let keptPending = try await harness.syncOperations.fetch(id: pending.id)
        let keptFailed = try await harness.syncOperations.fetch(id: failed.id)
        let keptConflict = try await harness.syncOperations.fetch(id: conflicted.id)
        let keptProgress = try await harness.syncOperations.fetch(id: progress.id)
        XCTAssertEqual(keptPending.status, .pending)
        XCTAssertEqual(keptFailed.status, .failed)
        XCTAssertEqual(keptConflict.status, .conflict)
        XCTAssertEqual(keptProgress.status, .inProgress)
    }

    func testDeleteFailedAndConflictIndividuallyIsRejected() async throws {
        let harness = try SwiftDataTestHarness()
        let failed = try makeOperation(id: "no-del-f", entityId: "e-ndf", createdAt: now)
        let conflicted = try makeOperation(id: "no-del-c", entityId: "e-ndc", createdAt: now)
        try await harness.syncOperations.enqueue(failed)
        try await harness.syncOperations.enqueue(conflicted)
        try await fail(failed, through: harness, retryCount: 1, nextRetryAt: nil)
        try await advance(conflicted, through: harness, to: .conflict)

        await XCTAssertThrowsErrorAsync(
            try await harness.syncOperations.delete(id: failed.id)
        ) { error in
            XCTAssertEqual(
                error as? DomainError,
                .invalidData(reason: "syncOperation.deleteOnlySucceeded")
            )
        }
        await XCTAssertThrowsErrorAsync(
            try await harness.syncOperations.delete(id: conflicted.id)
        ) { error in
            XCTAssertEqual(
                error as? DomainError,
                .invalidData(reason: "syncOperation.deleteOnlySucceeded")
            )
        }
    }

    // MARK: - Mapping

    func testCorruptStatusRawThrowsInvalidDataOnFetch() async throws {
        let harness = try SwiftDataTestHarness()
        let operation = try makeOperation(id: "corrupt", entityId: "e-cor", createdAt: now)
        try await harness.syncOperations.enqueue(operation)
        try await harness.store.debugOverwriteSyncOperationStatusRaw(
            id: "corrupt",
            statusRaw: "not-a-status"
        )

        await XCTAssertThrowsErrorAsync(
            try await harness.syncOperations.fetch(id: operation.id)
        ) { error in
            XCTAssertEqual(
                error as? DomainError,
                .invalidData(reason: "swiftData.SyncOperation.decodeFailed")
            )
        }
    }

    func testModelMappingDoesNotDefaultUnknownEnums() throws {
        let operation = try makeOperation(id: "map", entityId: "e-map", createdAt: now)
        let model = SyncOperationModel(domain: operation)
        XCTAssertEqual(model.toDomain(), operation)

        model.entityTypeRaw = "syncOperation"
        XCTAssertNil(model.toDomain())
        model.entityTypeRaw = operation.entityType.rawValue

        model.operationTypeRaw = "upsert"
        XCTAssertNil(model.toDomain())
        model.operationTypeRaw = operation.operationType.rawValue

        model.statusRaw = "queued"
        XCTAssertNil(model.toDomain())
    }

    func testOptionalFieldsRoundTripAsNil() async throws {
        let harness = try SwiftDataTestHarness()
        let operation = try makeOperation(
            id: "opts",
            entityId: "e-opts",
            createdAt: now,
            payloadReference: nil
        )
        XCTAssertNil(operation.payloadReference)
        try await harness.syncOperations.enqueue(operation)
        let fetched = try await harness.syncOperations.fetch(id: operation.id)
        XCTAssertNil(fetched.payloadReference)
        XCTAssertNil(fetched.lastAttemptAt)
        XCTAssertNil(fetched.nextRetryAt)
        XCTAssertNil(fetched.errorMessage)
    }

    // MARK: - Helpers

    private func makeOperation(
        id: String,
        entityType: SyncEntityType = .customer,
        entityId: String,
        operationType: SyncOperationType = .create,
        createdAt: Date,
        payloadReference: String? = nil,
        localVersion: Int = 1,
        remoteVersion: Int = 0,
        idempotencyKey: SyncIdempotencyKey? = nil
    ) throws -> SyncOperation {
        try SyncOperation.pending(
            id: SyncOperationID(id),
            entityType: entityType,
            entityId: entityId,
            operationType: operationType,
            payloadReference: payloadReference,
            createdAt: createdAt,
            localVersion: localVersion,
            remoteVersion: remoteVersion,
            idempotencyKey: idempotencyKey
        )
    }

    private func advance(
        _ operation: SyncOperation,
        through harness: SwiftDataTestHarness,
        to status: SyncStatus
    ) async throws {
        var current = try await harness.syncOperations.fetch(id: operation.id)
        let path: [SyncStatus]
        switch (current.status, status) {
        case (.pending, .inProgress):
            path = [.inProgress]
        case (.pending, .succeeded), (.pending, .failed), (.pending, .conflict):
            path = [.inProgress, status]
        case (.inProgress, .succeeded), (.inProgress, .failed), (.inProgress, .conflict):
            path = [status]
        default:
            throw DomainError.invalidData(
                reason: "test.unsupportedTransition.\(current.status.rawValue).\(status.rawValue)"
            )
        }
        for next in path {
            current.status = next
            current.updatedAt = now.addingTimeInterval(1)
            try await harness.syncOperations.update(current)
            current = try await harness.syncOperations.fetch(id: operation.id)
        }
    }

    private func fail(
        _ operation: SyncOperation,
        through harness: SwiftDataTestHarness,
        retryCount: Int,
        nextRetryAt: Date?
    ) async throws {
        try await advance(operation, through: harness, to: .failed)
        var stored = try await harness.syncOperations.fetch(id: operation.id)
        stored.retryCount = retryCount
        stored.lastAttemptAt = now
        stored.nextRetryAt = nextRetryAt
        stored.errorMessage = SyncError.networkUnavailable.localizedDescription
        stored.updatedAt = now
        try await harness.syncOperations.update(stored)
    }
}
