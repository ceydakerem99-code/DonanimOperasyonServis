import Foundation

/// Persistence surface for operator work-order templates.
protocol WorkOrderTemplateRepository: Sendable {
    func fetch(id: WorkOrderTemplateID) async throws -> WorkOrderTemplate
    func list(createdByUserId: UserID) async throws -> [WorkOrderTemplate]
    func save(_ template: WorkOrderTemplate) async throws
    func delete(id: WorkOrderTemplateID) async throws
}
