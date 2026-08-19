import Foundation
@testable import DonanimOperasyonServis

enum SyncRemoteWrite: Equatable, Sendable {
    case save(SyncEntityType, String)
    case delete(SyncEntityType, String)
    case append(SyncEntityType, String)
}

actor SyncRemoteProbe {
    private(set) var writes: [SyncRemoteWrite] = []
    var error: DomainError?

    func throwIfFailed() throws {
        if let error { throw error }
    }

    func setError(_ error: DomainError?) {
        self.error = error
    }

    func record(_ write: SyncRemoteWrite) {
        writes.append(write)
    }

    func recordedWrites() -> [SyncRemoteWrite] { writes }
}

struct SpyingUserRepository: UserRepository {
    let inner: InMemoryUserRepository
    let probe: SyncRemoteProbe

    func fetch(id: UserID) async throws -> User { try await inner.fetch(id: id) }
    func findByEmail(_ email: String) async throws -> User? { try await inner.findByEmail(email) }
    func list(role: UserRole?, isActive: Bool?) async throws -> [User] {
        try await inner.list(role: role, isActive: isActive)
    }
    func save(_ user: User) async throws {
        try await probe.throwIfFailed()
        try await inner.save(user)
        await probe.record(.save(.user, user.id.rawValue))
    }
    func delete(id: UserID) async throws {
        try await probe.throwIfFailed()
        try await inner.delete(id: id)
        await probe.record(.delete(.user, id.rawValue))
    }
}

struct SpyingCustomerRepository: CustomerRepository {
    let inner: InMemoryCustomerRepository
    let probe: SyncRemoteProbe

    func fetch(id: CustomerID) async throws -> Customer { try await inner.fetch(id: id) }
    func list(searchText: String?) async throws -> [Customer] {
        try await inner.list(searchText: searchText)
    }
    func save(_ customer: Customer) async throws {
        try await probe.throwIfFailed()
        try await inner.save(customer)
        await probe.record(.save(.customer, customer.id.rawValue))
    }
    func delete(id: CustomerID) async throws {
        try await probe.throwIfFailed()
        try await inner.delete(id: id)
        await probe.record(.delete(.customer, id.rawValue))
    }
}

struct SpyingWorkOrderRepository: WorkOrderRepository {
    let inner: InMemoryWorkOrderRepository
    let probe: SyncRemoteProbe

    func fetch(id: WorkOrderID) async throws -> WorkOrder { try await inner.fetch(id: id) }
    func list(filter: WorkOrderFilter) async throws -> [WorkOrder] {
        try await inner.list(filter: filter)
    }
    func save(_ workOrder: WorkOrder) async throws {
        try await probe.throwIfFailed()
        try await inner.save(workOrder)
        await probe.record(.save(.workOrder, workOrder.id.rawValue))
    }
    func delete(id: WorkOrderID) async throws {
        try await probe.throwIfFailed()
        try await inner.delete(id: id)
        await probe.record(.delete(.workOrder, id.rawValue))
    }
}

struct SpyingNoteRepository: WorkOrderNoteRepository {
    let inner: InMemoryNoteRepository
    let probe: SyncRemoteProbe

    func list(for workOrderId: WorkOrderID) async throws -> [WorkOrderNote] {
        try await inner.list(for: workOrderId)
    }
    func save(_ note: WorkOrderNote) async throws {
        try await probe.throwIfFailed()
        try await inner.save(note)
        await probe.record(.save(.workOrderNote, note.id))
    }
    func delete(id: String, for workOrderId: WorkOrderID) async throws {
        try await probe.throwIfFailed()
        try await inner.delete(id: id, for: workOrderId)
        await probe.record(.delete(.workOrderNote, id))
    }
}

struct SpyingPhotoRepository: WorkOrderPhotoRepository {
    let inner: InMemoryPhotoRepository
    let probe: SyncRemoteProbe

    func list(for workOrderId: WorkOrderID) async throws -> [WorkOrderPhoto] {
        try await inner.list(for: workOrderId)
    }
    func save(_ photo: WorkOrderPhoto) async throws {
        try await probe.throwIfFailed()
        try await inner.save(photo)
        await probe.record(.save(.workOrderPhoto, photo.id))
    }
    func delete(id: String, for workOrderId: WorkOrderID) async throws {
        try await probe.throwIfFailed()
        try await inner.delete(id: id, for: workOrderId)
        await probe.record(.delete(.workOrderPhoto, id))
    }
}

struct SpyingLocationRepository: WorkOrderLocationRepository {
    let inner: InMemoryLocationRepository
    let probe: SyncRemoteProbe

