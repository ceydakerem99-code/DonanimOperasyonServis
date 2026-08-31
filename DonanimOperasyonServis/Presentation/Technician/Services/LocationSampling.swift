import CoreLocation
import Foundation

#if DEBUG
/// DEBUG-only metadata describing where a location fix originated.
struct LocationSampleDiagnostics: Equatable, Sendable {
    enum Source: String, Sendable, CaseIterable {
        case realDevice
        case cached
        case simulator
        case testMock

        var displayName: String {
            switch self {
            case .realDevice: return "Gerçek GPS"
            case .cached: return "Önbellek"
            case .simulator: return "Simülatör"
            case .testMock: return "Test konumu"
            }
        }
    }

    let source: Source
    let capturedAt: Date
    let accuracyMeters: Double?

    var debugSummary: String {
        let accuracyText: String
        if let accuracyMeters {
            accuracyText = String(format: "±%.0f m", accuracyMeters)
        } else {
            accuracyText = "±?"
        }
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .medium
        return "Kaynak: \(source.displayName) · \(formatter.string(from: capturedAt)) · \(accuracyText)"
    }
}

protocol LocationSamplingWithDiagnostics: LocationSampling {
    var lastSampleDiagnostics: LocationSampleDiagnostics? { get }
}
#endif

protocol LocationSampling: Sendable {
    func sample() async throws -> LocationCoordinate
    /// Event-aware sample. Default implementations ignore the event.
    func sample(for event: LocationEvent) async throws -> LocationCoordinate
}

extension LocationSampling {
    func sample(for event: LocationEvent) async throws -> LocationCoordinate {
        try await sample()
    }
}

/// Presentation-layer GPS failures. Mapped to Turkish UI copy — not domain errors.
enum LocationSamplingError: Error, Equatable, Sendable {
    case servicesDisabled
    case permissionDenied
    case permissionRestricted
    case timedOut
    case failed

    var technicianMessage: String {
        switch self {
        case .servicesDisabled:
            return "Konum servisleri kapalı. Ayarlar'dan açıp tekrar deneyin."
        case .permissionDenied:
            return "Konum izni reddedildi. Ayarlar'dan izin verin veya daha sonra tekrar deneyin."
        case .permissionRestricted:
            return "Konum erişimi kısıtlı. Bu cihazda GPS kaydı alınamıyor."
        case .timedOut:
            return "Konum alınamadı. Lütfen GPS'in açık olduğundan emin olun ve tekrar deneyin."
        case .failed:
            return "Konum alınamadı. Tekrar deneyin."
        }
    }
}

/// Hardware / authorization helpers for technician GPS capture.
enum TechnicianLocationAccess {
    @MainActor
    static var authorizationStatus: CLAuthorizationStatus {
        CLLocationManager().authorizationStatus
    }

    static let unavailableMessage =
        "Konum servisleri kapalı. Ayarlar'dan açıp tekrar deneyin."

    static let deniedMessage =
        "Konum izni reddedildi. Ayarlar'dan izin verin veya daha sonra tekrar deneyin."
}

/// Live CoreLocation one-shot fix for field evidence.
final class CoreLocationSampler: LocationSampling, @unchecked Sendable {
    /// Maximum wait for a fix before surfacing `.timedOut`.
    var timeoutNanoseconds: UInt64 = 15_000_000_000

    #if DEBUG
    private(set) var lastSampleDiagnostics: LocationSampleDiagnostics?
    #endif

    func sample() async throws -> LocationCoordinate {
        try await sample(for: .arrived)
    }

    func sample(for event: LocationEvent) async throws -> LocationCoordinate {
        let result = try await LocationFixSession(timeoutNanoseconds: timeoutNanoseconds).capture()
        #if DEBUG
        lastSampleDiagnostics = result.diagnostics
        #endif
        return result.coordinate
    }
}

struct FixedLocationSampler: LocationSampling, Sendable {
    let coordinate: LocationCoordinate

    func sample() async throws -> LocationCoordinate { coordinate }
}

#if DEBUG
/// DEBUG-only field GPS mock with distinct coordinates per event.
final class MockFieldLocationSampler: LocationSampling, @unchecked Sendable {
    private(set) var lastSampleDiagnostics: LocationSampleDiagnostics?

