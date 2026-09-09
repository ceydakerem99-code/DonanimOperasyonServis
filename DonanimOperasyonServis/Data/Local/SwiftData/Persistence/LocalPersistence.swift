import Foundation
import SwiftData

/// Central, actor-isolated wrapper around the app's SwiftData
/// `ModelContext`.
///
/// Every persistence read and write in the app funnels through
/// `LocalPersistence`. Doing so has two important properties:
///
/// 1. **Concurrency safety.** `ModelContext` is not `Sendable`;
///    exposing it directly to callers would require pervasive
///    `@MainActor` isolation or unsafe workarounds. Wrapping it in
///    a single `@ModelActor` gives us a natural serial executor for
///    all SwiftData work.
///
/// 2. **Consistency.** All Data-layer repositories share the same
///    underlying `ModelContext`, so a save from one repository is
///    immediately visible to the next repository's fetch — no
///    cross-context cache-refresh dance. This matches the Phase 3
///    requirement that a work order and its status history stay
///    consistent even though they are written through separate
///    repository types.
///
/// The API is intentionally domain-facing: every method takes and
/// returns Domain types. Domain never sees a `@Model` class or a
/// `ModelContext`.
@ModelActor
actor LocalPersistence {

    // MARK: - User



    func fetchUser(id: String) throws -> User? {
        let model = try firstModel(UserModel.self, where: #Predicate { $0.id == id })
        return try model.map { try requireDecoded($0.toDomain(), entity: "User") }
    }

    func findUserByEmail(_ email: String) throws -> User? {
        let model = try firstModel(UserModel.self, where: #Predicate { $0.email == email })
        return try model.map { try requireDecoded($0.toDomain(), entity: "User") }
    }

    func listUsers() throws -> [User] {
        try modelContext
            .fetch(FetchDescriptor<UserModel>(sortBy: [SortDescriptor(\.fullName)]))
            .compactMap { $0.toDomain() }
    }

    func upsertUser(_ user: User) throws {
        let rawId = user.id.rawValue
        if let existing = try firstModel(UserModel.self, where: #Predicate { $0.id == rawId }) {
            existing.apply(domain: user)
        } else {
            modelContext.insert(UserModel(domain: user))
        }
        try modelContext.save()
    }

    func deleteUser(id: String) throws {
        guard let model = try firstModel(UserModel.self, where: #Predicate { $0.id == id })
        else { return }
        modelContext.delete(model)
        try modelContext.save()
    }

    // MARK: - Customer

    func fetchCustomer(id: String) throws -> Customer? {
        try firstModel(CustomerModel.self, where: #Predicate { $0.id == id })?.toDomain()
    }

    func listCustomers(searchText: String?) throws -> [Customer] {
        let all = try modelContext.fetch(
            FetchDescriptor<CustomerModel>(sortBy: [SortDescriptor(\.name)])
        )
        guard let raw = searchText?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(), !raw.isEmpty
        else {
            return all.map { $0.toDomain() }
        }
        return all
            .filter { CustomerSearchFilter.matches($0.toDomain(), query: raw) }
            .map { $0.toDomain() }
    }

    func upsertCustomer(_ customer: Customer) throws {
        let rawId = customer.id.rawValue
        if let existing = try firstModel(CustomerModel.self, where: #Predicate { $0.id == rawId }) {
            existing.apply(domain: customer)
        } else {
            modelContext.insert(CustomerModel(domain: customer))
        }
        try modelContext.save()
    }

    func deleteCustomer(id: String) throws {
        guard let model = try firstModel(CustomerModel.self, where: #Predicate { $0.id == id })
        else { return }
        modelContext.delete(model)
        try modelContext.save()
    }

    // MARK: - WorkOrderTemplate

    func fetchWorkOrderTemplate(id: String) throws -> WorkOrderTemplate? {
        let model = try firstModel(WorkOrderTemplateModel.self, where: #Predicate { $0.id == id })
        return try model.map { try requireDecoded($0.toDomain(), entity: "WorkOrderTemplate") }
    }

    func listWorkOrderTemplates(createdByUserId: String) throws -> [WorkOrderTemplate] {
        try modelContext
            .fetch(
                FetchDescriptor<WorkOrderTemplateModel>(
                    predicate: #Predicate { $0.createdByUserId == createdByUserId },
                    sortBy: [SortDescriptor(\.name)]
                )
            )
            .compactMap { $0.toDomain() }
    }

    func upsertWorkOrderTemplate(_ template: WorkOrderTemplate) throws {
        let rawId = template.id.rawValue
        if let existing = try firstModel(WorkOrderTemplateModel.self, where: #Predicate { $0.id == rawId }) {
            existing.apply(domain: template)
        } else {
            modelContext.insert(WorkOrderTemplateModel(domain: template))
        }
        try modelContext.save()
    }

    func deleteWorkOrderTemplate(id: String) throws {
        guard let model = try firstModel(WorkOrderTemplateModel.self, where: #Predicate { $0.id == id })
        else { return }
        modelContext.delete(model)
        try modelContext.save()
    }

    // MARK: - WorkOrder

    func fetchWorkOrder(id: String) throws -> WorkOrder? {
        let model = try firstModel(WorkOrderModel.self, where: #Predicate { $0.id == id })
        return try model.map { try requireDecoded($0.toDomain(), entity: "WorkOrder") }
    }

    func listWorkOrders(filter: WorkOrderFilter) throws -> [WorkOrder] {
        let all = try modelContext
            .fetch(FetchDescriptor<WorkOrderModel>(sortBy: [SortDescriptor(\.scheduledDate)]))
            .compactMap { $0.toDomain() }
        return all.filter { order in
            if let value = filter.status,               order.status != value               { return false }
            if let value = filter.priority,             order.priority != value             { return false }
            if let value = filter.workType,             order.workType != value             { return false }
            if let value = filter.assignedTechnicianId, order.assignedTechnicianId != value { return false }
            if let value = filter.createdByUserId,      order.createdByUserId != value      { return false }
            if let value = filter.customerId,           order.customerId != value           { return false }
            if let from = filter.scheduledFrom, order.scheduledDate < from { return false }
            if let to   = filter.scheduledTo,   order.scheduledDate > to   { return false }
            return true
        }
    }

    func upsertWorkOrder(_ workOrder: WorkOrder) throws {
        let rawId = workOrder.id.rawValue
        if let existing = try firstModel(WorkOrderModel.self, where: #Predicate { $0.id == rawId }) {
            existing.apply(domain: workOrder)
        } else {
            modelContext.insert(WorkOrderModel(domain: workOrder))
        }
        try modelContext.save()
    }

    func deleteWorkOrder(id: String) throws {
        guard let model = try firstModel(WorkOrderModel.self, where: #Predicate { $0.id == id })
        else { return }
        modelContext.delete(model)
        try modelContext.save()
    }

    // MARK: - WorkOrder children (notes / photos / locations / history / signatures)

    func listNotes(workOrderId: String) throws -> [WorkOrderNote] {
        try modelContext
            .fetch(FetchDescriptor<WorkOrderNoteModel>(
                predicate: #Predicate { $0.workOrderId == workOrderId },
                sortBy: [SortDescriptor(\.createdAt)]
            ))
            .map { $0.toDomain() }
    }

    func upsertNote(_ note: WorkOrderNote) throws {
        let noteId = note.id
        let woId   = note.workOrderId.rawValue
        if let existing = try firstModel(WorkOrderNoteModel.self, where: #Predicate { $0.id == noteId }) {
            existing.apply(domain: note)
        } else {
            let model = WorkOrderNoteModel(domain: note)
            model.workOrder = try firstModel(WorkOrderModel.self, where: #Predicate { $0.id == woId })
            modelContext.insert(model)
        }
        try modelContext.save()
    }

    func deleteNote(id: String) throws {
        guard let model = try firstModel(WorkOrderNoteModel.self, where: #Predicate { $0.id == id })
        else { return }
        modelContext.delete(model)
        try modelContext.save()
    }

    func listPhotos(workOrderId: String) throws -> [WorkOrderPhoto] {
        try modelContext
            .fetch(FetchDescriptor<WorkOrderPhotoModel>(
                predicate: #Predicate { $0.workOrderId == workOrderId },
                sortBy: [SortDescriptor(\.capturedAt)]
            ))
            .compactMap { $0.toDomain() }
    }

    func upsertPhoto(_ photo: WorkOrderPhoto) throws {
        let photoId = photo.id
        let woId    = photo.workOrderId.rawValue
        if let existing = try firstModel(WorkOrderPhotoModel.self, where: #Predicate { $0.id == photoId }) {
            existing.apply(domain: photo)
        } else {
            let model = WorkOrderPhotoModel(domain: photo)
            model.workOrder = try firstModel(WorkOrderModel.self, where: #Predicate { $0.id == woId })
            modelContext.insert(model)
        }
        try modelContext.save()
    }

    func deletePhoto(id: String) throws {
        guard let model = try firstModel(WorkOrderPhotoModel.self, where: #Predicate { $0.id == id })
        else { return }
        modelContext.delete(model)
        try modelContext.save()
    }

    func listLocations(workOrderId: String) throws -> [WorkOrderLocation] {
        try modelContext
            .fetch(FetchDescriptor<WorkOrderLocationModel>(
                predicate: #Predicate { $0.workOrderId == workOrderId },
                sortBy: [SortDescriptor(\.capturedAt)]
            ))
            .compactMap { $0.toDomain() }
    }

    func insertLocation(_ location: WorkOrderLocation) throws {
        let woId = location.workOrderId.rawValue
        let model = WorkOrderLocationModel(domain: location)
        model.workOrder = try firstModel(WorkOrderModel.self, where: #Predicate { $0.id == woId })
        modelContext.insert(model)
        try modelContext.save()
    }

    func listStatusHistory(workOrderId: String) throws -> [WorkOrderStatusHistory] {
        try modelContext
            .fetch(FetchDescriptor<WorkOrderStatusHistoryModel>(
                predicate: #Predicate { $0.workOrderId == workOrderId },
                sortBy: [SortDescriptor(\.occurredAt)]
            ))
            .compactMap { $0.toDomain() }
    }

    func appendStatusHistory(_ entry: WorkOrderStatusHistory) throws {
        let woId = entry.workOrderId.rawValue
        let model = WorkOrderStatusHistoryModel(domain: entry)
        model.workOrder = try firstModel(WorkOrderModel.self, where: #Predicate { $0.id == woId })
        modelContext.insert(model)
        try modelContext.save()
    }

    func listSignatures(workOrderId: String) throws -> [Signature] {
        try modelContext
            .fetch(FetchDescriptor<SignatureModel>(
                predicate: #Predicate { $0.workOrderId == workOrderId },
                sortBy: [SortDescriptor(\.capturedAt)]
            ))
            .compactMap { $0.toDomain() }
    }

    func upsertSignature(_ signature: Signature) throws {
        let sigId = signature.id
        let woId  = signature.workOrderId.rawValue
        if let existing = try firstModel(SignatureModel.self, where: #Predicate { $0.id == sigId }) {
            existing.apply(domain: signature)
        } else {
            let model = SignatureModel(domain: signature)
            model.workOrder = try firstModel(WorkOrderModel.self, where: #Predicate { $0.id == woId })
            modelContext.insert(model)
        }
        try modelContext.save()
    }

    func deleteSignature(id: String) throws {
        guard let model = try firstModel(SignatureModel.self, where: #Predicate { $0.id == id })
        else { return }
        modelContext.delete(model)
        try modelContext.save()
    }

    // MARK: - EditRequest

    func fetchEditRequest(id: String) throws -> EditRequest? {
        let model = try firstModel(EditRequestModel.self, where: #Predicate { $0.id == id })
        return try model.map { try requireDecoded($0.toDomain(), entity: "EditRequest") }
    }

    func listEditRequests(workOrderId: String) throws -> [EditRequest] {
        try modelContext
            .fetch(FetchDescriptor<EditRequestModel>(
                predicate: #Predicate { $0.workOrderId == workOrderId },
                sortBy: [SortDescriptor(\.createdAt)]
            ))
            .compactMap { $0.toDomain() }
    }

    func listEditRequests(statusRaw: String) throws -> [EditRequest] {
        try modelContext
            .fetch(FetchDescriptor<EditRequestModel>(
                predicate: #Predicate { $0.statusRaw == statusRaw },
                sortBy: [SortDescriptor(\.createdAt)]
            ))
            .compactMap { $0.toDomain() }
    }

    func upsertEditRequest(_ request: EditRequest) throws {
        let requestId = request.id.rawValue
        let woId      = request.workOrderId.rawValue
        if let existing = try firstModel(EditRequestModel.self, where: #Predicate { $0.id == requestId }) {
            existing.apply(domain: request)
        } else {
            let model = EditRequestModel(domain: request)
            model.workOrder = try firstModel(WorkOrderModel.self, where: #Predicate { $0.id == woId })
            modelContext.insert(model)
        }
        try modelContext.save()
    }

    // MARK: - CustomerSatisfaction

    func fetchCustomerSatisfaction(id: String) throws -> CustomerSatisfaction? {
        let model = try firstModel(CustomerSatisfactionModel.self, where: #Predicate { $0.id == id })
        return try model.map { try requireDecoded($0.toDomain(), entity: "CustomerSatisfaction") }
    }

    func listCustomerSatisfactions(workOrderId: String) throws -> [CustomerSatisfaction] {
        try modelContext
            .fetch(FetchDescriptor<CustomerSatisfactionModel>(
                predicate: #Predicate { $0.workOrderId == workOrderId },
                sortBy: [SortDescriptor(\.createdAt)]
            ))
            .compactMap { $0.toDomain() }
    }

    func listCustomerSatisfactions(customerId: String) throws -> [CustomerSatisfaction] {
        try modelContext
            .fetch(FetchDescriptor<CustomerSatisfactionModel>(
                predicate: #Predicate { $0.customerId == customerId },
                sortBy: [SortDescriptor(\.createdAt)]
            ))
            .compactMap { $0.toDomain() }
    }

    func listCustomerSatisfactions(statusRaw: String) throws -> [CustomerSatisfaction] {
        try modelContext
            .fetch(FetchDescriptor<CustomerSatisfactionModel>(
                predicate: #Predicate { $0.statusRaw == statusRaw },
                sortBy: [SortDescriptor(\.createdAt)]
            ))
            .compactMap { $0.toDomain() }
    }

    func upsertCustomerSatisfaction(_ satisfaction: CustomerSatisfaction) throws {
        let satisfactionId = satisfaction.id.rawValue
        let workOrderId = satisfaction.workOrderId.rawValue
        if let existing = try firstModel(CustomerSatisfactionModel.self, where: #Predicate { $0.id == satisfactionId }) {
            existing.apply(domain: satisfaction)
        } else {
            let model = CustomerSatisfactionModel(domain: satisfaction)
            model.workOrder = try firstModel(WorkOrderModel.self, where: #Predicate { $0.id == workOrderId })
            modelContext.insert(model)
        }
        try modelContext.save()
    }

    // TEMP: clear local customer satisfaction records
    func deleteAllCustomerSatisfactions() throws {
        let rows = try modelContext.fetch(
            FetchDescriptor<CustomerSatisfactionModel>()
        )
        for row in rows {
            modelContext.delete(row)
        }
        try modelContext.save()
    }

    // MARK: - Notification

    func listNotifications(recipientUserId: String, unreadOnly: Bool) throws -> [AppNotification] {
        let base = try modelContext.fetch(
            FetchDescriptor<NotificationModel>(
                predicate: #Predicate { $0.recipientUserId == recipientUserId },
                sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
            )
        )
        let filtered = unreadOnly ? base.filter { !$0.isRead } : base
        return filtered.compactMap { $0.toDomain() }
    }

    func upsertNotification(_ notification: AppNotification) throws {
        let notifId = notification.id.rawValue
        if let existing = try firstModel(NotificationModel.self, where: #Predicate { $0.id == notifId }) {
            existing.apply(domain: notification)
        } else {
            modelContext.insert(NotificationModel(domain: notification))
        }
        try modelContext.save()
    }

    func markNotificationAsRead(id: String) throws {
        guard let model = try firstModel(NotificationModel.self, where: #Predicate { $0.id == id })
        else { return }
        model.isRead = true
        try modelContext.save()
    }

    func deleteNotification(id: String) throws {
        guard let model = try firstModel(NotificationModel.self, where: #Predicate { $0.id == id })
        else { return }
        modelContext.delete(model)
        try modelContext.save()
    }

    // MARK: - Local session (auth surface)

    func currentSessionUserId() throws -> String? {
        try loadSessionModel()?.currentUserId
    }

    func setCurrentSessionUserId(_ userId: String?, at timestamp: Date) throws {
        if let existing = try loadSessionModel() {
            existing.currentUserId = userId
            existing.updatedAt = timestamp
        } else {
            modelContext.insert(
                LocalSessionModel(currentUserId: userId, updatedAt: timestamp)
            )
        }
        try modelContext.save()
    }

    private func loadSessionModel() throws -> LocalSessionModel? {
        let singletonId = LocalSessionModel.singletonId
        return try firstModel(
            LocalSessionModel.self,
            where: #Predicate { $0.id == singletonId }
        )
    }

    // MARK: - Sync queue

    func fetchSyncOperation(id: String) throws -> SyncOperation? {
        let model = try firstModel(SyncOperationModel.self, where: #Predicate { $0.id == id })
        return try model.map { try requireDecoded($0.toDomain(), entity: "SyncOperation") }
    }

    /// Inserts when `idempotencyKey` is unseen. A matching key returns
    /// `.duplicate` with the stored row left untouched — including
    /// across concurrent callers, because this actor serializes them.
    func enqueueSyncOperation(_ operation: SyncOperation) throws -> SyncEnqueueOutcome {
        let key = operation.idempotencyKey.rawValue
        if let existing = try firstModel(
            SyncOperationModel.self,
            where: #Predicate { $0.idempotencyKey == key }
        ) {
            let domain = try requireDecoded(existing.toDomain(), entity: "SyncOperation")
            return .duplicate(existing: domain)
        }

        if let duplicate = try findActiveDuplicate(of: operation) {
            let domain = try requireDecoded(duplicate.toDomain(), entity: "SyncOperation")
            return .duplicate(existing: domain)
        }

        guard operation.status == .pending else {
            throw DomainError.invalidData(reason: "syncOperation.enqueueRequiresPending")
        }

        let rawId = operation.id.rawValue
        if try firstModel(SyncOperationModel.self, where: #Predicate { $0.id == rawId }) != nil {
            throw DomainError.invalidData(reason: "syncOperation.idCollision")
        }

        modelContext.insert(SyncOperationModel(domain: operation))
        try modelContext.save()
        return .inserted(operation)
    }

    /// Blocks a second active row for the same logical mutation tuple.
    private func findActiveDuplicate(of operation: SyncOperation) throws -> SyncOperationModel? {
        let entityTypeRaw = operation.entityType.rawValue
        let entityId = operation.entityId
        let operationTypeRaw = operation.operationType.rawValue
        let localVersion = operation.localVersion
        let pendingRaw = SyncStatus.pending.rawValue
        let inProgressRaw = SyncStatus.inProgress.rawValue
        let failedRaw = SyncStatus.failed.rawValue
        let conflictRaw = SyncStatus.conflict.rawValue
        let rows = try modelContext.fetch(
            FetchDescriptor<SyncOperationModel>(
                predicate: #Predicate {
                    $0.entityTypeRaw == entityTypeRaw
                        && $0.entityId == entityId
                        && $0.operationTypeRaw == operationTypeRaw
                        && $0.localVersion == localVersion
                        && (
                            $0.statusRaw == pendingRaw
                                || $0.statusRaw == inProgressRaw
                                || $0.statusRaw == failedRaw
                                || $0.statusRaw == conflictRaw
                        )
                }
            )
        )
        return rows.first
    }

    /// Retry reset: `.failed` → `.pending` without going through
    /// `SyncStatusStateMachine` (documented in `SyncStatus.isTerminal`).
    func prepareSyncOperationRetry(id: String) throws {
        guard let model = try firstModel(
            SyncOperationModel.self,
            where: #Predicate { $0.id == id }
        ) else {
            throw DomainError.notFound(entity: "SyncOperation", id: id)
        }
        let current = try requireDecoded(model.toDomain(), entity: "SyncOperation")
        switch current.status {
        case .failed:
            model.statusRaw = SyncStatus.pending.rawValue
            try modelContext.save()
        case .pending:
            return
        case .inProgress, .succeeded, .conflict:
            throw DomainError.invalidData(reason: "syncOperation.prepareRetryRequiresFailed")
        }
    }

    func listSyncOperations(entityType: String, entityId: String) throws -> [SyncOperation] {
        let rows = try modelContext.fetch(
            FetchDescriptor<SyncOperationModel>(
                predicate: #Predicate {
                    $0.entityTypeRaw == entityType && $0.entityId == entityId
                },
                sortBy: [
                    SortDescriptor(\.createdAt),
                    SortDescriptor(\.id)
                ]
            )
        )
        return try decodedSyncOperations(rows)
    }

    func updateSyncOperation(_ operation: SyncOperation) throws {
        let rawId = operation.id.rawValue
        guard let existing = try firstModel(
            SyncOperationModel.self,
            where: #Predicate { $0.id == rawId }
        ) else {
            throw DomainError.notFound(entity: "SyncOperation", id: rawId)
        }
        let current = try requireDecoded(existing.toDomain(), entity: "SyncOperation")
        if current.status != operation.status {
            try SyncStatusStateMachine.transition(
                from: current.status,
                to: operation.status
            )
        }
        existing.apply(domain: operation)
        try modelContext.save()
    }

    func deleteSyncOperation(id: String) throws {
        guard let model = try firstModel(
            SyncOperationModel.self,
            where: #Predicate { $0.id == id }
        ) else {
            throw DomainError.notFound(entity: "SyncOperation", id: id)
        }
        let current = try requireDecoded(model.toDomain(), entity: "SyncOperation")
        guard current.status == .succeeded else {
            throw DomainError.invalidData(reason: "syncOperation.deleteOnlySucceeded")
        }
        modelContext.delete(model)
        try modelContext.save()
    }

    func deleteCompletedSyncOperations() throws {
        let succeededRaw = SyncStatus.succeeded.rawValue
        let rows = try modelContext.fetch(
            FetchDescriptor<SyncOperationModel>(
                predicate: #Predicate { $0.statusRaw == succeededRaw }
            )
        )
        for row in rows {
            modelContext.delete(row)
        }
        try modelContext.save()
    }

    func deleteFailedSyncOperations(ids: [String]) throws {
        guard !ids.isEmpty else { return }
        for id in ids {
            guard let model = try firstModel(
                SyncOperationModel.self,
                where: #Predicate { $0.id == id }
            ) else {
                throw DomainError.notFound(entity: "SyncOperation", id: id)
            }
            let current = try requireDecoded(model.toDomain(), entity: "SyncOperation")
            guard current.status == .failed else {
                throw DomainError.invalidData(reason: "syncOperation.deleteFailedOnlyFailed")
            }
            modelContext.delete(model)
        }
        try modelContext.save()
    }

    func fetchPendingSyncOperations(now: Date) throws -> [SyncOperation] {
        let pendingRaw = SyncStatus.pending.rawValue
        let failedRaw = SyncStatus.failed.rawValue
        let rows = try modelContext.fetch(
            FetchDescriptor<SyncOperationModel>(
                predicate: #Predicate {
                    $0.statusRaw == pendingRaw || $0.statusRaw == failedRaw
                },
                sortBy: [
                    SortDescriptor(\.createdAt),
                    SortDescriptor(\.id)
                ]
            )
        )
        return try decodedSyncOperations(rows).filter { operation in
            isReadyForAttempt(operation, now: now)
        }
    }

    func countPendingSyncOperations(now: Date) throws -> Int {
        try fetchPendingSyncOperations(now: now).count
    }

    func fetchSyncOperations(status: SyncStatus) throws -> [SyncOperation] {
        let statusRaw = status.rawValue
        let rows = try modelContext.fetch(
            FetchDescriptor<SyncOperationModel>(
                predicate: #Predicate { $0.statusRaw == statusRaw },
                sortBy: [
                    SortDescriptor(\.createdAt),
                    SortDescriptor(\.id)
                ]
            )
        )
        return try decodedSyncOperations(rows)
    }

    func fetchSyncConflict(id: String) throws -> SyncConflict? {
        let model = try firstModel(SyncConflictModel.self, where: #Predicate { $0.id == id })
        return try model.map { try requireDecoded($0.toDomain(), entity: "SyncConflict") }
    }

    func fetchSyncConflict(syncOperationId: String) throws -> SyncConflict? {
        let model = try firstModel(
            SyncConflictModel.self,
            where: #Predicate { $0.syncOperationId == syncOperationId }
        )
        return try model.map { try requireDecoded($0.toDomain(), entity: "SyncConflict") }
    }

    func upsertSyncConflict(_ conflict: SyncConflict) throws {
        let rawId = conflict.id.rawValue
        if let existing = try firstModel(
            SyncConflictModel.self,
            where: #Predicate { $0.id == rawId }
        ) {
            existing.apply(domain: conflict)
        } else {
            modelContext.insert(SyncConflictModel(domain: conflict))
        }
        try modelContext.save()
    }

    func listUnresolvedSyncConflicts() throws -> [SyncConflict] {
        let unresolvedRaw = SyncConflictStatus.unresolved.rawValue
        let rows = try modelContext.fetch(
            FetchDescriptor<SyncConflictModel>(
                predicate: #Predicate { $0.statusRaw == unresolvedRaw },
                sortBy: [
                    SortDescriptor(\.detectedAt),
                    SortDescriptor(\.id)
                ]
            )
        )
        return try rows
            .map { try requireDecoded($0.toDomain(), entity: "SyncConflict") }
            .filter { $0.resolution == nil }
    }

#if DEBUG
    /// Test seam: persist an unknown `statusRaw` so fetch can assert
    /// `DomainError.invalidData` instead of a silent default.
    func debugOverwriteSyncOperationStatusRaw(id: String, statusRaw: String) throws {
        guard let model = try firstModel(
            SyncOperationModel.self,
            where: #Predicate { $0.id == id }
        ) else {
            throw DomainError.notFound(entity: "SyncOperation", id: id)
        }
        model.statusRaw = statusRaw
        try modelContext.save()
    }

    func debugOverwriteSyncConflictStatusRaw(id: String, statusRaw: String) throws {
        guard let model = try firstModel(
            SyncConflictModel.self,
            where: #Predicate { $0.id == id }
        ) else {
            throw DomainError.notFound(entity: "SyncConflict", id: id)
        }
        model.statusRaw = statusRaw
        try modelContext.save()
    }
#endif

    /// A row is "pending" for the drain query when it is `.pending`
    /// and not waiting on backoff, or `.failed` whose `nextRetryAt`
    /// has arrived. Failed rows with no retry time (cap reached) stay
    /// out of this set.
    private func isReadyForAttempt(_ operation: SyncOperation, now: Date) -> Bool {
        switch operation.status {
        case .pending:
            if let nextRetryAt = operation.nextRetryAt {
                return nextRetryAt <= now
            }
            return true
        case .failed:
            guard let nextRetryAt = operation.nextRetryAt else { return false }
            return nextRetryAt <= now
        case .inProgress, .succeeded, .conflict:
            return false
        }
    }

    private func decodedSyncOperations(_ models: [SyncOperationModel]) throws -> [SyncOperation] {
        try models.map { try requireDecoded($0.toDomain(), entity: "SyncOperation") }
    }

    // MARK: - Small internal helpers

    /// Fetches at most one model matching the predicate. Encapsulates
    /// the common "descriptor + fetchLimit=1 + first" idiom that
    /// otherwise clutters every call site.
    private func firstModel<M: PersistentModel>(
        _ type: M.Type,
        where predicate: Predicate<M>
    ) throws -> M? {
        var descriptor = FetchDescriptor<M>(predicate: predicate)
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    /// Throws `DomainError.invalidData` when a persisted row decodes
    /// to `nil` (e.g. an unknown enum raw value on disk).
    private func requireDecoded<T>(
        _ value: T?,
        entity: String,
        file: StaticString = #file,
        line: UInt = #line
    ) throws -> T {
        guard let value else {
            throw DomainError.invalidData(reason: "swiftData.\(entity).decodeFailed")
        }
        return value
    }
}
