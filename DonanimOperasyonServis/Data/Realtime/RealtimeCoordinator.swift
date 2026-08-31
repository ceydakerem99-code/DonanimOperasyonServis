import Foundation
import Observation
import os

/// Shadow-mode Realtime coordinator.
///
/// Connects to the C# gateway with a Firebase ID token, logs envelopes,
/// and stores telemetry only. Does **not** mutate SwiftData, Firestore,
/// or `SyncOperation`.
@Observable
final class RealtimeCoordinator: RealtimeCustomerCreateSubmitting, RealtimeWorkOrderCreateSubmitting, @unchecked Sendable {
    private(set) var connectionState: RealtimeConnectionState = .disconnected
    private(set) var telemetry = RealtimeShadowTelemetry()
    private(set) var lastFailureMessage: String?

    private let configuration: RealtimeGatewayConfiguration
    private let authService: any FirebaseAuthServing
    private let client: RealtimeWebSocketClient
    private let networkReachability: (any NetworkReachabilityProviding)?
#if DEBUG
    private let debugReachability: (any DebugNetworkReachabilityControlling)?
#endif

    private struct SessionFlags: Sendable {
        var wantsConnection = false
        var isAppActive = true
        var reconnectAttempt = 0
        var sessionGeneration = 0
        var connectionState: RealtimeConnectionState = .disconnected
    }

    private let flags = OSAllocatedUnfairLock(initialState: SessionFlags())
    private var reconnectTask: Task<Void, Never>?
    private var reachabilityObservationTask: Task<Void, Never>?
#if DEBUG
    private var simulatedOfflineObservationTask: Task<Void, Never>?
#endif
    private let smokeAckWaiters = OSAllocatedUnfairLock(
        initialState: [String: CheckedContinuation<String, Error>]()
    )

    init(
        authService: any FirebaseAuthServing,
        configuration: RealtimeGatewayConfiguration = .default,
        transport: (any RealtimeWebSocketTransporting)? = nil,
        networkReachability: (any NetworkReachabilityProviding)? = nil
    ) {
        self.authService = authService
        self.configuration = configuration
        self.networkReachability = networkReachability
        let resolvedTransport = transport ?? URLSessionRealtimeWebSocketTransport()
        self.client = RealtimeWebSocketClient(transport: resolvedTransport)
#if DEBUG
        self.debugReachability = nil
#endif
    }

#if DEBUG
    init(
        authService: any FirebaseAuthServing,
        configuration: RealtimeGatewayConfiguration,
        transport: (any RealtimeWebSocketTransporting)?,
        debugReachability: (any DebugNetworkReachabilityControlling)?
    ) {
        self.authService = authService
        self.configuration = configuration
        self.networkReachability = debugReachability
        let resolvedTransport = transport ?? URLSessionRealtimeWebSocketTransport()
        self.client = RealtimeWebSocketClient(transport: resolvedTransport)
        self.debugReachability = debugReachability
    }
#endif

    func handleAuthenticatedSession() {
        reconnectTask?.cancel()
        reconnectTask = nil
        flags.withLock {
            $0.wantsConnection = true
            $0.reconnectAttempt = 0
        }
#if DEBUG
        startObservingSimulatedOfflineIfNeeded()
#endif
        startObservingReachabilityIfNeeded()
        Task { await connectIfNeeded(reason: "login") }
    }

    func handleSignedOut() {
        flags.withLock {
            $0.wantsConnection = false
            $0.sessionGeneration += 1
        }
        reconnectTask?.cancel()
        reconnectTask = nil
        reachabilityObservationTask?.cancel()
        reachabilityObservationTask = nil
#if DEBUG
        simulatedOfflineObservationTask?.cancel()
        simulatedOfflineObservationTask = nil
#endif
        Task {
            await client.disconnect()
            setState(.disconnected)
            AppLogger.realtime.info("REALTIME DISCONNECTED reason=logout")
        }
    }

    func handleForeground() {
        let wants = flags.withLock { flags -> Bool in
            flags.isAppActive = true
            return flags.wantsConnection
        }
        guard wants else { return }
        Task { await connectIfNeeded(reason: "foreground") }
    }

    func handleBackground() {
        let wants = flags.withLock { flags -> Bool in
            flags.isAppActive = false
            flags.sessionGeneration += 1
            return flags.wantsConnection
        }
        reconnectTask?.cancel()
        reconnectTask = nil
        Task {
            await client.disconnect()
            if wants {
                setState(.disconnected)
                AppLogger.realtime.info("REALTIME DISCONNECTED reason=background")
            }
        }
    }

