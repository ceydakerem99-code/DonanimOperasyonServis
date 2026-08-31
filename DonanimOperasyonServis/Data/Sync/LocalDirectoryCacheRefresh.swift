import Foundation

/// Read-only remote directory refresh into local SwiftData cache.
/// Used by operator UI for technician/customer pickers and work-order lists (offline-first).
///
/// **Role source of truth:** UI reads Firestore `users/{uid}.role` (via local cache).
/// Realtime Gateway reads Firebase Auth ID token custom claims — keep both in sync
/// when provisioning users; this type does not write Auth claims.
struct LocalDirectoryCacheRefresh: Sendable {
    let localUsers: UserRepository
    let remoteUsers: UserRepository
    let localCustomers: CustomerRepository
    let remoteCustomers: CustomerRepository
    let localWorkOrders: WorkOrderRepository
    let remoteWorkOrders: WorkOrderRepository
    let localNotifications: NotificationRepository
    let remoteNotifications: NotificationRepository
    let syncOperationRepository: SyncOperationRepository
    let reconciliationEngine: any Reconciling
    let networkReachability: NetworkReachabilityProviding

    private static let technicianRefreshGate = TechnicianAssignmentRefreshGate()
    private static let customerRefreshConcurrency = 5

    /// Pulls all users from Firestore and upserts into local SwiftData for admin directory views.
    /// No-op when offline. Remote failures are logged and do not mutate local cache.
    func refreshUsers() async {
        guard await networkReachability.isReachable else { return }
        do {
            let remoteList = try await remoteUsers.list(role: nil, isActive: nil)
            for user in remoteList {
                try await localUsers.save(user)
            }
        } catch {
            AppLogger.app.warning("User directory refresh failed: \(error)")
        }
    }

    /// Pulls active technicians from Firestore and upserts into local SwiftData.
    /// No-op when offline. Remote failures are logged and do not mutate local cache.
    func refreshTechnicians() async {
        guard await networkReachability.isReachable else { return }
        do {
            let remoteTechnicians = try await remoteUsers.list(role: .technician, isActive: true)
            for user in remoteTechnicians {
                try await localUsers.save(user)
            }
        } catch {
            AppLogger.app.warning("Technician directory refresh failed: \(error)")
        }
    }

    /// Pulls customers from Firestore and upserts into local SwiftData when no
    /// pending local mutation exists for that customer id.
    func refreshCustomers() async {
        guard await networkReachability.isReachable else { return }
        do {
            let remoteList = try await remoteCustomers.list(searchText: nil)
            for customer in remoteList {
                if await hasPendingCustomerMutation(entityId: customer.id.rawValue) {
                    continue
                }
                try await localCustomers.save(customer)
            }
        } catch {
            AppLogger.app.warning("Customer directory refresh failed: \(error)")
        }
    }

    /// Pulls work orders from Firestore and merges into local SwiftData.
    ///
    /// - New remote rows (no local record, no pending mutation): insert-only.
    /// - Existing local rows: reconciled via `ReconciliationEngine` — never blind upsert.
    /// - No `remoteVersion` is assumed; version-unknown updates stay local or become conflicts.
    func refreshWorkOrders(filter: WorkOrderFilter = .all) async {
        guard await networkReachability.isReachable else { return }
        do {
            let remoteList = try await remoteWorkOrders.list(filter: filter)
            for remoteOrder in remoteList {
                await reconcileRemoteWorkOrder(remoteOrder)
            }
        } catch {
            AppLogger.app.warning("Work order directory refresh failed: \(error)")
        }
    }

    /// Technician-scoped directory refresh: assigned work orders plus referenced customers.
    ///
    /// Technicians may `get` individual customers but cannot list the full customer
    /// collection in Firestore rules, so customers are fetched by id from assigned orders.
    /// No-op when offline. Missing/orphan customers are skipped without failing the refresh.
    /// Concurrent callers for the same technician share one in-flight refresh.
    func refreshTechnicianAssignments(technicianId: UserID) async {
        guard await networkReachability.isReachable else { return }
        await Self.technicianRefreshGate.run(technicianId: technicianId) {
            await self.performTechnicianAssignmentsRefresh(technicianId: technicianId)
        }
    }

