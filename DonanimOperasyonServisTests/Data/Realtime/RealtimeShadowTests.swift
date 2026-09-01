import XCTest
@testable import DonanimOperasyonServis

final class RealtimeShadowTests: XCTestCase {

    func testDebugConfigurationPointsToLocalGateway() {
        let config = RealtimeGatewayConfiguration.default
        #if DEBUG
        XCTAssertTrue(config.isEnabled)
        #if targetEnvironment(simulator)
        XCTAssertEqual(config.webSocketURL?.absoluteString, "ws://127.0.0.1:5088/ws")
        #else
        XCTAssertEqual(
            config.webSocketURL?.absoluteString,
            RealtimeGatewayConfiguration.resolveDevelopmentWebSocketURL()?.absoluteString
        )
        #endif
        #else
        XCTAssertFalse(config.isEnabled)
        XCTAssertNil(config.webSocketURL)
        #endif
        XCTAssertFalse(config.deviceId.isEmpty)
    }

    func testHelloMessageContainsIdTokenWithoutCrashing() throws {
        let data = try RealtimeProtocolCodec.makeHelloEnvelope(
            idToken: "secret-token-value",
            deviceId: "device-1",
            requestId: "req-1"
        )
        let envelope = try RealtimeProtocolCodec.decodeEnvelope(data)
        XCTAssertEqual(envelope.type, .hello)
        XCTAssertEqual(envelope.payloadObject["idToken"] as? String, "secret-token-value")
        XCTAssertEqual(envelope.payloadObject["deviceId"] as? String, "device-1")
        XCTAssertEqual(envelope.v, 1)
    }

    func testAckDecodingAllStatuses() throws {
        for status in ["accepted", "duplicate", "forbidden", "conflict", "invalid", "error"] {
            let isSuccess = status == "accepted" || status == "duplicate"
            var payload: [String: Any] = [
                "operationId": "op-1",
                "idempotencyKey": "key-1",
                "status": status
            ]
            if isSuccess {
                payload["eventId"] = "evt-1"
            } else {
                payload["error"] = ["code": status, "message": "m", "retryable": false]
            }
            let data = try JSONSerialization.data(withJSONObject: [
                "v": 1,
                "type": "op.ack",
                "payload": payload
            ])
            let envelope = try RealtimeProtocolCodec.decodeEnvelope(data)
            let ack = RealtimeProtocolCodec.decodeAck(envelope.payloadObject)
            XCTAssertEqual(ack?.rawStatus, status)
            XCTAssertEqual(ack?.status.rawValue, status)
        }
    }

    func testMalformedEventDoesNotCrash() {
        XCTAssertThrowsError(try RealtimeProtocolCodec.decodeEnvelope(Data("{" .utf8)))
        let empty = try? RealtimeProtocolCodec.decodeEnvelope(
            JSONSerialization.data(withJSONObject: ["v": 1, "type": "event.apply", "payload": [:]])
        )
        XCTAssertNotNil(empty)
        XCTAssertNil(RealtimeProtocolCodec.decodeEvent([:], protocolVersion: 1))
    }

    func testUnknownEventTypeIsForwardCompatible() throws {
        let data = try JSONSerialization.data(withJSONObject: [
            "v": 1,
            "type": "future.event",
            "payload": ["foo": "bar"]
        ])
        let envelope = try RealtimeProtocolCodec.decodeEnvelope(data)
        XCTAssertEqual(envelope.type, .unknown)
        XCTAssertEqual(envelope.rawType, "future.event")
    }

    func testConnectionStateTransitionsOnLoginLogout() async throws {
        let auth = FakeFirebaseAuthService()
        auth.setUID("uid-1", email: "a@b.com")
        let transport = FakeRealtimeWebSocketTransport()
        let config = RealtimeGatewayConfiguration(
            isEnabled: true,
            webSocketURL: URL(string: "ws://127.0.0.1:5088/ws"),
            deviceId: "test-device",
            heartbeatInterval: 60,
            initialReconnectDelay: 0.05,
            maxReconnectDelay: 0.1
        )
        let coordinator = RealtimeCoordinator(
            authService: auth,
            configuration: config,
            transport: transport
        )

        coordinator.handleAuthenticatedSession()
        try await waitUntil(timeout: 2) { coordinator.connectionState == .connected }
        XCTAssertEqual(coordinator.connectionState, .connected)
        XCTAssertEqual(coordinator.telemetry.lastHelloUserId, "uid-test")
        XCTAssertEqual(auth.idTokenForceRefreshRequests.first, true)

        let sent = try await transport.sentEnvelopes()
        XCTAssertTrue(sent.contains(where: { $0.type == .hello }))
        let hello = sent.first(where: { $0.type == .hello })
        XCTAssertEqual(hello?.payloadObject["idToken"] as? String, "fake-id-token.uid-1")

        coordinator.handleSignedOut()
        try await waitUntil(timeout: 2) { coordinator.connectionState == .disconnected }
        XCTAssertEqual(coordinator.connectionState, .disconnected)
    }