    /// FAZ 3A: real customer create → `op.submit` + wait for ACK.
    /// Does not enqueue/mutate `SyncOperation`. Skips when the socket is down
    /// so the existing SyncQueue path remains the production writer.
    func submitCustomerCreate(
        _ customer: Customer,
        actorUserId: String
    ) async -> RealtimeCustomerCreateSubmitResult {
        guard configuration.isEnabled, connectionState == .connected else {
            AppLogger.realtime.info("REALTIME CUSTOMER_CREATE skippedNotConnected")
            return .skippedNotConnected
        }
        let operationId = UUID().uuidString
        let key = RealtimeProtocolCodec.makeIdempotencyKey(
            actorUserId: actorUserId,
            entityType: "customer",
            entityId: customer.id.rawValue,
            operationType: "create",
            localVersion: 1
        )
        do {
            let status = try await submitAndAwaitAck(
                operationId: operationId,
                idempotencyKey: key,
                entityType: "customer",
                entityId: customer.id.rawValue,
                operationType: "create",
                actorUserId: actorUserId,
                payload: RealtimeProtocolCodec.customerSnapshot(customer)
            )
            mutateTelemetry { $0.lastCustomerCreateAckStatus = status }
            switch status {
            case "accepted":
                AppLogger.realtime.info(
                    "REALTIME ACK customerCreate status=accepted entityId=\(customer.id.rawValue, privacy: .public)"
                )
                return .accepted(operationId: operationId, eventId: nil)
            case "duplicate":
                AppLogger.realtime.info(
                    "REALTIME ACK customerCreate status=duplicate entityId=\(customer.id.rawValue, privacy: .public)"
                )
                return .duplicate(operationId: operationId, eventId: nil)
            default:
                AppLogger.realtime.error(
                    "REALTIME ACK customerCreate status=\(status, privacy: .public) entityId=\(customer.id.rawValue, privacy: .public)"
                )
                return .rejected(status: status)
            }
        } catch {
            AppLogger.realtime.error(
                "REALTIME ERROR customerCreate=\(error.localizedDescription, privacy: .public)"
            )
            return .failed(error.localizedDescription)
        }
    }

    /// FAZ 3B: real workOrder create → `op.submit` + wait for ACK.
    /// Does not enqueue/mutate `SyncOperation`. Skips when the socket is down
    /// so the existing SyncQueue path remains the production writer.
    func submitWorkOrderCreate(
        _ workOrder: WorkOrder,
        actorUserId: String
    ) async -> RealtimeWorkOrderCreateSubmitResult {
        guard configuration.isEnabled, connectionState == .connected else {
            AppLogger.realtime.info("REALTIME WORKORDER_CREATE skippedNotConnected")
            return .skippedNotConnected
        }
        let operationId = UUID().uuidString
        let key = RealtimeProtocolCodec.makeIdempotencyKey(
            actorUserId: actorUserId,
            entityType: "workOrder",
            entityId: workOrder.id.rawValue,
            operationType: "create",
            localVersion: 1
        )
        do {
            let status = try await submitAndAwaitAck(
                operationId: operationId,
                idempotencyKey: key,
                entityType: "workOrder",
                entityId: workOrder.id.rawValue,
                operationType: "create",
                actorUserId: actorUserId,
                payload: RealtimeProtocolCodec.workOrderSnapshot(workOrder)
            )
            mutateTelemetry { $0.lastWorkOrderCreateAckStatus = status }
            switch status {
            case "accepted":
                AppLogger.realtime.info(
                    "REALTIME ACK workOrderCreate status=accepted entityId=\(workOrder.id.rawValue, privacy: .public)"
                )
                return .accepted(operationId: operationId, eventId: nil)
            case "duplicate":
                AppLogger.realtime.info(
                    "REALTIME ACK workOrderCreate status=duplicate entityId=\(workOrder.id.rawValue, privacy: .public)"
                )
                return .duplicate(operationId: operationId, eventId: nil)
            default:
                AppLogger.realtime.error(
                    "REALTIME ACK workOrderCreate status=\(status, privacy: .public) entityId=\(workOrder.id.rawValue, privacy: .public)"
                )
                return .rejected(status: status)
            }
        } catch {
            AppLogger.realtime.error(
                "REALTIME ERROR workOrderCreate=\(error.localizedDescription, privacy: .public)"
            )
            return .failed(error.localizedDescription)
        }
    }

