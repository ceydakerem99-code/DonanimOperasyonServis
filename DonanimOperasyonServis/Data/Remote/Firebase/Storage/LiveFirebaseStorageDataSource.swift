import Foundation
import FirebaseStorage

/// `FirebaseStorageDataSource` backed by the real Firebase Storage
/// SDK.
///
/// - Concurrency: `Storage` / `StorageReference` are documented as
///   thread-safe but are not marked `Sendable` in Swift 6, hence
///   `@unchecked Sendable`. We hold a single `Storage` instance.
/// - Errors: SDK errors are mapped to `FirebaseError.storageError`
///   (or `.notFound` for missing objects) so the raw `NSError` never
///   leaks upward.
final class LiveFirebaseStorageDataSource: FirebaseStorageDataSource, @unchecked Sendable {

    private let storage: Storage

    init(storage: Storage = .storage()) {
        self.storage = storage
    }

    @discardableResult
    func upload(data: Data, to path: FirebaseStoragePath) async throws -> String {
        let ref = storage.reference(withPath: path.rawValue)
        do {
            _ = try await ref.putDataAsync(data)
            return path.rawValue
        } catch {
            throw FirebaseError.storageError(reason: error.localizedDescription)
        }
    }

    func download(from path: FirebaseStoragePath) async throws -> Data {
        let ref = storage.reference(withPath: path.rawValue)
        do {
            return try await ref.data(maxSize: Self.maxDownloadSize)
        } catch {
            let nsError = error as NSError
            if nsError.domain == StorageErrorDomain,
               nsError.code == StorageErrorCode.objectNotFound.rawValue {
                throw FirebaseError.notFound
            }
            throw FirebaseError.storageError(reason: error.localizedDescription)
        }
    }

    func delete(_ path: FirebaseStoragePath) async throws {
        let ref = storage.reference(withPath: path.rawValue)
        do {
            try await ref.delete()
        } catch {
            let nsError = error as NSError
            if nsError.domain == StorageErrorDomain,
               nsError.code == StorageErrorCode.objectNotFound.rawValue {
                return
            }
            throw FirebaseError.storageError(reason: error.localizedDescription)
        }
    }

    /// Hard cap so a runaway download cannot exhaust device memory.
    /// Photos/signatures in this app are well below this bound.
    private static let maxDownloadSize: Int64 = 32 * 1_024 * 1_024
}
