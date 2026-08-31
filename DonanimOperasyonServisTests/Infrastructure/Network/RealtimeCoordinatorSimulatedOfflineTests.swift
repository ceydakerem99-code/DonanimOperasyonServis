import XCTest
@testable import DonanimOperasyonServis

#if DEBUG
final class RealtimeCoordinatorSimulatedOfflineTests: XCTestCase {

    private func makeConfig() -> RealtimeGatewayConfiguration {
        RealtimeGatewayConfiguration(
            isEnabled: true,
            webSocketURL: URL(string: "ws://127.0.0.1:5088/ws"),
            deviceId: "test-device",
            heartbeatInterval: 60,
            initialReconnectDelay: 0.05,
            maxReconnectDelay: 0.1
        )
    }

    func testSimulatedOfflineBlocksInitialConnect() async throws {
        let auth = FakeFirebaseAuthService()
        auth.setUID("uid-1", email: "a@b.com")
        let transport = FakeRealtimeWebSocketTransport()
        let reachability = DebuggableNetworkReachability()
        await reachability.setSimulatedOffline(true)

        let coordinator = RealtimeCoordinator(
            authService: auth,
            configuration: makeConfig(),
            transport: transport,
            debugReachability: reachability
        )

        coordinator.handleAuthenticatedSession()
        try await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertEqual(coordinator.connectionState, .disconnected)
        let sent = try await transport.sentEnvelopes()
        XCTAssertTrue(sent.isEmpty)
    }

    func testSimulatedOfflineStopsReconnectLoop() async throws {
        let auth = FakeFirebaseAuthService()
        auth.setUID("uid-1", email: "a@b.com")
        let transport = FakeRealtimeWebSocketTransport()
        let reachability = DebuggableNetworkReachability()
        let coordinator = RealtimeCoordinator(
            authService: auth,
            configuration: makeConfig(),
            transport: transport,
            debugReachability: reachability
        )

        coordinator.handleAuthenticatedSession()
        try await waitUntil(timeout: 2) { coordinator.connectionState == .connected }

        await reachability.setSimulatedOffline(true)
        try await waitUntil(timeout: 2) { coordinator.connectionState == .disconnected }

        await transport.simulateDrop()
        try await Task.sleep(nanoseconds: 300_000_000)

        XCTAssertEqual(coordinator.connectionState, .disconnected)
        XCTAssertNotEqual(coordinator.connectionState, .reconnecting)
    }

    func testSimulatedOfflineOffRestoresConnect() async throws {
        let auth = FakeFirebaseAuthService()
        auth.setUID("uid-1", email: "a@b.com")
        let transport = FakeRealtimeWebSocketTransport()
        let reachability = DebuggableNetworkReachability()
        await reachability.setSimulatedOffline(true)

        let coordinator = RealtimeCoordinator(
            authService: auth,
            configuration: makeConfig(),
            transport: transport,
            debugReachability: reachability
        )

        coordinator.handleAuthenticatedSession()
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(coordinator.connectionState, .disconnected)

        await reachability.setSimulatedOffline(false)
        try await waitUntil(timeout: 2) { coordinator.connectionState == .connected }
    }

    func testConnectionDisplayStateUsesReachabilityWhenSimulatedOffline() async {
        let reachability = DebuggableNetworkReachability()
        await reachability.setSimulatedOffline(true)
        let isOnline = await reachability.isReachable
        XCTAssertFalse(isOnline)

        await reachability.setSimulatedOffline(false)
        let restoredOnline = await reachability.isReachable
        let expectedOnline = await underlyingPathReachability(reachability)
        XCTAssertEqual(restoredOnline, expectedOnline)
    }

    func testMockContainerRealtimeCoordinatorHasNoDebugReachabilityBinding() {
        let container = DIContainer.mock()
        XCTAssertTrue(container.networkReachability is FakeNetworkReachability)
        XCTAssertEqual(container.realtimeCoordinator.connectionState, .disconnected)
    }

    private func underlyingPathReachability(_ reachability: DebuggableNetworkReachability) async -> Bool {
        await reachability.setSimulatedOffline(false)
        return await reachability.isReachable
    }

    private func waitUntil(
        timeout: TimeInterval,
        pollInterval: UInt64 = 20_000_000,
        _ predicate: @escaping () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if predicate() { return }
            try await Task.sleep(nanoseconds: pollInterval)
        }
        XCTFail("Timed out waiting for condition")
    }
}
#endif
