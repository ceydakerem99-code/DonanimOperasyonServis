import Foundation
import Observation

@Observable
@MainActor
final class WorkOrderTemplateListViewModel {
    enum Phase: Equatable {
        case loading
        case loaded
        case empty
        case error(String)
    }

    private(set) var phase: Phase = .loading
    private(set) var cards: [WorkOrderTemplateCardData] = []
    private(set) var templates: [WorkOrderTemplate] = []
    private(set) var isPerformingMutation = false
    var pendingDeleteTemplate: WorkOrderTemplate?
    var editorTemplate: WorkOrderTemplate?
    var showsEditor = false

    private let actor: User
    private let service: OperatorWorkOrderTemplateService

    init(actor: User, service: OperatorWorkOrderTemplateService) {
        self.actor = actor
        self.service = service
    }

    func load() async {
        phase = .loading
        do {
            templates = try await service.list(actor: actor)
            cards = templates.map(WorkOrderTemplatePresentationMapping.cardData)
            phase = cards.isEmpty ? .empty : .loaded
        } catch let error as DomainError {
            phase = .error(error.operatorMessage)
        } catch {
            phase = .error("Şablonlar yüklenemedi.")
        }
    }

    func openCreateEditor() {
        editorTemplate = nil
        showsEditor = true
    }

    func openEditEditor(_ template: WorkOrderTemplate) {
        editorTemplate = template
        showsEditor = true
    }

    func requestDelete(_ template: WorkOrderTemplate) {
        pendingDeleteTemplate = template
    }

    func cancelDelete() {
        pendingDeleteTemplate = nil
    }

    func confirmDelete() async {
        guard let template = pendingDeleteTemplate else { return }
        pendingDeleteTemplate = nil
        isPerformingMutation = true
        defer { isPerformingMutation = false }
        do {
            try await service.delete(actor: actor, id: template.id)
            await load()
        } catch let error as DomainError {
            phase = .error(error.operatorMessage)
        } catch {
            phase = .error("Şablon silinemedi.")
        }
    }

    func duplicate(_ template: WorkOrderTemplate) async {
        isPerformingMutation = true
        defer { isPerformingMutation = false }
        do {
            _ = try await service.duplicate(actor: actor, id: template.id)
            await load()
        } catch let error as DomainError {
            phase = .error(error.operatorMessage)
        } catch {
            phase = .error("Şablon kopyalanamadı.")
        }
    }

    func template(for id: WorkOrderTemplateID) -> WorkOrderTemplate? {
        templates.first { $0.id == id }
    }
}

@Observable
@MainActor
final class WorkOrderTemplateEditorViewModel {
    var name = ""
    var summary = ""
    var workType: WorkType = .maintenance
    var deviceCategory: DeviceCategory = .pos
    var deviceBrand = ""
    var deviceModel = ""
    var issueDescription = ""
    var priority: WorkOrderPriority = .normal

    private(set) var isSaving = false
    private(set) var errorMessage: String?

    private let actor: User
    private let service: OperatorWorkOrderTemplateService
    private let editingTemplate: WorkOrderTemplate?

    var isEditing: Bool { editingTemplate != nil }
    var navigationTitle: String { isEditing ? "Şablonu Düzenle" : "Yeni Şablon" }

    init(
        actor: User,
        service: OperatorWorkOrderTemplateService,
        editingTemplate: WorkOrderTemplate? = nil
    ) {
        self.actor = actor
        self.service = service
        self.editingTemplate = editingTemplate
        if let editingTemplate {
            name = editingTemplate.name
            summary = editingTemplate.summary ?? ""
            workType = editingTemplate.workType
            deviceCategory = editingTemplate.deviceCategory
            deviceBrand = editingTemplate.deviceBrand ?? ""
            deviceModel = editingTemplate.deviceModel ?? ""
            issueDescription = editingTemplate.issueDescription ?? ""
            priority = editingTemplate.priority
        }
    }

    func save() async -> WorkOrderTemplate? {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        do {
            if var existing = editingTemplate {
                existing.name = name
                existing.summary = summary.nilIfEmpty
                existing.workType = workType
                existing.deviceCategory = deviceCategory
                existing.deviceBrand = deviceBrand.nilIfEmpty
                existing.deviceModel = deviceModel.nilIfEmpty
                existing.issueDescription = issueDescription.nilIfEmpty
                existing.priority = priority
                return try await service.update(actor: actor, template: existing)
            }

            return try await service.create(
                actor: actor,
                name: name,
                summary: summary.nilIfEmpty,
                workType: workType,
                deviceCategory: deviceCategory,
                deviceBrand: deviceBrand.nilIfEmpty,
                deviceModel: deviceModel.nilIfEmpty,
                issueDescription: issueDescription.nilIfEmpty,
                priority: priority
            )
        } catch let error as DomainError {
            errorMessage = error.operatorMessage
            return nil
        } catch {
            errorMessage = "Şablon kaydedilemedi."
            return nil
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
    }
}