    /// Pulls notifications for the signed-in user from Firestore into local cache.
    /// No-op when offline. Remote failures are logged and do not mutate local cache.
    func refreshNotifications(recipientUserId: UserID) async {
        guard await networkReachability.isReachable else { return }
        do {
            let remoteList = try await remoteNotifications.list(for: recipientUserId, unreadOnly: false)
            let localList = try await localNotifications.list(for: recipientUserId, unreadOnly: false)
            let localByID = Dictionary(uniqueKeysWithValues: localList.map { ($0.id, $0) })
            for notification in remoteList {
                if await hasPendingNotificationMutation(entityId: notification.id.rawValue) {
                    continue
                }
                if let local = localByID[notification.id], local.isRead, !notification.isRead {
                    var merged = notification
                    merged.isRead = true
                    try await localNotifications.save(merged)
                    continue
                }
                try await localNotifications.save(notification)
            }
        } catch {
            AppLogger.app.warning("Notification directory refresh failed: \(error)")
        }
    }

    // MARK: - Technician refresh

    private func performTechnicianAssignmentsRefresh(technicianId: UserID) async {
        #if DEBUG
        let started = ContinuousClock.now
        AppLogger.app.info("TECH REFRESH START technicianId=\(technicianId.rawValue, privacy: .public)")
        #endif

        var workOrderCount = 0
        var customersFetched = 0
        var customersMissing = 0

        do {
            let remoteList = try await remoteWorkOrders.list(
                filter: WorkOrderFilter(assignedTechnicianId: technicianId)
            )
            workOrderCount = remoteList.count
            for remoteOrder in remoteList {
                await reconcileRemoteWorkOrder(remoteOrder, preferRemoteWhenIdle: true)
            }

            let orders = try await localWorkOrders.list(
                filter: WorkOrderFilter(assignedTechnicianId: technicianId)
            )
            let customerIds = Set(orders.map(\.customerId))
            let stats = await refreshCustomersBounded(Array(customerIds))
            customersFetched = stats.fetched
            customersMissing = stats.missing
        } catch {
            AppLogger.app.warning("Technician customer directory refresh failed: \(error)")
        }

        #if DEBUG
        let durationMs = started.duration(to: .now).milliseconds
        AppLogger.app.info(
            "TECH REFRESH END durationMs=\(durationMs) workOrders=\(workOrderCount) customersFetched=\(customersFetched) missing=\(customersMissing)"
        )
        #endif
    }

    private func refreshCustomersBounded(_ customerIds: [CustomerID]) async -> (fetched: Int, missing: Int) {
        guard !customerIds.isEmpty else { return (0, 0) }

        var fetched = 0
        var missing = 0
        let limit = Self.customerRefreshConcurrency
        var index = 0

        await withTaskGroup(of: (Bool, Bool).self) { group in
            func addTask(for customerId: CustomerID) {
                group.addTask {
                    await self.refreshCustomerIfPresent(customerId)
                }
            }

            while index < min(limit, customerIds.count) {
                addTask(for: customerIds[index])
                index &+= 1
            }

            while let result = await group.next() {
                if result.0 { fetched &+= 1 }
                if result.1 { missing &+= 1 }
                if index < customerIds.count {
                    addTask(for: customerIds[index])
                    index &+= 1
                }
            }
        }

        return (fetched, missing)
    }

    // MARK: - Work orders

