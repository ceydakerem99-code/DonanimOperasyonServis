import Foundation

enum RealtimeMessageType: String, Sendable {
    case hello
    case helloOk = "hello.ok"
    case opSubmit = "op.submit"
    case opAck = "op.ack"
    case eventApply = "event.apply"
    case ping
    case pong
    case error
    case unknown
}

enum RealtimeAckStatus: String, Sendable {
    case accepted
    case duplicate
    case forbidden
    case conflict
    case invalid
    case error
}

/// FAZ 0/1 envelope. Unknown `type` values decode as `.unknown` without crashing.
struct RealtimeEnvelope: Equatable, Sendable {
    var v: Int
    var type: RealtimeMessageType
    var rawType: String
    var requestId: String?
    /// Raw JSON object for `payload` (forward-compatible).
    var payloadData: Data

    static let protocolVersion = 1

    var payloadObject: [String: Any] {
        (try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any]) ?? [:]
    }
}

struct RealtimeHelloPayload: Equatable, Sendable {
    var idToken: String
    var deviceId: String
    var protocolVersion: Int
    var entitySubscriptions: [String]
}

struct RealtimeHelloOkPayload: Equatable, Sendable {
    var userId: String
    var role: String
    var serverTime: String?
    var resumeToken: String?
}

struct RealtimeAckPayload: Equatable, Sendable {
    var operationId: String
    var idempotencyKey: String
    var status: RealtimeAckStatus
    var rawStatus: String
    var eventId: String?
    var remoteVersion: Int?
    var errorCode: String?
    var errorMessage: String?
    var retryable: Bool?
    var serverTimestamp: String?
    var correlationId: String?
}

struct RealtimeEventPayload: Equatable, Sendable {
    var eventId: String
    var operationId: String
    var eventType: String
    var entityType: String
    var entityId: String
    var actorUserId: String
    var timestamp: String?
    var idempotencyKey: String
    var payloadData: Data
    var protocolVersion: Int?
    var operationType: String?
    var remoteVersion: Int?
    var causation: String?
    var correlationId: String?
}

struct RealtimeGatewayErrorPayload: Equatable, Sendable {
    var code: String
    var message: String
    var retryable: Bool
}

enum RealtimeProtocolCodec {
    static func makeHelloEnvelope(
        idToken: String,
        deviceId: String,
        requestId: String = UUID().uuidString,
        subscriptions: [String] = ["customer", "workOrder"]
    ) throws -> Data {
        let body: [String: Any] = [
            "v": RealtimeEnvelope.protocolVersion,
            "type": RealtimeMessageType.hello.rawValue,
            "requestId": requestId,
            "payload": [
                "idToken": idToken,
                "deviceId": deviceId,
                "protocolVersion": RealtimeEnvelope.protocolVersion,
                "entitySubscriptions": subscriptions
            ] as [String: Any]
        ]
        return try JSONSerialization.data(withJSONObject: body, options: [])
    }

    static func makePingEnvelope(t: Int64 = Int64(Date().timeIntervalSince1970 * 1000)) throws -> Data {
        let body: [String: Any] = [
            "v": RealtimeEnvelope.protocolVersion,
            "type": RealtimeMessageType.ping.rawValue,
            "payload": ["t": t]
        ]
        return try JSONSerialization.data(withJSONObject: body, options: [])
    }

    static func makeOpSubmit(
        operationId: String,
        idempotencyKey: String,
        entityType: String,
        entityId: String,
        operationType: String,
        actorUserId: String,
        deviceId: String,
        localVersion: Int = 1,
        requestId: String = UUID().uuidString,
        payload: [String: Any]
    ) throws -> Data {
        let body: [String: Any] = [
            "v": RealtimeEnvelope.protocolVersion,
            "type": RealtimeMessageType.opSubmit.rawValue,
            "requestId": requestId,
            "payload": [
                "operationId": operationId,
                "idempotencyKey": idempotencyKey,
                "entityType": entityType,
                "entityId": entityId,
                "operationType": operationType,
                "localVersion": localVersion,
                "actorUserId": actorUserId,
                "deviceId": deviceId,
                "clientTimestamp": ISO8601DateFormatter().string(from: Date()),
                "payload": payload
            ] as [String: Any]
        ]
        return try JSONSerialization.data(withJSONObject: body, options: [])
    }

