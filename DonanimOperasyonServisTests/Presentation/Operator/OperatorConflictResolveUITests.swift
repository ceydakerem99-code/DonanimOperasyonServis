import XCTest
@testable import DonanimOperasyonServis

@MainActor
final class OperatorConflictResolveUITests: XCTestCase {

    private var container: DIContainer!
    private var deps: OperatorDependencies!
    private var operatorUser: User!
    private let now = DomainFixtures.referenceDate

    override func setUp() async throws {
        container = DIContainer.mock()
        deps = container.makeOperatorDependencies()
        operatorUser = DomainFixtures.operatorUser()
        try await deps.userRepository.save(operatorUser)
    }

    func testConflictListLoadsUnresolvedRows() async throws {
        let conflict = try await seedCustomerConflict()
        let vm = OperatorConflictListViewModel(actor: operatorUser, dependencies: deps)
        await vm.load()

        XCTAssertEqual(vm.phase, .loaded)
        XCTAssertEqual(vm.rows.count, 1)
        XCTAssertEqual(vm.rows.first?.id, conflict.id)
        XCTAssertEqual(vm.rows.first?.entityId, "cust-1")
    }

    func testConflictListEmptyWhenNoConflicts() async throws {
        let vm = OperatorConflictListViewModel(actor: operatorUser, dependencies: deps)
        await vm.load()
        XCTAssertEqual(vm.phase, .empty)
        XCTAssertTrue(vm.rows.isEmpty)
    }

    func testConflictListUnauthorizedRoleShowsError() async throws {
        let tech = DomainFixtures.technicianUser()
        try await deps.userRepository.save(tech)
        let vm = OperatorConflictListViewModel(actor: tech, dependencies: deps)
        await vm.load()
        if case .error = vm.phase {
            // expected
        } else {
            XCTFail("Technician must not load conflict inbox")
        }
    }

    func testDetailResolveUsingLocalUpdatesUIState() async throws {
        let conflict = try await seedCustomerConflict(advanceLinkedToConflict: true)
        let vm = OperatorConflictDetailViewModel(
            conflictId: conflict.id,
            actor: operatorUser,
            dependencies: deps
        )
        await vm.load()
        XCTAssertEqual(vm.phase, .loaded)
        XCTAssertTrue(vm.canResolve)

        await vm.resolveUsingLocal()

        if case .resolved(let label) = vm.phase {
            XCTAssertEqual(label, ConflictResolutionDecision.useLocal.displayName)
        } else {
            XCTFail("Expected resolved phase, got \(vm.phase)")
        }
        XCTAssertEqual(vm.conflict?.resolution, .useLocal)
        XCTAssertFalse(vm.canResolve)

        let listed = try await deps.syncConflictRepository.listUnresolved()
        XCTAssertFalse(listed.contains { $0.id == conflict.id })

        let local = try await deps.customerRepository.fetch(id: CustomerID("cust-1"))
        XCTAssertEqual(local.name, "Yerel")
    }

    func testDetailResolveUsingRemoteAppliesRemoteEntity() async throws {
        let conflict = try await seedCustomerConflict()
        let vm = OperatorConflictDetailViewModel(
            conflictId: conflict.id,
            actor: operatorUser,
            dependencies: deps
        )
        await vm.load()
        await vm.resolveUsingRemote()

        if case .resolved = vm.phase {
            // expected
        } else {
            XCTFail("Expected resolved phase, got \(vm.phase)")
        }
        XCTAssertEqual(vm.conflict?.resolution, .useRemote)
        let local = try await deps.customerRepository.fetch(id: CustomerID("cust-1"))
        XCTAssertEqual(local.name, "Sunucu")
    }

    func testDetailMissingConflictShowsError() async throws {
        let vm = OperatorConflictDetailViewModel(
            conflictId: SyncConflictID("missing-cf"),
            actor: operatorUser,
            dependencies: deps
        )
        await vm.load()
        if case .error = vm.phase {
            // expected
        } else {
            XCTFail("Missing conflict must surface error")
        }
    }

    func testListRemovesResolvedConflictAfterReload() async throws {
        let conflict = try await seedCustomerConflict()
        let listVM = OperatorConflictListViewModel(actor: operatorUser, dependencies: deps)
        await listVM.load()
        XCTAssertEqual(listVM.rows.count, 1)

        let detailVM = OperatorConflictDetailViewModel(
            conflictId: conflict.id,
            actor: operatorUser,
            dependencies: deps
        )
        await detailVM.load()
        await detailVM.resolveUsingRemote()

        await listVM.load()
        XCTAssertEqual(listVM.phase, .empty)
        XCTAssertTrue(listVM.rows.isEmpty)
    }

    // MARK: - Helpers

    @discardableResult
    private func seedCustomerConflict(
        advanceLinkedToConflict: Bool = false
    ) async throws -> SyncConflict {
        let local = DomainFixtures.customer(name: "Yerel")
        var remote = DomainFixtures.customer(name: "Sunucu")
        remote.updatedAt = now.addingTimeInterval(60)
        try await deps.customerRepository.save(local)
        try await container.remoteCustomerRepository.save(remote)

        var operation = try SyncOperation.pending(
            id: SyncOperationID("op-cust-ui-1"),
            entityType: .customer,
            entityId: local.id.rawValue,
            operationType: .update,
            createdAt: now,
            localVersion: 2,
            remoteVersion: 1
        )
        _ = try await deps.syncOperationRepository.enqueue(operation)
        if advanceLinkedToConflict {
            operation.status = .inProgress
            operation.updatedAt = now
            try await deps.syncOperationRepository.update(operation)
            operation.status = .conflict
            operation.updatedAt = now.addingTimeInterval(1)
            try await deps.syncOperationRepository.update(operation)
        }

        let conflict = SyncConflict.unresolved(
            id: SyncConflictID("cf-ui-1"),
            syncOperationId: operation.id,
            entityType: .customer,
            entityId: local.id.rawValue,
            localVersion: 2,
            remoteVersion: 4,
            localReference: "local/cust-1",
            remoteReference: "remote/cust-1",
            detectedAt: now
        )
        try await deps.syncConflictRepository.save(conflict)
        return conflict
    }
}