    /// DEBUG/smoke: submit a single shadow customer create (no Firebase mutation).
    func sendShadowProbe() async {
        guard connectionState == .connected, let uid = authService.currentUID else { return }
        let entityId = "shadow-probe-\(UUID().uuidString)"
        let operationId = UUID().uuidString
        let key = "\(uid):customer:\(entityId):create:1"
        do {
            let data = try RealtimeProtocolCodec.makeShadowOpSubmit(
                operationId: operationId,
                idempotencyKey: key,
                entityType: "customer",
                entityId: entityId,
                operationType: "create",
                actorUserId: uid,
                deviceId: configuration.deviceId
            )
            try await client.send(data: data)
            AppLogger.realtime.info("REALTIME SHADOW_PROBE_SENT entityId=\(entityId, privacy: .public)")
        } catch {
            AppLogger.realtime.error(
                "REALTIME ERROR shadowProbe=\(error.localizedDescription, privacy: .public)"
            )
        }
    }

    /// DEBUG real-gateway smoke: 1 customer + 1 workOrder create, then duplicate customer submit.
    /// Does not touch SwiftData, Firestore, or SyncOperation.
    @discardableResult
    func runShadowSmokeSequence() async -> RealtimeShadowSmokeReport {
        guard configuration.isEnabled else {
            return failSmoke("Gateway disabled (Release/placeholder)")
        }
        guard connectionState == .connected, let uid = authService.currentUID else {
            return failSmoke("Not connected — login with Live Firebase Auth and wait for 🟢 Connected")
        }

        let suffix = UUID().uuidString.lowercased()
        let customerId = "shadow-smoke-customer-\(suffix)"
        let workOrderId = "shadow-smoke-workorder-\(suffix)"
        let customerOpId = UUID().uuidString
        let workOrderOpId = UUID().uuidString
        let duplicateOpId = UUID().uuidString
        let customerKey = "\(uid):customer:\(customerId):create:1"
        let workOrderKey = "\(uid):workOrder:\(workOrderId):create:1"

        do {
            let customerAck = try await submitAndAwaitAck(
                operationId: customerOpId,
                idempotencyKey: customerKey,
                entityType: "customer",
                entityId: customerId,
                operationType: "create",
                actorUserId: uid,
                payload: ["id": customerId, "shadow": true]
            )
            guard customerAck == "accepted" else {
                return failSmoke(
                    "customer ACK=\(customerAck) (expected accepted)",
                    customerAck: customerAck,
                    customerEntityId: customerId
                )
            }

            let workOrderAck = try await submitAndAwaitAck(
                operationId: workOrderOpId,
                idempotencyKey: workOrderKey,
                entityType: "workOrder",
                entityId: workOrderId,
                operationType: "create",
                actorUserId: uid,
                payload: ["id": workOrderId, "shadow": true]
            )
            guard workOrderAck == "accepted" else {
                return failSmoke(
                    "workOrder ACK=\(workOrderAck) (expected accepted)",
                    customerAck: customerAck,
                    workOrderAck: workOrderAck,
                    customerEntityId: customerId,
                    workOrderEntityId: workOrderId
                )
            }

            let duplicateAck = try await submitAndAwaitAck(
                operationId: duplicateOpId,
                idempotencyKey: customerKey,
                entityType: "customer",
                entityId: customerId,
                operationType: "create",
                actorUserId: uid,
                payload: ["id": customerId, "shadow": true]
            )
            guard duplicateAck == "duplicate" else {
                return failSmoke(
                    "duplicate ACK=\(duplicateAck) (expected duplicate)",
                    customerAck: customerAck,
                    workOrderAck: workOrderAck,
                    duplicateAck: duplicateAck,
                    customerEntityId: customerId,
                    workOrderEntityId: workOrderId
                )
            }

            let report = RealtimeShadowSmokeReport(
                customerAck: customerAck,
                workOrderAck: workOrderAck,
                duplicateAck: duplicateAck,
                customerEntityId: customerId,
                workOrderEntityId: workOrderId,
                succeeded: true,
                detail: "Shadow smoke OK — in-memory only; Firebase not written"
            )
            mutateTelemetry { $0.lastSmokeReport = report }
            AppLogger.realtime.info(
                "REALTIME SMOKE_OK customer=\(customerId, privacy: .public) workOrder=\(workOrderId, privacy: .public)"
            )
            return report
        } catch {
            return failSmoke(
                "smoke failed: \(error.localizedDescription)",
                customerEntityId: customerId,
                workOrderEntityId: workOrderId
            )
        }
    }

