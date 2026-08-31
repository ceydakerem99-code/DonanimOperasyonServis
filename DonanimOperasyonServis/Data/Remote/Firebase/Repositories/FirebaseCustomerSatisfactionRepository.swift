import Foundation

/// Firestore-backed implementation of `CustomerSatisfactionRepository`.
struct FirebaseCustomerSatisfactionRepository: CustomerSatisfactionRepository {

    let dataSource: any FirestoreDataSource

    init(dataSource: any FirestoreDataSource) {
        self.dataSource = dataSource
    }

    func fetch(id: CustomerSatisfactionID) async throws -> CustomerSatisfaction {
        try await FirebaseRepositoryMapper.run(entity: "CustomerSatisfaction", id: id.rawValue) {
            guard let dto = try await dataSource.fetch(
                FirestoreCustomerSatisfactionDTO.self,
                collection: .customerSatisfactions,
                id: id.rawValue
            ) else {
                throw DomainError.notFound(entity: "CustomerSatisfaction", id: id.rawValue)
            }
            return try FirebaseRepositoryMapper.requireDomain(dto, entity: "CustomerSatisfaction") { $0.toDomain() }
        }
    }

    func list(for workOrderId: WorkOrderID) async throws -> [CustomerSatisfaction] {
        try await FirebaseRepositoryMapper.run(entity: "CustomerSatisfaction", id: workOrderId.rawValue) {
            let dtos = try await dataSource.list(
                FirestoreCustomerSatisfactionDTO.self,
                collection: .customerSatisfactions,
                predicates: [.equal("workOrderId", .string(workOrderId.rawValue))],
                orderBy: [.ascending("createdAt")]
            )
            return try dtos.map {
                try FirebaseRepositoryMapper.requireDomain($0, entity: "CustomerSatisfaction") { $0.toDomain() }
            }
        }
    }

    func listByCustomer(_ customerId: CustomerID) async throws -> [CustomerSatisfaction] {
        try await FirebaseRepositoryMapper.run(entity: "CustomerSatisfaction", id: customerId.rawValue) {
            let dtos = try await dataSource.list(
                FirestoreCustomerSatisfactionDTO.self,
                collection: .customerSatisfactions,
                predicates: [.equal("customerId", .string(customerId.rawValue))],
                orderBy: [.ascending("createdAt")]
            )
            return try dtos.map {
                try FirebaseRepositoryMapper.requireDomain($0, entity: "CustomerSatisfaction") { $0.toDomain() }
            }
        }
    }

    func listByStatus(_ status: CustomerSatisfactionStatus) async throws -> [CustomerSatisfaction] {
        try await FirebaseRepositoryMapper.run(entity: "CustomerSatisfaction") {
            let dtos = try await dataSource.list(
                FirestoreCustomerSatisfactionDTO.self,
                collection: .customerSatisfactions,
                predicates: [.equal("status", .string(status.rawValue))],
                orderBy: [.ascending("createdAt")]
            )
            return try dtos.map {
                try FirebaseRepositoryMapper.requireDomain($0, entity: "CustomerSatisfaction") { $0.toDomain() }
            }
        }
    }

    func save(_ satisfaction: CustomerSatisfaction) async throws {
        try await FirebaseRepositoryMapper.run(entity: "CustomerSatisfaction", id: satisfaction.id.rawValue) {
            try await dataSource.set(
                FirestoreCustomerSatisfactionDTO(domain: satisfaction),
                collection: .customerSatisfactions,
                id: satisfaction.id.rawValue
            )
        }
    }
}
