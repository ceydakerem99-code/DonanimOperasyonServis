import Foundation

/// In-memory `FirebaseStorageDataSource` used by unit tests and by
/// `DIContainer.mock()`. Stores `Data` blobs keyed by the canonical
/// `FirebaseStoragePath.rawValue`.
actor FakeFirebaseStorageDataSource: FirebaseStorageDataSource {

    private var blobs: [String: Data] = [:]

    init() {}

    @discardableResult
    func upload(data: Data, to path: FirebaseStoragePath) async throws -> String {
        blobs[path.rawValue] = data
        return path.rawValue
    }

    func download(from path: FirebaseStoragePath) async throws -> Data {
        guard let data = blobs[path.rawValue] else {
            throw FirebaseError.notFound
        }
        return data
    }

    func delete(_ path: FirebaseStoragePath) async throws {
        blobs.removeValue(forKey: path.rawValue)
    }

    /// Test helper: inspect stored blobs without going through
    /// `download`, which throws on a miss.
    func contains(_ path: FirebaseStoragePath) -> Bool {
        blobs[path.rawValue] != nil
    }
}
