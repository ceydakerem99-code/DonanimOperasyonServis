import Foundation

/// Read-only view of device connectivity. Implementations live in
/// Infrastructure (`NWPathMonitor`) or tests (`FakeNetworkReachability`).
/// Domain never imports Network.framework.
protocol NetworkReachabilityProviding: Sendable {
    var isReachable: Bool { get async }

    /// Snapshots from the **same** underlying monitor / fake. Callers
    /// must not start a second `NWPathMonitor`. The first value is the
    /// current state; later values are transitions.
    func reachabilityUpdates() async -> AsyncStream<Bool>
}
