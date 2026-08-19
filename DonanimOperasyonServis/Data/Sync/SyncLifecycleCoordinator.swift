import Foundation

/// Serializes lifecycle / network / background triggers onto one
/// `syncPending()` drain at a time. Overlapping become-active /
/// network / background events are dropped rather than queued.
/// Launch waits for an in-flight drain so recovery is never skipped,
/// then coalesces a second drain when the previous one was recent
/// and recovery produced no interrupted rows.
actor SyncLifecycleCoordinator: SyncLifecycleCoordinating {

    private let syncManager: any SyncManaging
    private let recovery: any SyncRecoveryHandling
    private let reachability: any NetworkReachabilityProviding
    private let scheduler: any BackgroundSyncScheduling
    private let coalescingInterval: TimeInterval

    private var drainInFlight = false
    private var lastDrainAt: Date?
    private var observationTask: Task<Void, Never>?
    private var acquireWaiters: [CheckedContinuation<Void, Never>] = []

    init(
        syncManager: any SyncManaging,
        recovery: any SyncRecoveryHandling,
        reachability: any NetworkReachabilityProviding,
        scheduler: any BackgroundSyncScheduling,
        coalescingInterval: TimeInterval = 2
    ) {
        self.syncManager = syncManager
        self.recovery = recovery
        self.reachability = reachability
        self.scheduler = scheduler
        self.coalescingInterval = coalescingInterval
    }

    func startObservingReachability() async {
        guard observationTask == nil else { return }
        let stream = await reachability.reachabilityUpdates()
        observationTask = Task { [weak self] in
            var previous: Bool?
            for await reachable in stream {
                let was = previous
                previous = reachable
                if was == false, reachable {
                    await self?.handleNetworkBecameReachable(now: Date())
                }
            }
        }
    }

    func handleLaunch(now: Date) async {
        await waitAcquire()
        defer { release() }
        let recovered = await runRecovery(now: now)
        if recovered.isEmpty && shouldSkipBecomeActive(now: now) {
            scheduler.scheduleNext()
            return
        }
        await runDrain(now: now)
        scheduler.scheduleNext()
    }

    func handleBecomeActive(now: Date) async {
        guard acquire() else { return }
        defer { release() }
        if shouldSkipBecomeActive(now: now) { return }
        await runDrain(now: now)
    }

    func handleNetworkBecameReachable(now: Date) async {
        guard acquire() else { return }
        defer { release() }
        await runDrain(now: now)
    }

    func handleBackgroundTask(
        _ task: any BackgroundSyncTaskHandle,
        now: Date
    ) async {
        scheduler.scheduleNext()
        guard acquire() else {
            task.complete(success: true)
            return
        }
        defer { release() }
        do {
            _ = try await syncManager.syncPending(now: now)
            lastDrainAt = now
            task.complete(success: true)
        } catch {
            AppLogger.sync.error(
                "Background syncPending failed: \(error.localizedDescription, privacy: .public)"
            )
            task.complete(success: false)
        }
    }

    // MARK: - Drain

    private func acquire() -> Bool {
        if drainInFlight { return false }
        drainInFlight = true
        return true
    }

    /// Launch waits so recovery is never dropped behind an in-flight
    /// foreground drain. Other triggers still fail-fast via `acquire()`.
    private func waitAcquire() async {
        if !drainInFlight {
            drainInFlight = true
            return
        }
        await withCheckedContinuation { continuation in
            acquireWaiters.append(continuation)
        }
    }

    private func release() {
        if !acquireWaiters.isEmpty {
            let waiter = acquireWaiters.removeFirst()
            waiter.resume()
            return
        }
        drainInFlight = false
    }

    private func shouldSkipBecomeActive(now: Date) -> Bool {
        guard let lastDrainAt else { return false }
        return now.timeIntervalSince(lastDrainAt) < coalescingInterval
    }

    private func runRecovery(now: Date) async -> [SyncOperationID] {
        do {
            let outcome = try await recovery.recoverInterruptedOperations(now: now)
            return outcome.recoveredOperationIDs
        } catch {
            AppLogger.sync.error(
                "Launch recovery failed: \(error.localizedDescription, privacy: .public)"
            )
            return []
        }
    }

    private func runDrain(now: Date) async {
        do {
            _ = try await syncManager.syncPending(now: now)
            lastDrainAt = now
        } catch {
            AppLogger.sync.error(
                "Lifecycle syncPending failed: \(error.localizedDescription, privacy: .public)"
            )
            lastDrainAt = now
        }
    }
}
