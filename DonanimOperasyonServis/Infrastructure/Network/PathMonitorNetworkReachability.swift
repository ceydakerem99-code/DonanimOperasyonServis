import Foundation
import Network
import os

/// Production `NetworkReachabilityProviding` backed by `NWPathMonitor`.
///
/// Domain never sees this type. A single instance is owned by
/// `DIContainer` (live). Call `start()` / `stop()` explicitly —
/// there is no background sync scheduler attached to path updates.
///
/// `NWPathMonitor` is not `Sendable`. Reachability flags live in
/// `OSAllocatedUnfairLock` so `isReachable` can be read from async
/// contexts. `@unchecked Sendable` covers the monitor reference.
final class PathMonitorNetworkReachability: NetworkReachabilityProviding, @unchecked Sendable {

    private struct Snapshot: Sendable {
        var isReachable = false
        var started = false
    }

    private let queue = DispatchQueue(
        label: "com.donanimoperasyonservis.reachability"
    )
    private let snapshot = OSAllocatedUnfairLock(initialState: Snapshot())
    private var monitor: NWPathMonitor?

    deinit {
        monitor?.cancel()
        monitor = nil
    }

    /// Begins delivering path updates. Idempotent: a second start
    /// while already running is a no-op.
    func start() {
        let shouldStart = snapshot.withLock { state -> Bool in
            if state.started { return false }
            state.started = true
            return true
        }
        guard shouldStart else { return }

        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [snapshot] path in
            snapshot.withLock { state in
                state.isReachable = (path.status == .satisfied)
            }
        }
        self.monitor = monitor
        monitor.start(queue: queue)
    }

    /// Cancels the current monitor. A later `start()` allocates a
    /// fresh `NWPathMonitor` (`cancel()` is terminal on a given
    /// instance).
    func stop() {
        snapshot.withLock { state in
            state.started = false
            state.isReachable = false
        }
        monitor?.cancel()
        monitor = nil
    }

    var isReachable: Bool {
        get async {
            snapshot.withLock { $0.isReachable }
        }
    }
}
