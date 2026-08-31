import Foundation

/// WebSocket gateway endpoint configuration. Never hard-code production to localhost.
struct RealtimeGatewayConfiguration: Equatable, Sendable {
    var isEnabled: Bool
    var webSocketURL: URL?
    var deviceId: String
    var heartbeatInterval: TimeInterval
    var initialReconnectDelay: TimeInterval
    var maxReconnectDelay: TimeInterval

    static let defaultGatewayPort = 5088
    private static let webSocketPath = "/ws"

    static var `default`: RealtimeGatewayConfiguration {
        #if DEBUG
        return RealtimeGatewayConfiguration(
            isEnabled: true,
            webSocketURL: resolveDevelopmentWebSocketURL(),
            deviceId: Self.persistentDeviceId(),
            heartbeatInterval: 25,
            initialReconnectDelay: 1,
            maxReconnectDelay: 30
        )
        #else
        return RealtimeGatewayConfiguration(
            isEnabled: false,
            webSocketURL: nil,
            deviceId: Self.persistentDeviceId(),
            heartbeatInterval: 25,
            initialReconnectDelay: 1,
            maxReconnectDelay: 30
        )
        #endif
    }

    /// DEBUG development endpoint:
    /// - Simulator → Mac localhost (`127.0.0.1`)
    /// - Physical device → Info.plist host, else bundled `RealtimeGatewayHost.dev` (build-time Mac LAN IP)
    static func resolveDevelopmentWebSocketURL() -> URL? {
        guard let host = developmentGatewayHost()?.trimmingCharacters(in: .whitespacesAndNewlines),
              !host.isEmpty else {
            return nil
        }
        let port = developmentGatewayPort()
        var components = URLComponents()
        components.scheme = "ws"
        components.host = host
        components.port = port
        components.path = webSocketPath
        return components.url
    }

    static func developmentGatewayHost() -> String? {
        #if targetEnvironment(simulator)
        return "127.0.0.1"
        #else
        if let infoPlistHost = hostFromInfoPlist(), !isLocalhostHost(infoPlistHost) {
            return infoPlistHost
        }
        if let bundledHost = hostFromBundledDevelopmentFile(), !isLocalhostHost(bundledHost) {
            return bundledHost
        }
        return nil
        #endif
    }

    private static func hostFromInfoPlist() -> String? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "RealtimeGatewayHost") as? String else {
            return nil
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("$(") else { return nil }
        return trimmed
    }

    /// Written at Debug build time by `Scripts/generate-realtime-gateway-host.sh`.
    private static func hostFromBundledDevelopmentFile() -> String? {
        guard let url = Bundle.main.url(forResource: "RealtimeGatewayHost", withExtension: "dev") else {
            return nil
        }
        guard let data = try? Data(contentsOf: url),
              let raw = String(data: data, encoding: .utf8) else {
            return nil
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func isLocalhostHost(_ host: String) -> Bool {
        switch host.lowercased() {
        case "localhost", "127.0.0.1", "::1":
            return true
        default:
            return false
        }
    }

    /// DEBUG reconnects re-resolve the LAN host; Release uses the injected URL.
    static func resolvesWebSocketURL(for configuration: RealtimeGatewayConfiguration) -> URL? {
        #if DEBUG
        resolveDevelopmentWebSocketURL() ?? configuration.webSocketURL
        #else
        configuration.webSocketURL
        #endif
    }

    static func isAllowedOnCurrentRuntime(_ url: URL) -> Bool {
        #if targetEnvironment(simulator)
        true
        #else
        guard let host = url.host else { return false }
        return !isLocalhostHost(host)
        #endif
    }

    static func developmentGatewayPort() -> Int {
        if let raw = Bundle.main.object(forInfoDictionaryKey: "RealtimeGatewayPort") as? Int, raw > 0 {
            return raw
        }
        if let raw = Bundle.main.object(forInfoDictionaryKey: "RealtimeGatewayPort") as? String {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if let port = Int(trimmed), port > 0 { return port }
        }
        return defaultGatewayPort
    }

    static func persistentDeviceId() -> String {
        let key = "realtime.gateway.deviceId"
        if let existing = UserDefaults.standard.string(forKey: key), !existing.isEmpty {
            return existing
        }
        let created = UUID().uuidString
        UserDefaults.standard.set(created, forKey: key)
        return created
    }
}

enum RealtimeConnectionState: String, Equatable, Sendable {
    case disconnected
    case connecting
    case authenticating
    case connected
    case reconnecting
    case failed

    var debugLabel: String {
        switch self {
        case .disconnected: return "Disconnected"
        case .connecting: return "Connecting"
        case .authenticating: return "Authenticating"
        case .connected: return "Connected"
        case .reconnecting: return "Reconnecting"
        case .failed: return "Failed"
        }
    }

    var debugSymbol: String {
        switch self {
        case .connected: return "🟢"
        case .connecting, .authenticating, .reconnecting: return "🟡"
        case .disconnected, .failed: return "🔴"
        }
    }
}
