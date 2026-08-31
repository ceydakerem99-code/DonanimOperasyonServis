import Foundation
import Observation

/// Observable sync progress / last drain report for DEBUG and lightweight banners.
/// `@unchecked Sendable` so `LocalToRemoteSyncManager` can update it from its actor.
/// Mutations that the header badge reads are applied on the main actor.
@Observable
final class SyncProgressStore: @unchecked Sendable {
    private(set) var isSyncing = false
    private(set) var currentIndex = 0
    private(set) var currentTotal = 0
    private(set) var statusMessage: String?
    private(set) var lastReport: SyncDrainReport?
    /// Live queue counts. Badge reads this, not drain telemetry counters.
    private(set) var issueSnapshot: SyncIssueSnapshot?

    func begin(total: Int) {
        applyOnMain {
            self.isSyncing = true
            self.currentIndex = 0
            self.currentTotal = total
            self.statusMessage = total > 0
                ? "Senkronize ediliyor… 0 / \(total)"
                : "Senkronize ediliyor…"
        }
    }

    func updateProgress(index: Int, total: Int) {
        applyOnMain {
            self.currentIndex = index
            self.currentTotal = total
            self.statusMessage = "Senkronize ediliyor… \(index) / \(max(total, 1))"
        }
    }

    func finish(report: SyncDrainReport, snapshot: SyncIssueSnapshot? = nil) {
        let resolved = snapshot ?? SyncIssueSnapshot(from: report)
        applyOnMain {
            self.isSyncing = false
            self.lastReport = report
            self.issueSnapshot = resolved
            self.statusMessage = report.summaryLine
            self.currentIndex = report.pendingAtStart
            self.currentTotal = report.pendingAtStart
        }
    }

    func applySnapshot(_ snapshot: SyncIssueSnapshot) {
        applyOnMain {
            self.issueSnapshot = snapshot
            self.isSyncing = false
        }
    }

    func clearMessage() {
        applyOnMain {
            self.statusMessage = nil
        }
    }

    private func applyOnMain(_ work: @escaping () -> Void) {
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.async(execute: work)
        }
    }
}
