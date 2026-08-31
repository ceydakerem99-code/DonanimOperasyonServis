import Foundation

/// Shadow telemetry only — never mutates SwiftData / Firebase / SyncOperation.
struct RealtimeShadowTelemetry: Equatable, Sendable {
    var lastHelloUserId: String?
    var lastHelloRole: String?
    var lastAckStatus: String?
    var lastAckOperationId: String?
    var lastEventId: String?
    var lastEventEntityType: String?
    var lastErrorCode: String?
    var receivedAckCount: Int = 0
    var receivedEventCount: Int = 0
    var unknownMessageCount: Int = 0
    var lastSmokeReport: RealtimeShadowSmokeReport?
    var lastCustomerCreateAckStatus: String?
    var lastWorkOrderCreateAckStatus: String?
}

/// FAZ 3A: customer create → gateway `op.submit` outcome. Does not mutate SyncQueue.
enum RealtimeCustomerCreateSubmitResult: Equatable, Sendable {
    case skippedNotConnected
    case accepted(operationId: String, eventId: String?)
    case duplicate(operationId: String, eventId: String?)
    case rejected(status: String)
    case failed(String)

    var isAcknowledgedSuccess: Bool {
        switch self {
        case .accepted, .duplicate: return true
        default: return false
        }
    }
}

/// FAZ 3B: workOrder create → gateway `op.submit` outcome. Does not mutate SyncQueue.
enum RealtimeWorkOrderCreateSubmitResult: Equatable, Sendable {
    case skippedNotConnected
    case accepted(operationId: String, eventId: String?)
    case duplicate(operationId: String, eventId: String?)
    case rejected(status: String)
    case failed(String)

    var isAcknowledgedSuccess: Bool {
        switch self {
        case .accepted, .duplicate: return true
        default: return false
        }
    }
}

protocol RealtimeCustomerCreateSubmitting: AnyObject, Sendable {
    func submitCustomerCreate(_ customer: Customer, actorUserId: String) async -> RealtimeCustomerCreateSubmitResult
}

protocol RealtimeWorkOrderCreateSubmitting: AnyObject, Sendable {
    func submitWorkOrderCreate(_ workOrder: WorkOrder, actorUserId: String) async -> RealtimeWorkOrderCreateSubmitResult
}

/// Result of DEBUG real-gateway smoke sequence (telemetry only).
struct RealtimeShadowSmokeReport: Equatable, Sendable {
    var customerAck: String?
    var workOrderAck: String?
    var duplicateAck: String?
    var customerEntityId: String?
    var workOrderEntityId: String?
    var succeeded: Bool
    var detail: String

    var summary: String {
        if succeeded {
            return "OK customer=\(customerAck ?? "?") workOrder=\(workOrderAck ?? "?") duplicate=\(duplicateAck ?? "?")"
        }
        return detail
    }
}

/// Low-level WebSocket session: connect, hello, ping, receive loop callbacks.
actor RealtimeWebSocketClient {
    private let transport: any RealtimeWebSocketTransporting
    private var receiveTask: Task<Void, Never>?
    private var heartbeatTask: Task<Void, Never>?
    private(set) var isConnected = false

    var onEnvelope: (@Sendable (RealtimeEnvelope) async -> Void)?
    var onTransportClosed: (@Sendable (Error?) async -> Void)?

    init(transport: any RealtimeWebSocketTransporting) {
        self.transport = transport
    }

    func connect(url: URL) async throws {
        try await transport.connect(url: url)
        isConnected = true
        startReceiveLoop()
    }

    func disconnect() async {
        heartbeatTask?.cancel()
        heartbeatTask = nil
        receiveTask?.cancel()
        receiveTask = nil
        isConnected = false
        await transport.close()
    }

    func sendHello(idToken: String, deviceId: String) async throws {
        let data = try RealtimeProtocolCodec.makeHelloEnvelope(
            idToken: idToken,
            deviceId: deviceId
        )
        try await transport.send(data: data)
    }

    func sendPing() async throws {
        try await transport.send(data: try RealtimeProtocolCodec.makePingEnvelope())
    }

    func send(data: Data) async throws {
        try await transport.send(data: data)
    }

    func startHeartbeat(interval: TimeInterval) {
        heartbeatTask?.cancel()
        heartbeatTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                guard !Task.isCancelled else { return }
                do {
                    try await self.sendPing()
                } catch {
                    return
                }
            }
        }
    }

    func setHandlers(
        onEnvelope: (@Sendable (RealtimeEnvelope) async -> Void)?,
        onTransportClosed: (@Sendable (Error?) async -> Void)?
    ) {
        self.onEnvelope = onEnvelope
        self.onTransportClosed = onTransportClosed
    }

    private func startReceiveLoop() {
        receiveTask?.cancel()
        receiveTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                do {
                    let data = try await self.transport.receive()
                    let envelope = try RealtimeProtocolCodec.decodeEnvelope(data)
                    if let onEnvelope = await self.onEnvelope {
                        await onEnvelope(envelope)
                    }
                } catch {
                    await self.handleReceiveFailure(error)
                    return
                }
            }
        }
    }

    private func handleReceiveFailure(_ error: Error) async {
        if error is CancellationError {
            return
        }
        isConnected = false
        heartbeatTask?.cancel()
        heartbeatTask = nil
        if let onTransportClosed {
            await onTransportClosed(error)
        }
    }
}