    func testAcceptedAndDuplicateAckUpdateTelemetryOnly() async throws {
        let auth = FakeFirebaseAuthService()
        auth.setUID("uid-1")
        let transport = FakeRealtimeWebSocketTransport()
        await transport.setAutoHelloOk(false)
        let config = RealtimeGatewayConfiguration(
            isEnabled: true,
            webSocketURL: URL(string: "ws://127.0.0.1:5088/ws"),
            deviceId: "test-device",
            heartbeatInterval: 60,
            initialReconnectDelay: 1,
            maxReconnectDelay: 1
        )
        let coordinator = RealtimeCoordinator(
            authService: auth,
            configuration: config,
            transport: transport
        )
        coordinator.handleAuthenticatedSession()
        try await Task.sleep(nanoseconds: 50_000_000)
        let helloOk = try JSONSerialization.data(withJSONObject: [
            "v": 1,
            "type": "hello.ok",
            "payload": ["userId": "uid-1", "role": "operator"]
        ])
        await transport.enqueueInbound(helloOk)
        try await waitUntil(timeout: 2) { coordinator.connectionState == .connected }

        let accepted = try JSONSerialization.data(withJSONObject: [
            "v": 1,
            "type": "op.ack",
            "payload": [
                "operationId": "op-a",
                "idempotencyKey": "k",
                "status": "accepted",
                "eventId": "e1"
            ]
        ])
        await transport.enqueueInbound(accepted)
        try await waitUntil(timeout: 2) { coordinator.telemetry.receivedAckCount == 1 }
        XCTAssertEqual(coordinator.telemetry.lastAckStatus, "accepted")

        let duplicate = try JSONSerialization.data(withJSONObject: [
            "v": 1,
            "type": "op.ack",
            "payload": [
                "operationId": "op-b",
                "idempotencyKey": "k",
                "status": "duplicate",
                "eventId": "e1"
            ]
        ])
        await transport.enqueueInbound(duplicate)
        try await waitUntil(timeout: 2) { coordinator.telemetry.receivedAckCount == 2 }
        XCTAssertEqual(coordinator.telemetry.lastAckStatus, "duplicate")
    }

    func testForbiddenConflictInvalidAckDecode() async throws {
        let auth = FakeFirebaseAuthService()
        auth.setUID("uid-1")
        let transport = FakeRealtimeWebSocketTransport()
        let coordinator = RealtimeCoordinator(
            authService: auth,
            configuration: RealtimeGatewayConfiguration(
                isEnabled: true,
                webSocketURL: URL(string: "ws://127.0.0.1:5088/ws"),
                deviceId: "d",
                heartbeatInterval: 60,
                initialReconnectDelay: 1,
                maxReconnectDelay: 1
            ),
            transport: transport
        )
        coordinator.handleAuthenticatedSession()
        try await waitUntil(timeout: 2) { coordinator.connectionState == .connected }

        for status in ["forbidden", "conflict", "invalid"] {
            let data = try JSONSerialization.data(withJSONObject: [
                "v": 1,
                "type": "op.ack",
                "payload": [
                    "operationId": "op-\(status)",
                    "idempotencyKey": "k-\(status)",
                    "status": status,
                    "error": ["code": status, "message": status, "retryable": false]
                ]
            ])
            await transport.enqueueInbound(data)
            try await waitUntil(timeout: 2) {
                coordinator.telemetry.lastAckStatus == status
            }
        }
    }

