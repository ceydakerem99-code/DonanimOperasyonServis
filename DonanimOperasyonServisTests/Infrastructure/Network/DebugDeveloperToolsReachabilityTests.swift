import XCTest
@testable import DonanimOperasyonServis

#if DEBUG
final class DebugDeveloperToolsReachabilityTests: XCTestCase {

    func testSimulatedOfflineForcesUnreachable() async {
        let reachability = DebuggableNetworkReachability()
        _ = await reachability.isReachable

        await reachability.setSimulatedOffline(true)
        let offlineReachable = await reachability.isReachable
        XCTAssertFalse(offlineReachable)

        await reachability.setSimulatedOffline(false)
        let restoredReachable = await reachability.isReachable
        let expectedReachable = await underlyingPathReachability(reachability)
        XCTAssertEqual(restoredReachable, expectedReachable)
    }

    func testSimulatedOfflineToggleIsIdempotent() async {
        let reachability = DebuggableNetworkReachability()
        _ = await reachability.isReachable

        await reachability.setSimulatedOffline(true)
        await reachability.setSimulatedOffline(true)
        let offlineReachable = await reachability.isReachable
        let simulationOn = await reachability.isSimulationOffline
        XCTAssertFalse(offlineReachable)
        XCTAssertTrue(simulationOn)

        await reachability.setSimulatedOffline(false)
        await reachability.setSimulatedOffline(false)
        let simulationOff = await reachability.isSimulationOffline
        XCTAssertFalse(simulationOff)
    }

    func testReachabilityUpdatesReflectSimulatedOffline() async {
        let reachability = DebuggableNetworkReachability()
        let stream = await reachability.reachabilityUpdates()
        var iterator = stream.makeAsyncIterator()
        _ = await iterator.next()

        await reachability.setSimulatedOffline(true)
        let offlineValue = await iterator.next()
        XCTAssertEqual(offlineValue, false)

        await reachability.setSimulatedOffline(false)
        let restoredValue = await iterator.next()
        let simulationOff = await reachability.isSimulationOffline
        let reachableAfterOff = await reachability.isReachable
        let expectedReachable = await underlyingPathReachability(reachability)
        XCTAssertFalse(simulationOff)
        XCTAssertNotNil(restoredValue)
        XCTAssertEqual(reachableAfterOff, expectedReachable)
    }

    func testLiveDebugWrapperUsesRealReachabilityInitially() async {
        let monitor = PathMonitorNetworkReachability()
        monitor.start()
        let reachability = DebuggableNetworkReachability(pathMonitor: monitor)

        let wrappedReachable = await reachability.isReachable
        let monitorReachable = await monitor.isReachable
        XCTAssertEqual(wrappedReachable, monitorReachable)
    }

    func testMockContainerStillUsesFakeReachability() {
        let container = DIContainer.mock()
        XCTAssertTrue(container.networkReachability is FakeNetworkReachability)
        XCTAssertFalse(container.networkReachability is DebuggableNetworkReachability)
    }

    /// Release `makeLiveReachability()` stays PathMonitor-only (`DIContainer.swift` `#else`).
    func testDebugLiveReachabilityImplementsSimulationControl() async {
        let reachability: any DebugNetworkReachabilityControlling = DebuggableNetworkReachability()
        await reachability.setSimulatedOffline(true)
        let reachable = await reachability.isReachable
        XCTAssertFalse(reachable)
    }

    func testSimulationOfflineStatePersistsAcrossReads() async {
        let reachability = DebuggableNetworkReachability()

        await reachability.setSimulatedOffline(true)
        let simulationOffline = await reachability.isSimulationOffline
        let reachableWhileOffline = await reachability.isReachable
        XCTAssertTrue(simulationOffline)
        XCTAssertFalse(reachableWhileOffline)

        // Same instance, no write — simulates reopening DebugDeveloperToolsView.
        let persistedSimulation = await reachability.isSimulationOffline
        let persistedReachable = await reachability.isReachable
        XCTAssertTrue(persistedSimulation)
        XCTAssertFalse(persistedReachable)
    }

    func testSimulationStateSurvivesViewLifecyclePattern() async {
        let sharedReachability = DebuggableNetworkReachability()

        await sharedReachability.setSimulatedOffline(true)
        let reachableAfterToggle = await sharedReachability.isReachable
        XCTAssertFalse(reachableAfterToggle)

        let toggleStateOnReopen = await sharedReachability.isSimulationOffline
        let reachableOnReopen = await sharedReachability.isReachable
        XCTAssertTrue(toggleStateOnReopen)
        XCTAssertFalse(reachableOnReopen)

        await sharedReachability.setSimulatedOffline(false)
        let expectedReachable = await underlyingPathReachability(sharedReachability)
        let restoredReachable = await sharedReachability.isReachable
        let simulationAfterOff = await sharedReachability.isSimulationOffline
        XCTAssertEqual(restoredReachable, expectedReachable)
        XCTAssertFalse(simulationAfterOff)
    }

    func testSharedReachabilityInstanceRetainsSimulationAcrossProtocolAccess() async {
        let reachability: any DebugNetworkReachabilityControlling = DebuggableNetworkReachability()
        await reachability.setSimulatedOffline(true)

        let reopenedAccess: any DebugNetworkReachabilityControlling = reachability
        let simulationOffline = await reopenedAccess.isSimulationOffline
        let reachable = await reopenedAccess.isReachable
        XCTAssertTrue(simulationOffline)
        XCTAssertFalse(reachable)
    }

    func testDIContainerNetworkReachabilityIsStableInstance() async {
        let reachability = DebuggableNetworkReachability()
        await reachability.setSimulatedOffline(true)

        let firstAccess = reachability
        let secondAccess = reachability
        let firstSimulation = await firstAccess.isSimulationOffline
        let secondSimulation = await secondAccess.isSimulationOffline
        XCTAssertTrue(firstAccess === secondAccess)
        XCTAssertTrue(firstSimulation)
        XCTAssertTrue(secondSimulation)
    }

    func testDebugSimulatedOfflineToOnlineTriggersExplicitSyncDrain() async throws {
        let local = try SwiftDataTestHarness()
        let probe = SyncRemoteProbe()
        let remote = SyncManagerTestFactory.remoteBundle(probe: probe)
        let reachability = DebuggableNetworkReachability()
        await reachability.setSimulatedOffline(true)

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
            reachability: reachability
        )
        let coordinator = SyncLifecycleCoordinator(
            syncManager: manager,
            recovery: LocalSyncRecoveryHandler(queue: local.syncOperations),
            reachability: reachability,
            scheduler: FakeBackgroundSyncScheduler()
        )

        let customer = DomainFixtures.customer()
        try await local.customers.save(customer)
        let operation = try SyncOperation.pending(
            id: SyncOperationID("op-debug-offline-online"),
            entityType: .customer,
            entityId: customer.id.rawValue,
            operationType: .create,
            createdAt: DomainFixtures.referenceDate,
            localVersion: 1
        )
        _ = try await local.syncOperations.enqueue(operation)

        await reachability.setSimulatedOffline(false)
        await coordinator.handleNetworkBecameReachable()

        await XCTAssertThrowsErrorAsync(try await local.syncOperations.fetch(id: operation.id))
        let writes = await probe.recordedWrites()
        XCTAssertEqual(writes, [.save(.customer, customer.id.rawValue)])
    }

    private func underlyingPathReachability(_ reachability: DebuggableNetworkReachability) async -> Bool {
        await reachability.setSimulatedOffline(false)
        return await reachability.isReachable
    }
}
#endif