    func sample() async throws -> LocationCoordinate {
        try await sample(for: .arrived)
    }

    func sample(for event: LocationEvent) async throws -> LocationCoordinate {
        let coordinate: LocationCoordinate
        switch event {
        case .enRoute:
            coordinate = LocationCoordinate(latitude: 41.0100, longitude: 28.9700, accuracy: 8)
        case .arrived:
            coordinate = LocationCoordinate(latitude: 41.0150, longitude: 28.9800, accuracy: 5)
        case .completed:
            coordinate = LocationCoordinate(latitude: 41.0160, longitude: 28.9810, accuracy: 4)
        }
        #if targetEnvironment(simulator)
        let source: LocationSampleDiagnostics.Source = .simulator
        #else
        let source: LocationSampleDiagnostics.Source = .testMock
        #endif
        lastSampleDiagnostics = LocationSampleDiagnostics(
            source: source,
            capturedAt: Date(),
            accuracyMeters: coordinate.accuracy
        )
        return coordinate
    }
}

/// UserDefaults-backed DEBUG preference for location source.
enum DebugLocationSettings {
    enum Source: String, CaseIterable, Identifiable {
        case deviceGPS
        case testLocation

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .deviceGPS: return "Gerçek GPS"
            case .testLocation: return "Test Konumu"
            }
        }
    }

    private static let key = "debug.locationSource"

    static var source: Source {
        get {
            if let raw = UserDefaults.standard.string(forKey: key),
               let value = Source(rawValue: raw) {
                return value
            }
            // Simulator CoreLocation is flaky; default to mock so field
            // status flows (Yola Çık → …) are testable without a fix.
            #if targetEnvironment(simulator)
            return .testLocation
            #else
            return .deviceGPS
            #endif
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: key)
        }
    }

    static func makeSampler() -> any LocationSampling {
        switch source {
        case .deviceGPS:
            return CoreLocationSampler()
        case .testLocation:
            return MockFieldLocationSampler()
        }
    }
}
#endif

/// Test double that fails sampling with a controlled error.
struct ThrowingLocationSampler: LocationSampling, Sendable {
    let error: LocationSamplingError

    func sample() async throws -> LocationCoordinate {
        throw error
    }
}

/// Test double that delays so cancellation can interrupt sampling.
struct DelayedLocationSampler: LocationSampling, Sendable {
    let nanoseconds: UInt64
    let coordinate: LocationCoordinate

    func sample() async throws -> LocationCoordinate {
        try await Task.sleep(nanoseconds: nanoseconds)
        return coordinate
    }
}

// MARK: - CoreLocation session

private struct LocationFixCaptureResult: Sendable {
    let coordinate: LocationCoordinate
    #if DEBUG
    let diagnostics: LocationSampleDiagnostics
    #endif
}

/// Captures one valid fix via continuous updates (more reliable than
/// `requestLocation()` on Simulator, where one-shot often times out
/// even when Features → Location is set).
private final class LocationFixSession: NSObject, CLLocationManagerDelegate, @unchecked Sendable {
    private static let cachedFixMaxAge: TimeInterval = 30

    private let manager = CLLocationManager()
    private let timeoutNanoseconds: UInt64
    private var continuation: CheckedContinuation<LocationFixCaptureResult, Error>?
    private var didFinish = false
    private var timeoutTask: Task<Void, Never>?
    private var isUpdating = false

    init(timeoutNanoseconds: UInt64) {
        self.timeoutNanoseconds = timeoutNanoseconds
    }

