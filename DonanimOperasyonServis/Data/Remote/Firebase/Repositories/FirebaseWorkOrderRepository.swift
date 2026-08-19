import Foundation

/// Firestore-backed implementation of `WorkOrderRepository`.
///
/// `WorkOrderFilter` is translated into a combination of Firestore
/// equality predicates (status, priority, workType, assigned
/// technician, creator, customer) plus in-memory range filtering
/// for `scheduledFrom`/`scheduledTo`. Compound range + equality
/// queries would require composite indexes we do not want to
/// introduce in Phase 4; the in-memory post-filter keeps the
/// contract identical to the SwiftData repository.
struct FirebaseWorkOrderRepository: WorkOrderRepository {

    let dataSource: any FirestoreDataSource

    init(dataSource: any FirestoreDataSource) {
        self.dataSource = dataSource
    }

    func fetch(id: WorkOrderID) async throws -> WorkOrder {
        do {
            guard let dto = try await dataSource.fetch(
                FirestoreWorkOrderDTO.self,
                collection: .workOrders,
                id: id.rawValue
            ) else {
                throw DomainError.notFound(entity: "WorkOrder", id: id.rawValue)
            }
            return try FirebaseRepositoryMapper.requireDomain(dto, entity: "WorkOrder") { $0.toDomain() }
        } catch {
            throw FirebaseRepositoryMapper.mapNotFound(error, entity: "WorkOrder", id: id.rawValue)
        }
    }

    func list(filter: WorkOrderFilter) async throws -> [WorkOrder] {
        let dtos = try await dataSource.list(
            FirestoreWorkOrderDTO.self,
            collection: .workOrders,
            predicates: Self.predicates(for: filter),
            orderBy: [.ascending("scheduledDate")]
        )
        let decoded = try dtos.map {
            try FirebaseRepositoryMapper.requireDomain($0, entity: "WorkOrder") { $0.toDomain() }
        }
        return decoded.filter { order in
            if let from = filter.scheduledFrom, order.scheduledDate < from { return false }
            if let to   = filter.scheduledTo,   order.scheduledDate > to   { return false }
            return true
        }
    }

    func save(_ workOrder: WorkOrder) async throws {
        try await dataSource.set(
            FirestoreWorkOrderDTO(domain: workOrder),
            collection: .workOrders,
            id: workOrder.id.rawValue
        )
    }

    func delete(id: WorkOrderID) async throws {
        try await dataSource.delete(collection: .workOrders, id: id.rawValue)
    }

    /// Equality predicates that Firestore can apply server-side.
    /// Date-range predicates are intentionally omitted — they are
    /// applied in memory after fetch (see `list(filter:)`).
    static func predicates(for filter: WorkOrderFilter) -> [FirestorePredicate] {
        var predicates: [FirestorePredicate] = []
        if let value = filter.status {
            predicates.append(.equal("status", .string(value.rawValue)))
        }
        if let value = filter.priority {
            predicates.append(.equal("priority", .string(value.rawValue)))
        }
        if let value = filter.workType {
            predicates.append(.equal("workType", .string(value.rawValue)))
        }
        if let value = filter.assignedTechnicianId {
            predicates.append(.equal("assignedTechnicianId", .string(value.rawValue)))
        }
        if let value = filter.createdByUserId {
            predicates.append(.equal("createdByUserId", .string(value.rawValue)))
        }
        if let value = filter.customerId {
            predicates.append(.equal("customerId", .string(value.rawValue)))
        }
        return predicates
    }
}