    private func reconcileRemoteWorkOrder(
        _ remoteOrder: WorkOrder,
        preferRemoteWhenIdle: Bool = false
    ) async {
        let entityId = remoteOrder.id.rawValue
        let localExists = await localWorkOrderExists(id: remoteOrder.id)
        let hasPending = await hasPendingWorkOrderMutation(entityId: entityId)

        if !localExists {
            guard !hasPending else { return }
            do {
                try await localWorkOrders.save(remoteOrder)
            } catch {
                AppLogger.app.warning("Work order insert failed for \(entityId): \(error)")
            }
            return
        }

        if preferRemoteWhenIdle, !hasPending {
            do {
                try await localWorkOrders.save(remoteOrder)
            } catch {
                AppLogger.app.warning("Work order directory save failed for \(entityId): \(error)")
            }
            return
        }

        let request = ReconciliationRequest(
            entityType: .workOrder,
            entityId: entityId,
            versions: .unknown
        )
        do {
            _ = try await reconciliationEngine.reconcile(
                request,
                prefetchedRemote: ReconciledRecord.workOrder(remoteOrder),
                now: Date()
            )
        } catch {
            AppLogger.app.warning("Work order reconcile failed for \(entityId): \(error)")
        }
    }

    private func localWorkOrderExists(id: WorkOrderID) async -> Bool {
        do {
            _ = try await localWorkOrders.fetch(id: id)
            return true
        } catch let error as DomainError {
            if case .notFound = error { return false }
            return false
        } catch {
            return false
        }
    }

    private func localCustomerExists(id: CustomerID) async -> Bool {
        do {
            _ = try await localCustomers.fetch(id: id)
            return true
        } catch let error as DomainError {
            if case .notFound = error { return false }
            return false
        } catch {
            return false
        }
    }

    private func hasPendingCustomerMutation(entityId: String) async -> Bool {
        guard let operations = try? await syncOperationRepository.list(
            entityType: .customer,
            entityId: entityId
        ) else {
            return false
        }
        return operations.contains { $0.status != .succeeded }
    }

    private func hasPendingWorkOrderMutation(entityId: String) async -> Bool {
        guard let operations = try? await syncOperationRepository.list(
            entityType: .workOrder,
            entityId: entityId
        ) else {
            return false
        }
        return operations.contains { $0.status != .succeeded }
    }

    private func hasPendingNotificationMutation(entityId: String) async -> Bool {
        guard let operations = try? await syncOperationRepository.list(
            entityType: .notification,
            entityId: entityId
        ) else {
            return false
        }
        return operations.contains { $0.status != .succeeded }
    }

    /// Returns `(fetchedFromRemote, missingRemote)`.
    private func refreshCustomerIfPresent(_ customerId: CustomerID) async -> (Bool, Bool) {
        if await hasPendingCustomerMutation(entityId: customerId.rawValue) {
            return (false, false)
        }
        if await localCustomerExists(id: customerId) {
            return (false, false)
        }
        do {
            let customer = try await remoteCustomers.fetch(id: customerId)
            try await localCustomers.save(customer)
            return (true, false)
        } catch let error as DomainError {
            if case .notFound = error {
                AppLogger.app.warning(
                    "Technician customer refresh skipped for \(customerId.rawValue, privacy: .public): \(error)"
                )
                return (false, true)
            }
            AppLogger.app.warning(
                "Technician customer refresh skipped for \(customerId.rawValue, privacy: .public): \(error)"
            )
            return (false, false)
        } catch {
            AppLogger.app.warning(
                "Technician customer refresh skipped for \(customerId.rawValue, privacy: .public): \(error)"
            )
            return (false, false)
        }
    }
}

// MARK: - In-flight coalescing

private actor TechnicianAssignmentRefreshGate {
    private var inFlight: [String: Task<Void, Never>] = [:]

    func run(technicianId: UserID, operation: @Sendable @escaping () async -> Void) async {
        let key = technicianId.rawValue
        if let existing = inFlight[key] {
            #if DEBUG
            AppLogger.app.info("TECH REFRESH JOIN reason=inFlight technicianId=\(key, privacy: .public)")
            #endif
            await existing.value
            return
        }

        let task = Task {
            await operation()
        }
        inFlight[key] = task
        await task.value
        inFlight[key] = nil
    }
}

#if DEBUG
private extension Duration {
    var milliseconds: Int64 {
        let components = components
        return Int64(components.seconds) * 1000 + Int64(components.attoseconds / 1_000_000_000_000_000)
    }
}
#endif
