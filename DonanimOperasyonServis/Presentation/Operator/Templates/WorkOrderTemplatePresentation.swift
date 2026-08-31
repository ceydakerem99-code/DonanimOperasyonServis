import Foundation

enum WorkOrderTemplateApplying {
    static func apply(_ template: WorkOrderTemplate, to draft: inout NewWorkOrderDraft) {
        draft.workType = template.workType
        draft.deviceCategory = template.deviceCategory
        draft.priority = template.priority

        if let brand = template.deviceBrand?.trimmingCharacters(in: .whitespacesAndNewlines),
           !brand.isEmpty {
            draft.deviceBrand = brand
        }
        if let model = template.deviceModel?.trimmingCharacters(in: .whitespacesAndNewlines),
           !model.isEmpty {
            draft.deviceModel = model
        }
        if let description = template.issueDescription {
            draft.issueDescription = description
        }
    }
}

struct WorkOrderTemplateCardData: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let summary: String?
    let workTypeLabel: String
    let deviceLabel: String
    let priority: AppPriority
}

enum WorkOrderTemplatePresentationMapping {
    static func cardData(from template: WorkOrderTemplate) -> WorkOrderTemplateCardData {
        WorkOrderTemplateCardData(
            id: template.id.rawValue,
            name: template.name,
            summary: template.summary,
            workTypeLabel: template.workType.displayName,
            deviceLabel: template.deviceCategory.displayName,
            priority: WorkOrderPresentationMapping.appPriority(from: template.priority)
        )
    }
}