    func capture() async throws -> LocationFixCaptureResult {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            DispatchQueue.main.async {
                self.startOnMain()
            }
        }
    }

    @MainActor
    private func startOnMain() {
        guard !didFinish else { return }
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        // Distance filter 0 so the first fix is delivered promptly.
        manager.distanceFilter = kCLDistanceFilterNone

        // Do not synchronously call `locationServicesEnabled()` here: Apple
        // warns that it can block the main thread. Authorization is the
        // supported preflight and `locationManagerDidChangeAuthorization`
        // is the authoritative callback after the user responds.
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            beginLocationUpdates()
        case .notDetermined:
            // Timeout starts only after we actually request a fix
            // (see authorization callback) so the permission sheet
            // does not consume the budget.
            manager.requestWhenInUseAuthorization()
        case .denied:
            finish(.failure(LocationSamplingError.permissionDenied))
        case .restricted:
            finish(.failure(LocationSamplingError.permissionRestricted))
        @unknown default:
            finish(.failure(LocationSamplingError.failed))
        }
    }

    @MainActor
    private func beginLocationUpdates() {
        guard !didFinish, !isUpdating else { return }
        isUpdating = true
        scheduleTimeout()

        if let cached = manager.location {
            let coordinate = Self.coordinate(from: cached)
            let age = Date().timeIntervalSince(cached.timestamp)
            #if targetEnvironment(simulator)
            let acceptCached = coordinate.isValid
            #else
            let acceptCached = coordinate.isValid && age <= Self.cachedFixMaxAge
            #endif
            if acceptCached {
                finish(.success(Self.makeResult(from: cached, source: .cached)))
                return
            }
        }

        manager.startUpdatingLocation()
    }

    private func scheduleTimeout() {
        timeoutTask?.cancel()
        let nanoseconds = timeoutNanoseconds
        timeoutTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: nanoseconds)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.finish(.failure(LocationSamplingError.timedOut))
            }
        }
    }

    private func finish(_ result: Result<LocationFixCaptureResult, Error>) {
        guard !didFinish else { return }
        didFinish = true
        timeoutTask?.cancel()
        timeoutTask = nil
        if isUpdating {
            manager.stopUpdatingLocation()
            isUpdating = false
        }
        manager.delegate = nil
        continuation?.resume(with: result)
        continuation = nil
    }

    private static func coordinate(from location: CLLocation) -> LocationCoordinate {
        LocationCoordinate(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            accuracy: location.horizontalAccuracy >= 0 ? location.horizontalAccuracy : nil
        )
    }

    private enum FixSource {
        case cached
        case live
    }

    private static func makeResult(from location: CLLocation, source: FixSource) -> LocationFixCaptureResult {
        let coordinate = coordinate(from: location)
        #if DEBUG
        let diagnosticSource: LocationSampleDiagnostics.Source = {
            switch source {
            case .cached:
                return .cached
            case .live:
                #if targetEnvironment(simulator)
                return .simulator
                #else
                return .realDevice
                #endif
            }
        }()
        return LocationFixCaptureResult(
            coordinate: coordinate,
            diagnostics: LocationSampleDiagnostics(
                source: diagnosticSource,
                capturedAt: location.timestamp,
                accuracyMeters: location.horizontalAccuracy >= 0 ? location.horizontalAccuracy : nil
            )
        )
        #else
        return LocationFixCaptureResult(coordinate: coordinate)
        #endif
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            Task { @MainActor in
                self.beginLocationUpdates()
            }
        case .denied:
            finish(.failure(LocationSamplingError.permissionDenied))
        case .restricted:
            finish(.failure(LocationSamplingError.permissionRestricted))
        case .notDetermined:
            break
        @unknown default:
            finish(.failure(LocationSamplingError.failed))
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        let coordinate = Self.coordinate(from: location)
        guard coordinate.isValid else { return }
        // Reject absurd first readings (Simulator sometimes reports
        // negative accuracy before a real fix).
        if let accuracy = coordinate.accuracy, accuracy > 2_000 {
            return
        }
        finish(.success(Self.makeResult(from: location, source: .live)))
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if let clError = error as? CLError {
            switch clError.code {
            case .denied:
                finish(.failure(LocationSamplingError.permissionDenied))
            case .locationUnknown:
                // Transient — keep waiting until timeout or a valid fix.
                // One-shot `requestLocation()` used to fail immediately here
                // on Simulator even when a custom location was set.
                return
            default:
                break
            }
        }
        // Non-recoverable failure path: still allow timeout to fire if we
        // already have updates running; only fail hard when not updating.
        if !isUpdating {
            finish(.failure(LocationSamplingError.failed))
        }
    }
}

enum TechnicianPlaceholderImage {
    static let pngData = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
}