    func testTokenRefreshPathForcesNewIdToken() async throws {
        let auth = FakeFirebaseAuthService()
        auth.setUID("uid-1")
        let transport = FakeRealtimeWebSocketTransport()
        await transport.setAutoHelloOk(false)
        let coordinator = RealtimeCoordinator(
            authService: auth,
            configuration: RealtimeGatewayConfiguration(
                isEnabled: true,
                webSocketURL: URL(string: "ws://127.0.0.1:5088/ws"),
                deviceId: "d",
                heartbeatInterval: 60,
                initialReconnectDelay: 0.05,
                maxReconnectDelay: 0.1
            ),
            transport: transport
        )
        coordinator.handleAuthenticatedSession()
        try await Task.sleep(nanoseconds: 50_000_000)
        let helloOk = try JSONSerialization.data(withJSONObject: [
            "v": 1,
            "type": "hello.ok",
            "payload": ["userId": "uid-1", "role": "operator"]
        ])
        await transport.enqueueInbound(helloOk)
        try await waitUntil(timeout: 2) { coordinator.connectionState == .connected }

        let unauthorized = try JSONSerialization.data(withJSONObject: [
            "v": 1,
            "type": "error",
            "payload": ["code": "unauthorized", "message": "token expired", "retryable": true]
        ])
        await transport.enqueueInbound(unauthorized)
        try await waitUntil(timeout: 2) { auth.idTokenForceRefreshCallCount >= 1 }
        XCTAssertGreaterThanOrEqual(auth.idTokenForceRefreshCallCount, 1)
    }

    func testReconnectAfterTransportDropDoesNotForceRefreshInitialTokenAgain() async throws {
        let auth = FakeFirebaseAuthService()
        auth.setUID("uid-1")
        let transport = FakeRealtimeWebSocketTransport()
        let config = RealtimeGatewayConfiguration(
            isEnabled: true,
            webSocketURL: URL(string: "ws://127.0.0.1:5088/ws"),
            deviceId: "test-device",
            heartbeatInterval: 60,
            initialReconnectDelay: 0.05,
            maxReconnectDelay: 0.1
        )
        let coordinator = RealtimeCoordinator(
            authService: auth,
            configuration: config,
            transport: transport
        )
        coordinator.handleAuthenticatedSession()
        try await waitUntil(timeout: 2) { coordinator.connectionState == .connected }

        await transport.simulateDrop()
        try await waitUntil(timeout: 3) { coordinator.connectionState == .connected }

        XCTAssertTrue(auth.idTokenForceRefreshRequests.contains(true))
        XCTAssertTrue(auth.idTokenForceRefreshRequests.dropFirst().allSatisfy { !$0 })
    }

    func testReconnectAfterTransportDrop() async throws {
        let auth = FakeFirebaseAuthService()
        auth.setUID("uid-1")
        let transport = FakeRealtimeWebSocketTransport()
        let config = RealtimeGatewayConfiguration(
            isEnabled: true,
            webSocketURL: URL(string: "ws://127.0.0.1:5088/ws"),
            deviceId: "test-device",
            heartbeatInterval: 60,
            initialReconnectDelay: 0.05,
            maxReconnectDelay: 0.1
        )
        let coordinator = RealtimeCoordinator(
            authService: auth,
            configuration: config,
            transport: transport
        )
        coordinator.handleAuthenticatedSession()
        try await waitUntil(timeout: 2) { coordinator.connectionState == .connected }

        await transport.simulateDrop()
        try await waitUntil(timeout: 2) {
            coordinator.connectionState == .reconnecting || coordinator.connectionState == .connected
        }
        try await waitUntil(timeout: 3) { coordinator.connectionState == .connected }
        XCTAssertEqual(coordinator.connectionState, .connected)
    }

    func testUnknownEventPayloadIncrementsTelemetryWithoutCrash() async throws {
        let auth = FakeFirebaseAuthService()
        auth.setUID("uid-1")
        let transport = FakeRealtimeWebSocketTransport()
        let coordinator = RealtimeCoordinator(
            authService: auth,
            configuration: RealtimeGatewayConfiguration(
                isEnabled: true,
                webSocketURL: URL(string: "ws://127.0.0.1:5088/ws"),
                deviceId: "d",
                heartbeatInterval: 60,
                initialReconnectDelay: 1,
                maxReconnectDelay: 1
            ),
            transport: transport
        )
        coordinator.handleAuthenticatedSession()
        try await waitUntil(timeout: 2) { coordinator.connectionState == .connected }

        let event = try JSONSerialization.data(withJSONObject: [
            "v": 1,
            "type": "event.apply",
            "payload": [
                "eventId": "evt-unknown-type",
                "operationId": "op-1",
                "eventType": "future.thing",
                "entityType": "customer",
                "entityId": "c1",
                "actorUserId": "uid-1",
                "idempotencyKey": "k1",
                "extraFutureField": true,
                "payload": ["x": 1]
            ]
        ])
        await transport.enqueueInbound(event)
        try await waitUntil(timeout: 2) { coordinator.telemetry.receivedEventCount == 1 }
        XCTAssertEqual(coordinator.telemetry.lastEventId, "evt-unknown-type")
        XCTAssertEqual(coordinator.telemetry.lastEventEntityType, "customer")
    }

