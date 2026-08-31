#if DEBUG
import Foundation

/// DEBUG live-build reachability: wraps `PathMonitorNetworkReachability` and
/// allows Developer Tools to force offline without replacing the production monitor.
protocol DebugNetworkReachabilityControlling: NetworkReachabilityProviding {
    var isSimulationOffline: Bool { get async }
    func setSimulatedOffline(_ offline: Bool) async
}

/// Real `NWPathMonitor` plus optional simulated offline for DEBUG live sessions.
actor DebuggableNetworkReachability: DebugNetworkReachabilityControlling {

    private let pathMonitor: PathMonitorNetworkReachability
    private var simulatedOffline = false
    private var continuations: [UUID: AsyncStream<Bool>.Continuation] = [:]
    private var observationTask: Task<Void, Never>?

    init(pathMonitor: PathMonitorNetworkReachability? = nil) {
        let monitor = pathMonitor ?? PathMonitorNetworkReachability()
        self.pathMonitor = monitor
        monitor.start()
    }

    private func ensurePathObservation() {
        guard observationTask == nil else { return }
        let monitor = pathMonitor
        observationTask = Task {
            let stream = await monitor.reachabilityUpdates()
            for await pathReachable in stream {
                await self.handlePathUpdate(pathReachable)
            }
        }
    }

    var isSimulationOffline: Bool {
        simulatedOffline
    }

    func setSimulatedOffline(_ offline: Bool) async {
        let changed = simulatedOffline != offline
        simulatedOffline = offline
        guard changed else { return }
        broadcast(await effectiveReachable())
    }

    var isReachable: Bool {
        get async {
            await effectiveReachable()
        }
    }

    func reachabilityUpdates() async -> AsyncStream<Bool> {
        AsyncStream { continuation in
            let id = UUID()
            Task {
                await self.registerContinuation(id: id, continuation: continuation)
            }
            continuation.onTermination = { _ in
                Task { await self.removeContinuation(id: id) }
            }
        }
    }

    private func effectiveReachable(pathReachable: Bool? = nil) async -> Bool {
        if simulatedOffline { return false }
        if let pathReachable { return pathReachable }
        return await pathMonitor.isReachable
    }

    private func handlePathUpdate(_ pathReachable: Bool) async {
        guard !simulatedOffline else { return }
        broadcast(await effectiveReachable(pathReachable: pathReachable))
    }

    private func registerContinuation(
        id: UUID,
        continuation: AsyncStream<Bool>.Continuation
    ) async {
        ensurePathObservation()
        continuations[id] = continuation
        continuation.yield(await effectiveReachable())
    }

    private func removeContinuation(id: UUID) {
        continuations[id] = nil
    }

    private func broadcast(_ reachable: Bool) {
        let simulationOffline = simulatedOffline
        AppLogger.sync.info(
            "SYNC AUTO-DRAIN reachability broadcast reachable=\(reachable, privacy: .public) simulatedOffline=\(simulationOffline, privacy: .public)"
        )
        for continuation in continuations.values {
            continuation.yield(reachable)
        }
    }
}
#endif
