import Foundation

protocol LocationSampling: Sendable {
    func sample() async throws -> LocationCoordinate
}

struct CoreLocationSampler: LocationSampling {
    func sample() async throws -> LocationCoordinate {
        LocationCoordinate(latitude: 41.0082, longitude: 28.9784, accuracy: 10)
    }
}

struct FixedLocationSampler: LocationSampling, Sendable {
    let coordinate: LocationCoordinate

    func sample() async throws -> LocationCoordinate { coordinate }
}

enum TechnicianPlaceholderImage {
    static let pngData = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
}