    func testShadowSmokeSequenceAcceptedThenDuplicate() async throws {
        let auth = FakeFirebaseAuthService()
        auth.setUID("uid-1")
        let transport = FakeRealtimeWebSocketTransport()
        await transport.setAutoAcceptOps(true)
        let coordinator = RealtimeCoordinator(
            authService: auth,
            configuration: RealtimeGatewayConfiguration(
                isEnabled: true,
                webSocketURL: URL(string: "ws://127.0.0.1:5088/ws"),
                deviceId: "smoke-device",
                heartbeatInterval: 60,
                initialReconnectDelay: 1,
                maxReconnectDelay: 1
            ),
            transport: transport
        )
        coordinator.handleAuthenticatedSession()
        try await waitUntil(timeout: 2) { coordinator.connectionState == .connected }

        let report = await coordinator.runShadowSmokeSequence()
        XCTAssertTrue(report.succeeded, report.detail)
        XCTAssertEqual(report.customerAck, "accepted")
        XCTAssertEqual(report.workOrderAck, "accepted")
        XCTAssertEqual(report.duplicateAck, "duplicate")
        XCTAssertEqual(coordinator.telemetry.receivedAckCount, 3)
    }

    func testTechnicianShadowSmokeSequenceUsesWorkOrderProbeOnly() async throws {
        let auth = FakeFirebaseAuthService()
        auth.setUID("uid-tech-1")
        let transport = FakeRealtimeWebSocketTransport()
        await transport.setAutoAcceptOps(true)
        await transport.setAutoHelloOk(false)
        let coordinator = RealtimeCoordinator(
            authService: auth,
            configuration: RealtimeGatewayConfiguration(
                isEnabled: true,
                webSocketURL: URL(string: "ws://127.0.0.1:5088/ws"),
                deviceId: "smoke-device",
                heartbeatInterval: 60,
                initialReconnectDelay: 1,
                maxReconnectDelay: 1
            ),
            transport: transport
        )
        coordinator.handleAuthenticatedSession()
        try await Task.sleep(nanoseconds: 50_000_000)
        let helloOk = try JSONSerialization.data(withJSONObject: [
            "v": 1,
            "type": "hello.ok",
            "payload": ["userId": "uid-tech-1", "role": "technician"]
        ])
        await transport.enqueueInbound(helloOk)
        try await waitUntil(timeout: 2) { coordinator.connectionState == .connected }

        let report = await coordinator.runShadowSmokeSequence()
        XCTAssertTrue(report.succeeded, report.detail)
        XCTAssertEqual(report.customerAck, "accepted")
        XCTAssertEqual(report.workOrderAck, "accepted")
        XCTAssertEqual(report.duplicateAck, "duplicate")
        XCTAssertTrue(report.customerEntityId?.hasPrefix("shadow-probe-smoke-") == true)
    }

    func testTechnicianShadowProbeAwaitAck() async throws {
        let auth = FakeFirebaseAuthService()
        auth.setUID("uid-tech-1")
        let transport = FakeRealtimeWebSocketTransport()
        await transport.setAutoAcceptOps(true)
        await transport.setAutoHelloOk(false)
        let coordinator = RealtimeCoordinator(
            authService: auth,
            configuration: RealtimeGatewayConfiguration(
                isEnabled: true,
                webSocketURL: URL(string: "ws://127.0.0.1:5088/ws"),
                deviceId: "probe-device",
                heartbeatInterval: 60,
                initialReconnectDelay: 1,
                maxReconnectDelay: 1
            ),
            transport: transport
        )
        coordinator.handleAuthenticatedSession()
        try await Task.sleep(nanoseconds: 50_000_000)
        let helloOk = try JSONSerialization.data(withJSONObject: [
            "v": 1,
            "type": "hello.ok",
            "payload": ["userId": "uid-tech-1", "role": "technician"]
        ])
        await transport.enqueueInbound(helloOk)
        try await waitUntil(timeout: 2) { coordinator.connectionState == .connected }

        await coordinator.sendShadowProbe()
        try await waitUntil(timeout: 2) { coordinator.telemetry.lastAckStatus == "accepted" }
        XCTAssertEqual(coordinator.telemetry.lastAckStatus, "accepted")
    }

    private func waitUntil(
        timeout: TimeInterval,
        file: StaticString = #filePath,
        line: UInt = #line,
        predicate: @escaping @MainActor () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let ok = await MainActor.run { predicate() }
            if ok { return }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTFail("Condition not met before timeout", file: file, line: line)
    }
}
