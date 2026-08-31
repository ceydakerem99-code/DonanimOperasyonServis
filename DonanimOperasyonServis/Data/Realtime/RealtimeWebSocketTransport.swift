import Foundation

protocol RealtimeWebSocketTransporting: AnyObject, Sendable {
    func connect(url: URL) async throws
    func send(data: Data) async throws
    func receive() async throws -> Data
    func close() async
}

/// Production transport backed by `URLSessionWebSocketTask`.
actor URLSessionRealtimeWebSocketTransport: RealtimeWebSocketTransporting {
    private var task: URLSessionWebSocketTask?
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func connect(url: URL) async throws {
        await close()
        let task = session.webSocketTask(with: url)
        self.task = task
        task.resume()
    }

    func send(data: Data) async throws {
        guard let task else { throw RealtimeClientError.notConnected }
        guard let text = String(data: data, encoding: .utf8) else {
            throw RealtimeClientError.malformedMessage("payload is not utf8")
        }
        try await task.send(.string(text))
    }

    func receive() async throws -> Data {
        guard let task else { throw RealtimeClientError.notConnected }
        let message = try await task.receive()
        switch message {
        case .data(let data):
            return data
        case .string(let text):
            guard let data = text.data(using: .utf8) else {
                throw RealtimeClientError.malformedMessage("non-utf8 text frame")
            }
            return data
        @unknown default:
            throw RealtimeClientError.malformedMessage("unknown websocket frame")
        }
    }

    func close() async {
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
    }
}

/// In-memory duplex transport for unit tests.
actor FakeRealtimeWebSocketTransport: RealtimeWebSocketTransporting {
    private var connected = false
    private var inbound: [Data] = []
    private var waiters: [CheckedContinuation<Data, Error>] = []
    private(set) var sent: [Data] = []
    private(set) var connectCallCount = 0
    var connectError: Error?
    var autoHelloOk = true
    var autoPong = true
    var autoAcceptOps = false
    private var acceptedIdempotencyKeys: Set<String> = []

    func setAutoHelloOk(_ enabled: Bool) {
        autoHelloOk = enabled
    }

    func setAutoAcceptOps(_ enabled: Bool) {
        autoAcceptOps = enabled
    }

    func enqueueInbound(_ data: Data) {
        if let waiter = waiters.first {
            waiters.removeFirst()
            waiter.resume(returning: data)
        } else {
            inbound.append(data)
        }
    }

    func connect(url: URL) async throws {
        _ = url
        connectCallCount += 1
        if let connectError { throw connectError }
        connected = true
    }

    func send(data: Data) async throws {
        guard connected else { throw RealtimeClientError.notConnected }
        sent.append(data)
        if let envelope = try? RealtimeProtocolCodec.decodeEnvelope(data) {
            if autoHelloOk, envelope.type == .hello {
                var ok: [String: Any] = [
                    "v": 1,
                    "type": "hello.ok",
                    "payload": [
                        "userId": "uid-test",
                        "role": "operator",
                        "serverTime": ISO8601DateFormatter().string(from: Date())
                    ]
                ]
                if let requestId = envelope.requestId {
                    ok["requestId"] = requestId
                }
                enqueueInbound(try JSONSerialization.data(withJSONObject: ok))
            } else if autoPong, envelope.type == .ping {
                let pong: [String: Any] = [
                    "v": 1,
                    "type": "pong",
                    "payload": envelope.payloadObject
                ]
                enqueueInbound(try JSONSerialization.data(withJSONObject: pong))
            } else if autoAcceptOps, envelope.type == .opSubmit {
                let payload = envelope.payloadObject
                let operationId = payload["operationId"] as? String ?? ""
                let key = payload["idempotencyKey"] as? String ?? ""
                let entityType = payload["entityType"] as? String ?? ""
                let entityId = payload["entityId"] as? String ?? ""
                let isDuplicate = acceptedIdempotencyKeys.contains(key)
                if !isDuplicate {
                    acceptedIdempotencyKeys.insert(key)
                }
                let eventId = "evt-\(operationId)"
                let ack: [String: Any] = [
                    "v": 1,
                    "type": "op.ack",
                    "payload": [
                        "operationId": operationId,
                        "idempotencyKey": key,
                        "status": isDuplicate ? "duplicate" : "accepted",
                        "eventId": eventId,
                        "remoteVersion": 1
                    ] as [String: Any]
                ]
                enqueueInbound(try JSONSerialization.data(withJSONObject: ack))
                if !isDuplicate {
                    let event: [String: Any] = [
                        "v": 1,
                        "type": "event.apply",
                        "payload": [
                            "eventId": eventId,
                            "operationId": operationId,
                            "eventType": "create",
                            "entityType": entityType,
                            "entityId": entityId,
                            "actorUserId": payload["actorUserId"] as? String ?? "",
                            "idempotencyKey": key,
                            "payload": ["shadow": true]
                        ] as [String: Any]
                    ]
                    enqueueInbound(try JSONSerialization.data(withJSONObject: event))
                }
            }
        }
    }

    func receive() async throws -> Data {
        guard connected else { throw RealtimeClientError.notConnected }
        if !inbound.isEmpty {
            return inbound.removeFirst()
        }
        return try await withCheckedThrowingContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func close() async {
        connected = false
        let pending = waiters
        waiters.removeAll()
        for waiter in pending {
            waiter.resume(throwing: RealtimeClientError.notConnected)
        }
    }

    /// Simulates an unexpected network drop (receive loop fails → reconnect).
    func simulateDrop() {
        connected = false
        let pending = waiters
        waiters.removeAll()
        for waiter in pending {
            waiter.resume(throwing: RealtimeClientError.transport("dropped"))
        }
    }

    func sentEnvelopes() throws -> [RealtimeEnvelope] {
        try sent.map { try RealtimeProtocolCodec.decodeEnvelope($0) }
    }
}
