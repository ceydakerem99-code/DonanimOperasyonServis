import Foundation

/// Deterministic reachability for unit tests and `DIContainer.mock()`.
/// Flip `setReachable` to simulate online / offline without touching
/// `NWPathMonitor` or the real network.
actor FakeNetworkReachability: NetworkReachabilityProviding {

    private var reachable: Bool

    init(isReachable: Bool = true) {
        self.reachable = isReachable
    }

    func setReachable(_ reachable: Bool) {
        self.reachable = reachable
    }

    var isReachable: Bool { reachable }
}
