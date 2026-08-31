import Foundation

/// Timing / outcome summary for one `syncPending` drain.
/// Used for DEBUG telemetry and progress UI — does not change sync behavior.
struct SyncDrainReport: Equatable, Sendable {
    enum OperationResult: String, Equatable, Sendable {
        case success
        case failed
        case retry
        case held
        case conflict
        case skipped
    }

    struct OperationTiming: Equatable, Sendable {
        let index: Int
        let total: Int
        let entityType: SyncEntityType
        let operationType: SyncOperationType
        let duration: TimeInterval
        let result: OperationResult
    }

    let startedAt: Date
    let finishedAt: Date
    let pendingAtStart: Int
    let succeeded: Int
    let failed: Int
    let retried: Int
    let held: Int
    let conflicts: Int
    let operations: [OperationTiming]
    let deferredOffline: Bool
    /// `.failed` rows with no scheduled retry, after stale prune.
    let activeFailedCount: Int
    /// `.failed` rows still inside retry backoff, after stale prune.
    let retryableFailedCount: Int

    var totalDuration: TimeInterval {
        finishedAt.timeIntervalSince(startedAt)
    }

    var summaryLine: String {
        if deferredOffline {
            return "Senkron çevrimdışı ertelendi"
        }
        if activeFailedCount > 0 {
            return "\(activeFailedCount) işlem senkronizasyon hatası"
        }
        if retryableFailedCount > 0 {
            return "\(retryableFailedCount) işlem senkronizasyon için bekliyor"
        }
        if succeeded > 0 {
            return "\(succeeded) işlem senkronize edildi"
        }
        return "Senkronize edilecek işlem yok"
    }

    var progressLabel: String {
        "\(succeeded + failed + conflicts + held) / \(max(pendingAtStart, 1))"
    }
}