    static func makeShadowOpSubmit(
        operationId: String,
        idempotencyKey: String,
        entityType: String,
        entityId: String,
        operationType: String,
        actorUserId: String,
        deviceId: String,
        localVersion: Int = 1,
        requestId: String = UUID().uuidString
    ) throws -> Data {
        try makeOpSubmit(
            operationId: operationId,
            idempotencyKey: idempotencyKey,
            entityType: entityType,
            entityId: entityId,
            operationType: operationType,
            actorUserId: actorUserId,
            deviceId: deviceId,
            localVersion: localVersion,
            requestId: requestId,
            payload: ["id": entityId, "shadow": true]
        )
    }

    /// FAZ 0 idempotency: `{actorUid}:{entityType}:{entityId}:{opType}:{localVersion}`
    static func makeIdempotencyKey(
        actorUserId: String,
        entityType: String,
        entityId: String,
        operationType: String,
        localVersion: Int
    ) -> String {
        "\(actorUserId):\(entityType):\(entityId):\(operationType):\(localVersion)"
    }

    static func customerSnapshot(_ customer: Customer) -> [String: Any] {
        var snapshot: [String: Any] = [
            "id": customer.id.rawValue,
            "name": customer.name,
            "address": customer.address,
            "createdByUserId": customer.createdByUserId.rawValue,
            "createdAt": ISO8601DateFormatter().string(from: customer.createdAt),
            "updatedAt": ISO8601DateFormatter().string(from: customer.updatedAt)
        ]
        if let contactPersonName = customer.contactPersonName {
            snapshot["contactPersonName"] = contactPersonName
        }
        if let phone = customer.phoneNumber?.rawValue {
            snapshot["phoneNumber"] = phone
        }
        if let email = customer.email {
            snapshot["email"] = email
        }
        if let city = customer.city {
            snapshot["city"] = city
        }
        if let notes = customer.notes {
            snapshot["notes"] = notes
        }
        return snapshot
    }

    static func workOrderSnapshot(_ workOrder: WorkOrder) -> [String: Any] {
        var snapshot: [String: Any] = [
            "id": workOrder.id.rawValue,
            "workOrderNumber": workOrder.workOrderNumber,
            "createdByUserId": workOrder.createdByUserId.rawValue,
            "assignedTechnicianId": workOrder.assignedTechnicianId.rawValue,
            "customerId": workOrder.customerId.rawValue,
            "workType": workOrder.workType.rawValue,
            "deviceCategory": workOrder.deviceCategory.rawValue,
            "deviceBrand": workOrder.deviceBrand,
            "deviceModel": workOrder.deviceModel,
            "serialNumber": workOrder.serialNumber,
            "priority": workOrder.priority.rawValue,
            "scheduledDate": ISO8601DateFormatter().string(from: workOrder.scheduledDate),
            "status": workOrder.status.rawValue,
            "createdAt": ISO8601DateFormatter().string(from: workOrder.createdAt),
            "updatedAt": ISO8601DateFormatter().string(from: workOrder.updatedAt)
        ]
        if let issueDescription = workOrder.issueDescription {
            snapshot["issueDescription"] = issueDescription
        }
        if let range = workOrder.scheduledTimeRange {
            snapshot["scheduledStart"] = ISO8601DateFormatter().string(from: range.start)
            snapshot["scheduledEnd"] = ISO8601DateFormatter().string(from: range.end)
        }
        if let pauseReason = workOrder.currentPauseReason {
            snapshot["currentPauseReason"] = pauseReason.rawValue
        }
        if let completedAt = workOrder.completedAt {
            snapshot["completedAt"] = ISO8601DateFormatter().string(from: completedAt)
        }
        return snapshot
    }

