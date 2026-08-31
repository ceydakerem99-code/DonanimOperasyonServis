import Foundation

/// Drains the local SwiftData sync queue toward remote repositories.
///
/// Implementations must not talk to SwiftUI, must not open a
/// `ModelContext`, and must not import Firebase. Callers invoke this
/// manually (`syncPending()`); there is no launch/background
/// scheduler in this type. Phase 5G's `SyncLifecycleCoordinator`
/// is what invokes `syncPending()` from launch, foreground, network
/// recovery, and `BGAppRefreshTask`.
protocol SyncManaging: Sendable {
    @discardableResult
    func syncPending(now: Date) async throws -> SyncDrainOutcome
    func sync(operation: SyncOperation, now: Date) async throws
    /// Last drain timing report (nil before the first `syncPending`).
    func lastDrainReport() async -> SyncDrainReport?
    /// Live queue counts for the header badge. Independent of whether
    /// the last drain's telemetry counters (`failed` / `held`) changed.
    func issueSnapshot() async throws -> SyncIssueSnapshot
}

extension SyncManaging {
    @discardableResult
    func syncPending() async throws -> SyncDrainOutcome {
        try await syncPending(now: Date())
    }

    func sync(operation: SyncOperation) async throws {
        try await sync(operation: operation, now: Date())
    }
}
