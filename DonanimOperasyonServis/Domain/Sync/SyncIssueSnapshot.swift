import Foundation

/// Live queue counts for the header badge. Distinct from drain
/// telemetry (`SyncDrainReport.failed` / `held` / `retried`) so a
/// cached drain report cannot keep showing a stale error total.
struct SyncIssueSnapshot: Equatable, Sendable {
    var activeFailedCount: Int
    var retryableFailedCount: Int
    var pendingCount: Int
    var succeededCount: Int
    var conflictCount: Int
    var updatedAt: Date

    static func empty(at date: Date = Date()) -> SyncIssueSnapshot {
        SyncIssueSnapshot(
            activeFailedCount: 0,
            retryableFailedCount: 0,
            pendingCount: 0,
            succeededCount: 0,
            conflictCount: 0,
            updatedAt: date
        )
    }

    init(
        activeFailedCount: Int,
        retryableFailedCount: Int,
        pendingCount: Int,
        succeededCount: Int,
        conflictCount: Int,
        updatedAt: Date
    ) {
        self.activeFailedCount = activeFailedCount
        self.retryableFailedCount = retryableFailedCount
        self.pendingCount = pendingCount
        self.succeededCount = succeededCount
        self.conflictCount = conflictCount
        self.updatedAt = updatedAt
    }

    init(from report: SyncDrainReport) {
        self.init(
            activeFailedCount: report.activeFailedCount,
            retryableFailedCount: report.retryableFailedCount,
            pendingCount: 0,
            succeededCount: 0,
            conflictCount: report.conflicts,
            updatedAt: report.finishedAt
        )
    }
}
