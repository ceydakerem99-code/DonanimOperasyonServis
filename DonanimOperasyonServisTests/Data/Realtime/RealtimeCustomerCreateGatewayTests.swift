import XCTest
@testable import DonanimOperasyonServis

final class RealtimeCustomerCreateGatewayTests: XCTestCase {

    func testIdempotencyKeyMatchesFaz0Contract() {
        let key = RealtimeProtocolCodec.makeIdempotencyKey(
            actorUserId: "uid-1",
            entityType: "customer",
            entityId: "cust-1",
            operationType: "create",
            localVersion: 1
        )
        XCTAssertEqual(key, "uid-1:customer:cust-1:create:1")
    }

    func testCustomerOpSubmitEncodesSnapshotWithoutShadowFlag() throws {
        let customer = DomainFixtures.customer(id: CustomerID("cust-snap"), name: "Acme")
        let data = try RealtimeProtocolCodec.makeOpSubmit(
            operationId: "op-1",
            idempotencyKey: "uid-1:customer:cust-snap:create:1",
            entityType: "customer",
            entityId: "cust-snap",
            operationType: "create",
            actorUserId: "uid-1",
            deviceId: "device-1",
            payload: RealtimeProtocolCodec.customerSnapshot(customer)
        )
        let envelope = try RealtimeProtocolCodec.decodeEnvelope(data)
        XCTAssertEqual(envelope.type, .opSubmit)
        XCTAssertEqual(envelope.payloadObject["idempotencyKey"] as? String, "uid-1:customer:cust-snap:create:1")
        let nested = envelope.payloadObject["payload"] as? [String: Any]
        XCTAssertEqual(nested?["id"] as? String, "cust-snap")
        XCTAssertEqual(nested?["name"] as? String, "Acme")
        XCTAssertNil(nested?["shadow"])
    }

    func testCreateWithSyncStillEnqueuesSyncQueueWhenGatewayDisconnected() async throws {
        let container = DIContainer.mock()
        let deps = container.makeOperatorDependencies()
        let operatorUser = DomainFixtures.operatorUser()
        try await deps.userRepository.save(operatorUser)

        let created = try await deps.customerService.createWithSync(
            actor: operatorUser,
            name: "Gateway Kapalı Firma",
            address: "Cadde 1"
        )
        let ops = try await deps.syncOperationRepository.list(
            entityType: .customer,
            entityId: created.id.rawValue
        )
        XCTAssertTrue(ops.contains { $0.operationType == .create && $0.status == .pending })
        XCTAssertEqual(container.realtimeCoordinator.connectionState, .disconnected)
    }

    func testConnectedCreateSubmitsAndWaitsForAcceptedAck() async throws {
        let auth = FakeFirebaseAuthService()
        auth.setUID("uid-1")
        let transport = FakeRealtimeWebSocketTransport()
        await transport.setAutoAcceptOps(true)
        let coordinator = RealtimeCoordinator(
            authService: auth,
            configuration: RealtimeGatewayConfiguration(
                isEnabled: true,
                webSocketURL: URL(string: "ws://127.0.0.1:5088/ws"),
                deviceId: "test-device",
                heartbeatInterval: 60,
                initialReconnectDelay: 1,
                maxReconnectDelay: 1
            ),
            transport: transport
        )
        coordinator.handleAuthenticatedSession()
        try await waitUntil(timeout: 2) { coordinator.connectionState == .connected }

        let container = DIContainer.mock()
        let operatorUser = DomainFixtures.operatorUser(id: UserID("uid-1"))
        try await container.userRepository.save(operatorUser)
        let service = OperatorCustomerService(
            createCustomer: CreateCustomerUseCase(customerRepository: container.customerRepository),
            updateCustomer: UpdateCustomerUseCase(customerRepository: container.customerRepository),
            syncOperationRepository: container.syncOperationRepository,
            realtimeCustomerCreate: coordinator
        )
        let created = try await service.createWithSync(
            actor: operatorUser,
            name: "Gateway Firma",
            address: "Adres 2"
        )

        let ops = try await container.syncOperationRepository.list(
            entityType: .customer,
            entityId: created.id.rawValue
        )
        XCTAssertTrue(ops.contains { $0.operationType == .create && $0.status == .pending })

        let sent = try await transport.sentEnvelopes()
        let submit = sent.first { $0.type == .opSubmit }
        XCTAssertNotNil(submit)
        XCTAssertEqual(submit?.payloadObject["entityType"] as? String, "customer")
        XCTAssertEqual(submit?.payloadObject["entityId"] as? String, created.id.rawValue)
        XCTAssertEqual(
            submit?.payloadObject["idempotencyKey"] as? String,
            "uid-1:customer:\(created.id.rawValue):create:1"
        )
        let nested = submit?.payloadObject["payload"] as? [String: Any]
        XCTAssertEqual(nested?["name"] as? String, "Gateway Firma")
        XCTAssertEqual(coordinator.telemetry.lastCustomerCreateAckStatus, "accepted")
        XCTAssertEqual(coordinator.telemetry.receivedAckCount, 1)
    }

    func testDuplicateCustomerCreateAckIsSuccess() async throws {
        let auth = FakeFirebaseAuthService()
        auth.setUID("uid-1")
        let transport = FakeRealtimeWebSocketTransport()
        await transport.setAutoAcceptOps(true)
        let coordinator = RealtimeCoordinator(
            authService: auth,
            configuration: RealtimeGatewayConfiguration(
                isEnabled: true,
                webSocketURL: URL(string: "ws://127.0.0.1:5088/ws"),
                deviceId: "test-device",
                heartbeatInterval: 60,
                initialReconnectDelay: 1,
                maxReconnectDelay: 1
            ),
            transport: transport
        )
        coordinator.handleAuthenticatedSession()
        try await waitUntil(timeout: 2) { coordinator.connectionState == .connected }

        let customer = DomainFixtures.customer(id: CustomerID("cust-dup"), name: "Dup")
        let first = await coordinator.submitCustomerCreate(customer, actorUserId: "uid-1")
        let second = await coordinator.submitCustomerCreate(customer, actorUserId: "uid-1")
        guard case .accepted = first else {
            return XCTFail("expected accepted, got \(first)")
        }
        guard case .duplicate = second else {
            return XCTFail("expected duplicate, got \(second)")
        }
        XCTAssertTrue(first.isAcknowledgedSuccess)
        XCTAssertTrue(second.isAcknowledgedSuccess)
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
