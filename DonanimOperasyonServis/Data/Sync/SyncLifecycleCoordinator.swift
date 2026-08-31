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
    private let progressStore: SyncProgressStore?

    private var drainInFlight = false
    private var lastDrainAt: Date?
    private var observationTask: Task<Void, Never>?
    private var acquireWaiters: [CheckedContinuation<Void, Never>] = []
    /// Set when a reachability online event arrives while another drain is active.
    private var pendingNetworkReachableDrain = false

    init(
        syncManager: any SyncManaging,
        recovery: any SyncRecoveryHandling,
        reachability: any NetworkReachabilityProviding,
        scheduler: any BackgroundSyncScheduling,
        coalescingInterval: TimeInterval = 2,
        progressStore: SyncProgressStore? = nil
    ) {
        self.syncManager = syncManager
        self.recovery = recovery
        self.reachability = reachability
        self.scheduler = scheduler
        self.coalescingInterval = coalescingInterval
        self.progressStore = progressStore
    }

    func startObservingReachability() async {
        guard observationTask == nil else { return }
        let stream = await reachability.reachabilityUpdates()
        observationTask = Task { [weak self] in
            var previous: Bool?
            for await reachable in stream {
                let was = previous
                previous = reachable
                AppLogger.sync.info(
                    "SYNC AUTO-DRAIN reachability event was=\(String(describing: was), privacy: .public) now=\(reachable, privacy: .public)"
                )
                if was == false, reachable {
                    await self?.handleNetworkBecameReachable(now: Date(), source: "reachabilityStream")
                }
            }
        }
    }

    func handleLaunch(now: Date) async {
        await waitAcquire()
        defer { release() }
        let recovered = await runRecovery(now: now)
        if recovered.isEmpty && shouldSkipBecomeActive(now: now) {
            await publishIssueSnapshot()
            scheduler.scheduleNext()
            return
        }
        await runDrain(now: now)
        scheduler.scheduleNext()
    }

    func handleBecomeActive(now: Date) async {
        guard acquire() else { return }
        defer { release() }
        if shouldSkipBecomeActive(now: now) {
            await publishIssueSnapshot()
            return
        }
        await runDrain(now: now)
    }

    func handleNetworkBecameReachable(now: Date) async {
        await handleNetworkBecameReachable(now: now, source: "explicit")
    }

    private func handleNetworkBecameReachable(now: Date, source: String) async {
        let online = await reachability.isReachable
        AppLogger.sync.info(
            "SYNC AUTO-DRAIN START source=\(source, privacy: .public) isReachable=\(online, privacy: .public) drainInFlight=\(self.drainInFlight, privacy: .public)"
        )
        guard online else {
            AppLogger.sync.info(
                "SYNC AUTO-DRAIN SKIP reason=reachabilityStillOffline source=\(source, privacy: .public)"
            )
            return
        }
        if !acquire() {
            pendingNetworkReachableDrain = true
            AppLogger.sync.info(
                "SYNC AUTO-DRAIN SKIP reason=drainInFlightDeferred source=\(source, privacy: .public)"
            )
            return
        }
        defer { release() }
        _ = await runRecovery(now: now)
        await runDrain(now: now, source: source)
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
            await markDrainStarted()
            _ = try await syncManager.syncPending(now: now)
            await publishLastReport()
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
        if pendingNetworkReachableDrain {
            pendingNetworkReachableDrain = false
            AppLogger.sync.info("SYNC AUTO-DRAIN START source=deferredAfterInFlightDrain")
            Task { await self.handleNetworkBecameReachable(now: Date(), source: "deferredAfterInFlightDrain") }
        }
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

    private func runDrain(now: Date, source: String = "lifecycle") async {
        do {
            await markDrainStarted()
            let outcome = try await syncManager.syncPending(now: now)
            await publishLastReport()
            lastDrainAt = now
            AppLogger.sync.info(
                "SYNC AUTO-DRAIN SUCCESS source=\(source, privacy: .public) outcome=\(outcome.logLabel, privacy: .public)"
            )
        } catch {
            AppLogger.sync.error(
                "SYNC AUTO-DRAIN FAIL source=\(source, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
            )
            lastDrainAt = now
        }
    }

    private func markDrainStarted() async {
        progressStore?.begin(total: 0)
    }

    func refreshProgressSnapshot() async {
        await publishIssueSnapshot()
    }

    private func publishLastReport() async {
        guard let progressStore else { return }
        let report = await syncManager.lastDrainReport()
        let snapshot = try? await syncManager.issueSnapshot()
        await MainActor.run {
            if let report {
                progressStore.finish(report: report, snapshot: snapshot)
            } else if let snapshot {
                progressStore.applySnapshot(snapshot)
            }
        }
    }

    private func publishIssueSnapshot() async {
        guard let progressStore else { return }
        guard let snapshot = try? await syncManager.issueSnapshot() else { return }
        await MainActor.run {
            progressStore.applySnapshot(snapshot)
        }
    }
}
