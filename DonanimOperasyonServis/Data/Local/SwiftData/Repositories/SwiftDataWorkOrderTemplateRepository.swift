import Foundation

struct SwiftDataWorkOrderTemplateRepository: WorkOrderTemplateRepository {
    let store: LocalPersistence

    init(store: LocalPersistence) {
        self.store = store
    }

    func fetch(id: WorkOrderTemplateID) async throws -> WorkOrderTemplate {
        guard let template = try await store.fetchWorkOrderTemplate(id: id.rawValue) else {
            throw DomainError.notFound(entity: "WorkOrderTemplate", id: id.rawValue)
        }
        return template
    }

    func list(createdByUserId: UserID) async throws -> [WorkOrderTemplate] {
        try await store.listWorkOrderTemplates(createdByUserId: createdByUserId.rawValue)
    }

    func save(_ template: WorkOrderTemplate) async throws {
        try await store.upsertWorkOrderTemplate(template)
    }

    func delete(id: WorkOrderTemplateID) async throws {
        try await store.deleteWorkOrderTemplate(id: id.rawValue)
    }
}
