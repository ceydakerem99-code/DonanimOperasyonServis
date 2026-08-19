import Foundation

/// Read-only view of device connectivity. Implementations live in
/// Infrastructure (`NWPathMonitor`) or tests (`FakeNetworkReachability`).
/// Domain never imports Network.framework.
protocol NetworkReachabilityProviding: Sendable {
    var isReachable: Bool { get async }
}
