import XCTest
@testable import DonanimOperasyonServis

final class RealtimeWorkOrderCreateGatewayTests: XCTestCase {

    func testIdempotencyKeyMatchesFaz0Contract() {
        let key = RealtimeProtocolCodec.makeIdempotencyKey(
            actorUserId: "uid-1",
            entityType: "workOrder",
            entityId: "wo-1",
            operationType: "create",
            localVersion: 1
        )
        XCTAssertEqual(key, "uid-1:workOrder:wo-1:create:1")
    }

    func testWorkOrderOpSubmitEncodesSnapshotWithoutShadowFlag() throws {
        let workOrder = DomainFixtures.workOrder(id: WorkOrderID("wo-snap"), workOrderNumber: "WO-9001")
        let data = try RealtimeProtocolCodec.makeOpSubmit(
            operationId: "op-1",
            idempotencyKey: "uid-1:workOrder:wo-snap:create:1",
            entityType: "workOrder",
            entityId: "wo-snap",
            operationType: "create",
            actorUserId: "uid-1",
            deviceId: "device-1",
            payload: RealtimeProtocolCodec.workOrderSnapshot(workOrder)
        )
        let envelope = try RealtimeProtocolCodec.decodeEnvelope(data)
        XCTAssertEqual(envelope.type, .opSubmit)
        XCTAssertEqual(envelope.payloadObject["idempotencyKey"] as? String, "uid-1:workOrder:wo-snap:create:1")
        let nested = envelope.payloadObject["payload"] as? [String: Any]
        XCTAssertEqual(nested?["id"] as? String, "wo-snap")
        XCTAssertEqual(nested?["workOrderNumber"] as? String, "WO-9001")
        XCTAssertNil(nested?["shadow"])
    }

    func testCreateWithSyncStillEnqueuesSyncQueueWhenGatewayDisconnected() async throws {
        let container = DIContainer.mock()
        let deps = container.makeOperatorDependencies()
        let operatorUser = DomainFixtures.operatorUser()
        let technician = DomainFixtures.technicianUser()
        let customer = DomainFixtures.customer()
        try await deps.userRepository.save(operatorUser)
        try await deps.userRepository.save(technician)
        try await deps.customerRepository.save(customer)

        let created = try await deps.workOrderService.createWithSync(
            actor: operatorUser,
            request: DomainFixtures.newWorkOrderRequest(customerId: customer.id)
        )
        let ops = try await deps.syncOperationRepository.list(
            entityType: .workOrder,
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
        let technician = DomainFixtures.technicianUser()
        let customer = DomainFixtures.customer()
        try await container.userRepository.save(operatorUser)
        try await container.userRepository.save(technician)
        try await container.customerRepository.save(customer)

        let service = OperatorWorkOrderService(
            createWorkOrder: CreateWorkOrderUseCase(
                workOrderRepository: container.workOrderRepository,
                statusHistoryRepository: container.workOrderStatusHistoryRepository
            ),
            assignWorkOrder: AssignWorkOrderUseCase(workOrderRepository: container.workOrderRepository),
            updateWorkOrderPlanning: UpdateWorkOrderPlanningUseCase(
                workOrderRepository: container.workOrderRepository
            ),
            statusHistoryRepository: container.workOrderStatusHistoryRepository,
            syncOperationRepository: container.syncOperationRepository,
            notificationRepository: container.notificationRepository,
            realtimeWorkOrderCreate: coordinator
        )
        let created = try await service.createWithSync(
            actor: operatorUser,
            request: DomainFixtures.newWorkOrderRequest(customerId: customer.id)
        )

        let ops = try await container.syncOperationRepository.list(
            entityType: .workOrder,
            entityId: created.id.rawValue
        )
        XCTAssertTrue(ops.contains { $0.operationType == .create && $0.status == .pending })

        let sent = try await transport.sentEnvelopes()
        let submit = sent.first { $0.type == .opSubmit && $0.payloadObject["entityType"] as? String == "workOrder" }
        XCTAssertNotNil(submit)
        XCTAssertEqual(submit?.payloadObject["entityId"] as? String, created.id.rawValue)
        XCTAssertEqual(
            submit?.payloadObject["idempotencyKey"] as? String,
            "uid-1:workOrder:\(created.id.rawValue):create:1"
        )
        let nested = submit?.payloadObject["payload"] as? [String: Any]
        XCTAssertEqual(nested?["workOrderNumber"] as? String, created.workOrderNumber)
        XCTAssertEqual(coordinator.telemetry.lastWorkOrderCreateAckStatus, "accepted")
        XCTAssertEqual(coordinator.telemetry.receivedAckCount, 1)
    }

    func testDuplicateWorkOrderCreateAckIsSuccess() async throws {
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

        let workOrder = DomainFixtures.workOrder(id: WorkOrderID("wo-dup"), workOrderNumber: "WO-DUP")
        let first = await coordinator.submitWorkOrderCreate(workOrder, actorUserId: "uid-1")
        let second = await coordinator.submitWorkOrderCreate(workOrder, actorUserId: "uid-1")
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
