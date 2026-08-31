import Foundation

/// Local-first CRUD for operator work-order templates.
struct OperatorWorkOrderTemplateService: Sendable {
    private static func defaultsSeededKey(for userId: UserID) -> String {
        "workOrderTemplateDefaultsSeeded.\(userId.rawValue)"
    }

    let repository: WorkOrderTemplateRepository

    func list(actor: User) async throws -> [WorkOrderTemplate] {
        try await ensureDefaults(actor: actor)
        return try await repository.list(createdByUserId: actor.id)
    }

    func fetch(actor: User, id: WorkOrderTemplateID) async throws -> WorkOrderTemplate {
        let template = try await repository.fetch(id: id)
        guard template.createdByUserId == actor.id else {
            throw DomainError.unauthorized(action: .createWorkOrder)
        }
        return template
    }

    @discardableResult
    func create(
        actor: User,
        name: String,
        summary: String?,
        workType: WorkType,
        deviceCategory: DeviceCategory,
        deviceBrand: String?,
        deviceModel: String?,
        issueDescription: String?,
        priority: WorkOrderPriority,
        at now: Date = Date()
    ) async throws -> WorkOrderTemplate {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw DomainError.invalidData(reason: "workOrderTemplate.nameRequired")
        }

        let template = WorkOrderTemplate(
            id: WorkOrderTemplateID(UUID().uuidString),
            name: trimmedName,
            summary: summary?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            workType: workType,
            deviceCategory: deviceCategory,
            deviceBrand: deviceBrand?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            deviceModel: deviceModel?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            issueDescription: issueDescription?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            priority: priority,
            createdByUserId: actor.id,
            createdAt: now,
            updatedAt: now
        )
        try await repository.save(template)
        return template
    }

    @discardableResult
    func update(
        actor: User,
        template: WorkOrderTemplate,
        at now: Date = Date()
    ) async throws -> WorkOrderTemplate {
        guard template.createdByUserId == actor.id else {
            throw DomainError.unauthorized(action: .createWorkOrder)
        }
        let trimmedName = template.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw DomainError.invalidData(reason: "workOrderTemplate.nameRequired")
        }

        var updated = template
        updated.name = trimmedName
        updated.summary = template.summary?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        updated.deviceBrand = template.deviceBrand?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        updated.deviceModel = template.deviceModel?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        updated.issueDescription = template.issueDescription?
            .trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        updated.updatedAt = now
        try await repository.save(updated)
        return updated
    }

    func delete(actor: User, id: WorkOrderTemplateID) async throws {
        let template = try await repository.fetch(id: id)
        guard template.createdByUserId == actor.id else {
            throw DomainError.unauthorized(action: .createWorkOrder)
        }
        try await repository.delete(id: id)
    }

    @discardableResult
    func duplicate(actor: User, id: WorkOrderTemplateID, at now: Date = Date()) async throws -> WorkOrderTemplate {
        let source = try await fetch(actor: actor, id: id)
        return try await create(
            actor: actor,
            name: "\(source.name) Kopya",
            summary: source.summary,
            workType: source.workType,
            deviceCategory: source.deviceCategory,
            deviceBrand: source.deviceBrand,
            deviceModel: source.deviceModel,
            issueDescription: source.issueDescription,
            priority: source.priority,
            at: now
        )
    }

    private func ensureDefaults(actor: User, at now: Date = Date()) async throws {
        let key = Self.defaultsSeededKey(for: actor.id)
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        for template in WorkOrderTemplateDefaults.templates(for: actor.id, at: now) {
            try await repository.save(template)
        }
        UserDefaults.standard.set(true, forKey: key)
    }

#if DEBUG
    static func resetDefaultsSeed(for userId: UserID) {
        UserDefaults.standard.removeObject(forKey: defaultsSeededKey(for: userId))
    }
#endif
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
