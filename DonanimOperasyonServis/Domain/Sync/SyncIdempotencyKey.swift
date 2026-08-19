import Foundation

/// Stable key that the remote side can use to ignore a duplicate
/// apply of the same logical mutation.
///
/// Format: `{entityType}:{entityId}:{operationType}:v{localVersion}`
///
/// Retries of the **same** `SyncOperation` reuse this key. A new
/// mutation that bumps `localVersion` produces a different key.
/// Persistence uniqueness is a Phase 5B concern; Domain only
/// defines the invariant and the generator.
struct SyncIdempotencyKey: Hashable, Sendable, Codable {
    let rawValue: String

    init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    static func make(
        entityType: SyncEntityType,
        entityId: String,
        operationType: SyncOperationType,
        localVersion: Int
    ) -> SyncIdempotencyKey {
        SyncIdempotencyKey(
            "\(entityType.rawValue):\(entityId):\(operationType.rawValue):v\(localVersion)"
        )
    }
}

extension SyncIdempotencyKey: CustomStringConvertible {
    var description: String { rawValue }
}