    static func decodeEnvelope(_ data: Data) throws -> RealtimeEnvelope {
        let object = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        guard let dict = object as? [String: Any] else {
            throw RealtimeClientError.malformedMessage("root is not an object")
        }
        let rawType = dict["type"] as? String ?? ""
        let type = RealtimeMessageType(rawValue: rawType) ?? .unknown
        let payload = dict["payload"] as? [String: Any] ?? [:]
        let payloadData = try JSONSerialization.data(withJSONObject: payload, options: [])
        let version = (dict["v"] as? Int)
            ?? (dict["v"] as? NSNumber)?.intValue
            ?? RealtimeEnvelope.protocolVersion
        return RealtimeEnvelope(
            v: version,
            type: type,
            rawType: rawType,
            requestId: dict["requestId"] as? String,
            payloadData: payloadData
        )
    }

    static func decodeHelloOk(_ payload: [String: Any]) -> RealtimeHelloOkPayload? {
        guard let userId = payload["userId"] as? String, !userId.isEmpty else { return nil }
        return RealtimeHelloOkPayload(
            userId: userId,
            role: payload["role"] as? String ?? "unknown",
            serverTime: payload["serverTime"] as? String,
            resumeToken: payload["resumeToken"] as? String
        )
    }

    static func decodeAck(_ payload: [String: Any]) -> RealtimeAckPayload? {
        let rawStatus = payload["status"] as? String ?? ""
        let status = RealtimeAckStatus(rawValue: rawStatus) ?? .error
        let error = payload["error"] as? [String: Any]
        return RealtimeAckPayload(
            operationId: payload["operationId"] as? String ?? "",
            idempotencyKey: payload["idempotencyKey"] as? String ?? "",
            status: status,
            rawStatus: rawStatus,
            eventId: payload["eventId"] as? String,
            remoteVersion: intValue(payload["remoteVersion"]),
            errorCode: error?["code"] as? String,
            errorMessage: error?["message"] as? String,
            retryable: error?["retryable"] as? Bool,
            serverTimestamp: payload["serverTimestamp"] as? String,
            correlationId: payload["correlationId"] as? String
        )
    }

    static func decodeEvent(_ payload: [String: Any], protocolVersion: Int?) -> RealtimeEventPayload? {
        let eventId = payload["eventId"] as? String ?? ""
        let operationId = payload["operationId"] as? String ?? ""
        guard !eventId.isEmpty || !operationId.isEmpty else { return nil }
        let nested = payload["payload"] as? [String: Any] ?? [:]
        let nestedData = (try? JSONSerialization.data(withJSONObject: nested, options: [])) ?? Data("{}".utf8)
        return RealtimeEventPayload(
            eventId: eventId,
            operationId: operationId,
            eventType: payload["eventType"] as? String
                ?? payload["causation"] as? String
                ?? payload["operationType"] as? String
                ?? "unknown",
            entityType: payload["entityType"] as? String ?? "",
            entityId: payload["entityId"] as? String ?? "",
            actorUserId: payload["actorUserId"] as? String ?? "",
            timestamp: payload["serverTimestamp"] as? String ?? payload["timestamp"] as? String,
            idempotencyKey: payload["idempotencyKey"] as? String ?? "",
            payloadData: nestedData,
            protocolVersion: protocolVersion,
            operationType: payload["operationType"] as? String,
            remoteVersion: intValue(payload["remoteVersion"]),
            causation: payload["causation"] as? String,
            correlationId: payload["correlationId"] as? String
        )
    }

    static func decodeError(_ payload: [String: Any]) -> RealtimeGatewayErrorPayload {
        RealtimeGatewayErrorPayload(
            code: payload["code"] as? String ?? "error",
            message: payload["message"] as? String ?? "unknown",
            retryable: payload["retryable"] as? Bool ?? false
        )
    }

    private static func intValue(_ any: Any?) -> Int? {
        if let i = any as? Int { return i }
        if let n = any as? NSNumber { return n.intValue }
        return nil
    }
}

enum RealtimeClientError: Error, Equatable, Sendable {
    case disabled
    case missingURL
    case notConnected
    case authenticationFailed(String)
    case malformedMessage(String)
    case transport(String)
}