    private func submitAndAwaitAck(
        operationId: String,
        idempotencyKey: String,
        entityType: String,
        entityId: String,
        operationType: String,
        actorUserId: String,
        payload: [String: Any]
    ) async throws -> String {
        let data = try RealtimeProtocolCodec.makeOpSubmit(
            operationId: operationId,
            idempotencyKey: idempotencyKey,
            entityType: entityType,
            entityId: entityId,
            operationType: operationType,
            actorUserId: actorUserId,
            deviceId: configuration.deviceId,
            payload: payload
        )
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            let registered = smokeAckWaiters.withLock { waiters -> Bool in
                if waiters[operationId] != nil { return false }
                waiters[operationId] = continuation
                return true
            }
            guard registered else {
                continuation.resume(throwing: RealtimeClientError.transport("duplicate smoke waiter"))
                return
            }
            Task {
                do {
                    try await self.client.send(data: data)
                    AppLogger.realtime.info(
                        "REALTIME OP_SUBMITTED entityType=\(entityType, privacy: .public) entityId=\(entityId, privacy: .public)"
                    )
                } catch {
                    self.finishSmokeWaiter(operationId: operationId, result: .failure(error))
                    return
                }
                try? await Task.sleep(nanoseconds: 8_000_000_000)
                self.finishSmokeWaiter(
                    operationId: operationId,
                    result: .failure(RealtimeClientError.transport("ACK timeout for \(operationId)"))
                )
            }
        }
    }

    private func finishSmokeWaiter(operationId: String, result: Result<String, Error>) {
        let continuation = smokeAckWaiters.withLock { waiters -> CheckedContinuation<String, Error>? in
            waiters.removeValue(forKey: operationId)
        }
        continuation?.resume(with: result)
    }

    private func failSmoke(
        _ detail: String,
        customerAck: String? = nil,
        workOrderAck: String? = nil,
        duplicateAck: String? = nil,
        customerEntityId: String? = nil,
        workOrderEntityId: String? = nil
    ) -> RealtimeShadowSmokeReport {
        let report = RealtimeShadowSmokeReport(
            customerAck: customerAck,
            workOrderAck: workOrderAck,
            duplicateAck: duplicateAck,
            customerEntityId: customerEntityId,
            workOrderEntityId: workOrderEntityId,
            succeeded: false,
            detail: detail
        )
        mutateTelemetry { $0.lastSmokeReport = report }
        AppLogger.realtime.error("REALTIME SMOKE_FAIL detail=\(detail, privacy: .public)")
        return report
    }

    private func shouldForceRefreshIdToken(for reason: String) -> Bool {
        reason == "login"
    }

    private func connectIfNeeded(reason: String) async {
        guard configuration.isEnabled else {
            setState(.disconnected)
            return
        }

#if DEBUG
        if await isSimulatedOffline() {
            await pauseForSimulatedOffline()
            return
        }
#endif

        if let networkReachability, await !networkReachability.isReachable {
            setState(.disconnected)
            return
        }

        let snapshot = flags.withLock { $0 }
        guard snapshot.wantsConnection, snapshot.isAppActive else { return }
        guard let url = resolvedWebSocketURL(), RealtimeGatewayConfiguration.isAllowedOnCurrentRuntime(url) else {
            reconnectTask?.cancel()
            reconnectTask = nil
            setState(.disconnected)
            let host = resolvedWebSocketURL()?.host ?? "missing"
            AppLogger.realtime.info("REALTIME SKIP reason=unreachable_gateway host=\(host, privacy: .public)")
            return
        }
        let current = snapshot.connectionState
        let generation = snapshot.sessionGeneration
        if current == .connected || current == .connecting || current == .authenticating {
            return
        }
        if current == .reconnecting {
            guard reason == "backoff" || reason == "token_refresh" || reason == "network_restored" else {
                return
            }
        }

        if current == .reconnecting {
            AppLogger.realtime.info("REALTIME RECONNECT reason=\(reason, privacy: .public)")
        } else {
            AppLogger.realtime.info("REALTIME CONNECTING reason=\(reason, privacy: .public)")
            setState(.connecting)
        }

        await client.setHandlers(onEnvelope: nil, onTransportClosed: nil)
        await client.disconnect()
        await client.setHandlers(
            onEnvelope: { [weak self] envelope in
                await self?.handleEnvelope(envelope, generation: generation)
            },
            onTransportClosed: { [weak self] error in
                await self?.handleTransportClosed(error, generation: generation)
            }
        )

        do {
            try await client.connect(url: url)
            let stillValid = flags.withLock {
                $0.sessionGeneration == generation && $0.wantsConnection && $0.isAppActive
            }
            guard stillValid else {
                await client.disconnect()
                return
            }
            setState(.authenticating)
            AppLogger.realtime.info("REALTIME AUTHENTICATING")
            let forceRefresh = shouldForceRefreshIdToken(for: reason)
            let token = try await authService.idToken(forceRefresh: forceRefresh)
            try await client.sendHello(idToken: token, deviceId: configuration.deviceId)
        } catch {
            await failAndScheduleReconnect(error, generation: generation)
        }
    }

    private func handleEnvelope(_ envelope: RealtimeEnvelope, generation: Int) async {
        let valid = flags.withLock { $0.sessionGeneration == generation }
        guard valid else { return }
        let payload = envelope.payloadObject

        switch envelope.type {
        case .helloOk:
            guard let ok = RealtimeProtocolCodec.decodeHelloOk(payload) else {
                mutateTelemetry { $0.unknownMessageCount += 1 }
                return
            }
            mutateTelemetry {
                $0.lastHelloUserId = ok.userId
                $0.lastHelloRole = ok.role
            }
            setState(.connected)
            flags.withLock { $0.reconnectAttempt = 0 }
            await client.startHeartbeat(interval: configuration.heartbeatInterval)
            AppLogger.realtime.info(
                "REALTIME AUTHENTICATED userId=\(ok.userId, privacy: .public) role=\(ok.role, privacy: .public)"
            )
            AppLogger.realtime.info("REALTIME CONNECTED")

        case .opAck:
            guard let ack = RealtimeProtocolCodec.decodeAck(payload) else {
                mutateTelemetry { $0.unknownMessageCount += 1 }
                return
            }
            mutateTelemetry {
                $0.receivedAckCount += 1
                $0.lastAckStatus = ack.rawStatus
                $0.lastAckOperationId = ack.operationId
            }
            finishSmokeWaiter(operationId: ack.operationId, result: .success(ack.rawStatus))
            AppLogger.realtime.info(
                "REALTIME ACK status=\(ack.rawStatus, privacy: .public) operationId=\(ack.operationId, privacy: .public)"
            )

        case .eventApply:
            if let event = RealtimeProtocolCodec.decodeEvent(payload, protocolVersion: envelope.v) {
                mutateTelemetry {
                    $0.receivedEventCount += 1
                    $0.lastEventId = event.eventId
                    $0.lastEventEntityType = event.entityType
                }
                AppLogger.realtime.info(
                    "REALTIME EVENT_RECEIVED eventId=\(event.eventId, privacy: .public) entityType=\(event.entityType, privacy: .public) entityId=\(event.entityId, privacy: .public)"
                )
            } else {
                mutateTelemetry { $0.unknownMessageCount += 1 }
                AppLogger.realtime.info("REALTIME EVENT_RECEIVED unknown_or_incomplete")
            }

        case .pong:
            break

        case .error:
            let err = RealtimeProtocolCodec.decodeError(payload)
            mutateTelemetry { $0.lastErrorCode = err.code }
            setFailure(err.message)
            AppLogger.realtime.error(
                "REALTIME ERROR code=\(err.code, privacy: .public) message=\(err.message, privacy: .public)"
            )
            if err.code == "unauthorized" {
                await refreshTokenAndReconnect(generation: generation)
            }

        case .unknown, .hello, .opSubmit, .ping:
            mutateTelemetry { $0.unknownMessageCount += 1 }
            AppLogger.realtime.info(
                "REALTIME EVENT_RECEIVED ignored_type=\(envelope.rawType, privacy: .public)"
            )
        }
    }

    private func handleTransportClosed(_ error: Error?, generation: Int) async {
        let snapshot = flags.withLock { $0 }
        guard snapshot.sessionGeneration == generation else { return }
        guard snapshot.wantsConnection, snapshot.isAppActive else {
            setState(.disconnected)
            return
        }
        await failAndScheduleReconnect(
            error ?? RealtimeClientError.transport("closed"),
            generation: generation
        )
    }

    private func refreshTokenAndReconnect(generation: Int) async {
        let valid = flags.withLock {
            $0.sessionGeneration == generation && $0.wantsConnection
        }
        guard valid else { return }
#if DEBUG
        if await isSimulatedOffline() {
            await pauseForSimulatedOffline()
            return
        }
#endif
        do {
            _ = try await authService.idToken(forceRefresh: true)
            AppLogger.realtime.info("REALTIME RECONNECT reason=token_refresh")
            setState(.reconnecting)
            await client.setHandlers(onEnvelope: nil, onTransportClosed: nil)
            await client.disconnect()
            await connectIfNeeded(reason: "token_refresh")
        } catch {
            await failAndScheduleReconnect(error, generation: generation)
        }
    }

    private func failAndScheduleReconnect(_ error: Error, generation: Int) async {
        let snapshot = flags.withLock { $0 }
        guard snapshot.sessionGeneration == generation else { return }

        setFailure(error.localizedDescription)
        await client.disconnect()

        guard snapshot.wantsConnection, snapshot.isAppActive, configuration.isEnabled else {
            setState(.failed)
            return
        }

#if DEBUG
        if await isSimulatedOffline() {
            await pauseForSimulatedOffline()
            return
        }
#endif

        if let networkReachability, await !networkReachability.isReachable {
            setState(.disconnected)
            return
        }

        guard resolvedWebSocketURL() != nil else {
            reconnectTask?.cancel()
            reconnectTask = nil
            setState(.disconnected)
            return
        }

        setState(.reconnecting)
        let attempt = flags.withLock { flags -> Int in
            flags.reconnectAttempt += 1
            return flags.reconnectAttempt
        }
        let delay = min(
            configuration.maxReconnectDelay,
            configuration.initialReconnectDelay * pow(2, Double(max(0, attempt - 1)))
        )
        AppLogger.realtime.info(
            "REALTIME RECONNECT attempt=\(attempt) delay=\(delay, privacy: .public)s"
        )
        reconnectTask?.cancel()
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard let self, !Task.isCancelled else { return }
            await self.connectIfNeeded(reason: "backoff")
        }
    }

    private func setState(_ state: RealtimeConnectionState) {
        flags.withLock { $0.connectionState = state }
        DispatchQueue.main.async { self.connectionState = state }
    }

    private func setFailure(_ message: String) {
        DispatchQueue.main.async { self.lastFailureMessage = message }
    }

    private func mutateTelemetry(_ body: @escaping @Sendable (inout RealtimeShadowTelemetry) -> Void) {
        DispatchQueue.main.async {
            var copy = self.telemetry
            body(&copy)
            self.telemetry = copy
        }
    }

