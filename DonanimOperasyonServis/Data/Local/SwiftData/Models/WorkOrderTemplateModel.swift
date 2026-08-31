import Foundation
import SwiftData

@Model
final class WorkOrderTemplateModel {
    @Attribute(.unique) var id: String

    var name: String
    var summary: String?
    var workTypeRaw: String
    var deviceCategoryRaw: String
    var deviceBrand: String?
    var deviceModel: String?
    var issueDescription: String?
    var priorityRaw: String
    var createdByUserId: String
    var createdAt: Date
    var updatedAt: Date

    init(
        id: String,
        name: String,
        summary: String?,
        workTypeRaw: String,
        deviceCategoryRaw: String,
        deviceBrand: String?,
        deviceModel: String?,
        issueDescription: String?,
        priorityRaw: String,
        createdByUserId: String,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.name = name
        self.summary = summary
        self.workTypeRaw = workTypeRaw
        self.deviceCategoryRaw = deviceCategoryRaw
        self.deviceBrand = deviceBrand
        self.deviceModel = deviceModel
        self.issueDescription = issueDescription
        self.priorityRaw = priorityRaw
        self.createdByUserId = createdByUserId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

extension WorkOrderTemplateModel {
    convenience init(domain: WorkOrderTemplate) {
        self.init(
            id: domain.id.rawValue,
            name: domain.name,
            summary: domain.summary,
            workTypeRaw: domain.workType.rawValue,
            deviceCategoryRaw: domain.deviceCategory.rawValue,
            deviceBrand: domain.deviceBrand,
            deviceModel: domain.deviceModel,
            issueDescription: domain.issueDescription,
            priorityRaw: domain.priority.rawValue,
            createdByUserId: domain.createdByUserId.rawValue,
            createdAt: domain.createdAt,
            updatedAt: domain.updatedAt
        )
    }

    func apply(domain: WorkOrderTemplate) {
        name = domain.name
        summary = domain.summary
        workTypeRaw = domain.workType.rawValue
        deviceCategoryRaw = domain.deviceCategory.rawValue
        deviceBrand = domain.deviceBrand
        deviceModel = domain.deviceModel
        issueDescription = domain.issueDescription
        priorityRaw = domain.priority.rawValue
        createdByUserId = domain.createdByUserId.rawValue
        createdAt = domain.createdAt
        updatedAt = domain.updatedAt
    }

    func toDomain() -> WorkOrderTemplate? {
        guard let workType = WorkType(rawValue: workTypeRaw),
              let deviceCategory = DeviceCategory(rawValue: deviceCategoryRaw),
              let priority = WorkOrderPriority(rawValue: priorityRaw)
        else { return nil }

        return WorkOrderTemplate(
            id: WorkOrderTemplateID(id),
            name: name,
            summary: summary,
            workType: workType,
            deviceCategory: deviceCategory,
            deviceBrand: deviceBrand,
            deviceModel: deviceModel,
            issueDescription: issueDescription,
            priority: priority,
            createdByUserId: UserID(createdByUserId),
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}
