import Foundation
@testable import DonanimOperasyonServis

/// In-memory `WorkOrderRepository` for tests. Filtering supports
/// the subset of `WorkOrderFilter` fields actually exercised by
/// current tests; additional fields fall through as "no narrowing".
actor InMemoryWorkOrderRepository: WorkOrderRepository {
    private var storage: [WorkOrderID: WorkOrder] = [:]

    init(seed: [WorkOrder] = []) {
        for order in seed { storage[order.id] = order }
    }

    func fetch(id: WorkOrderID) async throws -> WorkOrder {
        guard let order = storage[id] else {
            throw DomainError.notFound(entity: "WorkOrder", id: id.rawValue)
        }
        return order
    }

    func list(filter: WorkOrderFilter) async throws -> [WorkOrder] {
        storage.values.filter { order in
            if let status = filter.status, order.status != status { return false }
            if let priority = filter.priority, order.priority != priority { return false }
            if let workType = filter.workType, order.workType != workType { return false }
            if let tech = filter.assignedTechnicianId, order.assignedTechnicianId != tech { return false }
            if let creator = filter.createdByUserId, order.createdByUserId != creator { return false }
            if let customer = filter.customerId, order.customerId != customer { return false }
            return true
        }
    }

    func save(_ workOrder: WorkOrder) async throws {
        storage[workOrder.id] = workOrder
    }

    func delete(id: WorkOrderID) async throws {
        storage.removeValue(forKey: id)
    }

    func snapshot() -> [WorkOrder] { Array(storage.values) }
}

actor InMemoryStatusHistoryRepository: WorkOrderStatusHistoryRepository {
    private var entries: [WorkOrderStatusHistory] = []

    func list(for workOrderId: WorkOrderID) async throws -> [WorkOrderStatusHistory] {
        entries.filter { $0.workOrderId == workOrderId }
    }

    func append(_ entry: WorkOrderStatusHistory) async throws {
        entries.append(entry)
    }

    func all() -> [WorkOrderStatusHistory] { entries }
}

actor InMemoryNoteRepository: WorkOrderNoteRepository {
    private var notes: [String: WorkOrderNote] = [:]

    init(seed: [WorkOrderNote] = []) {
        for n in seed { notes[n.id] = n }
    }

    func list(for workOrderId: WorkOrderID) async throws -> [WorkOrderNote] {
        notes.values.filter { $0.workOrderId == workOrderId }
    }

    func save(_ note: WorkOrderNote) async throws {
        notes[note.id] = note
    }

    func delete(id: String, for workOrderId: WorkOrderID) async throws {
        notes.removeValue(forKey: id)
    }
}

actor InMemoryPhotoRepository: WorkOrderPhotoRepository {
    private var photos: [String: WorkOrderPhoto] = [:]

    init(seed: [WorkOrderPhoto] = []) {
        for p in seed { photos[p.id] = p }
    }

    func list(for workOrderId: WorkOrderID) async throws -> [WorkOrderPhoto] {
        photos.values.filter { $0.workOrderId == workOrderId }
    }

    func save(_ photo: WorkOrderPhoto) async throws {
        photos[photo.id] = photo
    }

    func delete(id: String, for workOrderId: WorkOrderID) async throws {
        photos.removeValue(forKey: id)
    }
}

actor InMemoryLocationRepository: WorkOrderLocationRepository {
    private var locations: [String: WorkOrderLocation] = [:]

    init(seed: [WorkOrderLocation] = []) {
        for l in seed { locations[l.id] = l }
    }

    func list(for workOrderId: WorkOrderID) async throws -> [WorkOrderLocation] {
        locations.values.filter { $0.workOrderId == workOrderId }
    }

    func save(_ location: WorkOrderLocation) async throws {
        locations[location.id] = location
    }
}

actor InMemorySignatureRepository: SignatureRepository {
    private var signatures: [String: Signature] = [:]

    init(seed: [Signature] = []) {
        for s in seed { signatures[s.id] = s }
    }

    func list(for workOrderId: WorkOrderID) async throws -> [Signature] {
        signatures.values.filter { $0.workOrderId == workOrderId }
    }

    func save(_ signature: Signature) async throws {
        signatures[signature.id] = signature
    }

    func delete(id: String, for workOrderId: WorkOrderID) async throws {
        signatures.removeValue(forKey: id)
    }
}

actor InMemoryEditRequestRepository: EditRequestRepository {
    private var storage: [EditRequestID: EditRequest] = [:]

    init(seed: [EditRequest] = []) {
        for r in seed { storage[r.id] = r }
    }

    func fetch(id: EditRequestID) async throws -> EditRequest {
        guard let request = storage[id] else {
            throw DomainError.notFound(entity: "EditRequest", id: id.rawValue)
        }
        return request
    }

    func list(for workOrderId: WorkOrderID) async throws -> [EditRequest] {
        storage.values.filter { $0.workOrderId == workOrderId }
    }

    func listByStatus(_ status: EditRequestStatus) async throws -> [EditRequest] {
        storage.values.filter { $0.status == status }
    }

    func save(_ request: EditRequest) async throws {
        storage[request.id] = request
    }
}