#if DEBUG
    private func isSimulatedOffline() async -> Bool {
        guard let debugReachability else { return false }
        return await debugReachability.isSimulationOffline
    }

    private func startObservingSimulatedOfflineIfNeeded() {
        guard simulatedOfflineObservationTask == nil,
              let reachability = debugReachability else { return }
        simulatedOfflineObservationTask = Task { [weak self] in
            let stream = await reachability.reachabilityUpdates()
            for await reachable in stream {
                guard let self else { return }
                if reachable {
                    await self.connectIfNeeded(reason: "network_restored")
                } else {
                    await self.pauseForNetworkUnavailable(reason: "simulated_offline")
                }
            }
        }
    }

    private func pauseForSimulatedOffline() async {
        await pauseForNetworkUnavailable(reason: "simulated_offline")
    }
#endif

    private func startObservingReachabilityIfNeeded() {
#if DEBUG
        guard debugReachability == nil else { return }
#endif
        guard reachabilityObservationTask == nil, let networkReachability else { return }
        reachabilityObservationTask = Task { [weak self] in
            let stream = await networkReachability.reachabilityUpdates()
            for await reachable in stream {
                guard let self else { return }
                if reachable {
                    await self.connectIfNeeded(reason: "network_restored")
                } else {
                    await self.pauseForNetworkUnavailable(reason: "network_unavailable")
                }
            }
        }
    }

    private func pauseForNetworkUnavailable(reason: String) async {
        reconnectTask?.cancel()
        reconnectTask = nil
        await client.setHandlers(onEnvelope: nil, onTransportClosed: nil)
        await client.disconnect()
        setState(.disconnected)
        AppLogger.realtime.info("REALTIME PAUSED reason=\(reason, privacy: .public)")
    }

    private func resolvedWebSocketURL() -> URL? {
        RealtimeGatewayConfiguration.resolvesWebSocketURL(for: configuration)
    }
}
