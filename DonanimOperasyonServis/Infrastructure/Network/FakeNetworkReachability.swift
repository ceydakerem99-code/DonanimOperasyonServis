import Foundation

/// Deterministic reachability for unit tests and `DIContainer.mock()`.
/// Flip `setReachable` to simulate online / offline without touching
/// `NWPathMonitor` or the real network.
actor FakeNetworkReachability: NetworkReachabilityProviding {

    private var reachable: Bool
    private var continuations: [UUID: AsyncStream<Bool>.Continuation] = [:]

    init(isReachable: Bool = true) {
        self.reachable = isReachable
    }

    func setReachable(_ reachable: Bool) {
        let changed = self.reachable != reachable
        self.reachable = reachable
        guard changed else { return }
        for continuation in continuations.values {
            continuation.yield(reachable)
        }
    }

    var isReachable: Bool { reachable }

    func reachabilityUpdates() async -> AsyncStream<Bool> {
        let (stream, continuation) = AsyncStream<Bool>.makeStream()
        let id = UUID()
        continuations[id] = continuation
        continuation.yield(reachable)
        continuation.onTermination = { [weak self] _ in
            let actor = self
            Task { await actor?.removeContinuation(id) }
        }
        return stream
    }

    private func removeContinuation(_ id: UUID) {
        continuations[id] = nil
    }
}
