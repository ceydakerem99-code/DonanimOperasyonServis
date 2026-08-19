import Foundation

/// A GPS coordinate captured by a technician's device. Framework-
/// agnostic: does not depend on CoreLocation.
///
/// `accuracy` is expressed in meters as reported by the platform.
/// `nil` means the accuracy was not available at capture time.
struct LocationCoordinate: Hashable, Sendable, Codable {
    let latitude: Double
    let longitude: Double
    let accuracy: Double?

    init(latitude: Double, longitude: Double, accuracy: Double? = nil) {
        self.latitude = latitude
        self.longitude = longitude
        self.accuracy = accuracy
    }

    /// True when the numeric values are within valid WGS-84 ranges.
    var isValid: Bool {
        (-90.0...90.0).contains(latitude) &&
        (-180.0...180.0).contains(longitude)
    }
}
