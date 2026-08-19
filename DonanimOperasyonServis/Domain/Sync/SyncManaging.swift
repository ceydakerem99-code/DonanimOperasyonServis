import Foundation

/// Drains the local SwiftData sync queue toward remote repositories.
///
/// Implementations must not talk to SwiftUI, must not open a
/// `ModelContext`, and must not import Firebase. Callers invoke this
/// manually (`syncPending()`); there is no launch/background
/// scheduler in Phase 5C.
protocol SyncManaging: Sendable {
    func syncPending(now: Date) async throws
    func sync(operation: SyncOperation, now: Date) async throws
}

extension SyncManaging {
    func syncPending() async throws {
        try await syncPending(now: Date())
    }

    func sync(operation: SyncOperation) async throws {
        try await sync(operation: operation, now: Date())
    }
}