    func list(for workOrderId: WorkOrderID) async throws -> [WorkOrderLocation] {
        try await inner.list(for: workOrderId)
    }
    func save(_ location: WorkOrderLocation) async throws {
        try await probe.throwIfFailed()
        try await inner.save(location)
        await probe.record(.save(.workOrderLocation, location.id))
    }
}

struct SpyingStatusHistoryRepository: WorkOrderStatusHistoryRepository {
    let inner: InMemoryStatusHistoryRepository
    let probe: SyncRemoteProbe

    func list(for workOrderId: WorkOrderID) async throws -> [WorkOrderStatusHistory] {
        try await inner.list(for: workOrderId)
    }
    func append(_ entry: WorkOrderStatusHistory) async throws {
        try await probe.throwIfFailed()
        try await inner.append(entry)
        await probe.record(.append(.workOrderStatusHistory, entry.id))
    }
}

struct SpyingSignatureRepository: SignatureRepository {
    let inner: InMemorySignatureRepository
    let probe: SyncRemoteProbe

    func list(for workOrderId: WorkOrderID) async throws -> [Signature] {
        try await inner.list(for: workOrderId)
    }
    func save(_ signature: Signature) async throws {
        try await probe.throwIfFailed()
        try await inner.save(signature)
        await probe.record(.save(.signature, signature.id))
    }
    func delete(id: String, for workOrderId: WorkOrderID) async throws {
        try await probe.throwIfFailed()
        try await inner.delete(id: id, for: workOrderId)
        await probe.record(.delete(.signature, id))
    }
}

struct SpyingEditRequestRepository: EditRequestRepository {
    let inner: InMemoryEditRequestRepository
    let probe: SyncRemoteProbe

    func fetch(id: EditRequestID) async throws -> EditRequest { try await inner.fetch(id: id) }
    func list(for workOrderId: WorkOrderID) async throws -> [EditRequest] {
        try await inner.list(for: workOrderId)
    }
    func listByStatus(_ status: EditRequestStatus) async throws -> [EditRequest] {
        try await inner.listByStatus(status)
    }
    func save(_ request: EditRequest) async throws {
        try await probe.throwIfFailed()
        try await inner.save(request)
        await probe.record(.save(.editRequest, request.id.rawValue))
    }
}

struct SpyingNotificationRepository: NotificationRepository {
    let inner: InMemoryNotificationRepository
    let probe: SyncRemoteProbe

    func list(for recipientId: UserID, unreadOnly: Bool) async throws -> [AppNotification] {
        try await inner.list(for: recipientId, unreadOnly: unreadOnly)
    }
    func save(_ notification: AppNotification) async throws {
        try await probe.throwIfFailed()
        try await inner.save(notification)
        await probe.record(.save(.notification, notification.id.rawValue))
    }
    func markAsRead(id: NotificationID) async throws {
        try await inner.markAsRead(id: id)
    }
    func delete(id: NotificationID) async throws {
        try await probe.throwIfFailed()
        try await inner.delete(id: id)
        await probe.record(.delete(.notification, id.rawValue))
    }
}

enum SyncManagerTestFactory {

    static func remoteBundle(probe: SyncRemoteProbe) -> (
        repositories: SyncEntityRepositories,
        customers: InMemoryCustomerRepository,
        workOrders: InMemoryWorkOrderRepository
    ) {
        let customers = InMemoryCustomerRepository()
        let workOrders = InMemoryWorkOrderRepository()
        let repositories = SyncEntityRepositories(
            users: SpyingUserRepository(inner: InMemoryUserRepository(), probe: probe),
            customers: SpyingCustomerRepository(inner: customers, probe: probe),
            workOrders: SpyingWorkOrderRepository(inner: workOrders, probe: probe),
            notes: SpyingNoteRepository(inner: InMemoryNoteRepository(), probe: probe),
            photos: SpyingPhotoRepository(inner: InMemoryPhotoRepository(), probe: probe),
            locations: SpyingLocationRepository(inner: InMemoryLocationRepository(), probe: probe),
            statusHistory: SpyingStatusHistoryRepository(
                inner: InMemoryStatusHistoryRepository(),
                probe: probe
            ),
            signatures: SpyingSignatureRepository(inner: InMemorySignatureRepository(), probe: probe),
            editRequests: SpyingEditRequestRepository(
                inner: InMemoryEditRequestRepository(),
                probe: probe
            ),
            notifications: SpyingNotificationRepository(
                inner: InMemoryNotificationRepository(),
                probe: probe
            )
        )
        return (repositories, customers, workOrders)
    }
}
