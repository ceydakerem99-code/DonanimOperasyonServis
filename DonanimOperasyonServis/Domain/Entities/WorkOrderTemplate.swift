import Foundation

/// Reusable defaults for creating work orders. Instance-specific
/// fields (customer, technician, schedule, serial number) are never
/// stored on a template.
struct WorkOrderTemplate: Hashable, Sendable, Identifiable, Codable {
    let id: WorkOrderTemplateID
    var name: String
    var summary: String?
    var workType: WorkType
    var deviceCategory: DeviceCategory
    var deviceBrand: String?
    var deviceModel: String?
    var issueDescription: String?
    var priority: WorkOrderPriority
    var createdByUserId: UserID
    var createdAt: Date
    var updatedAt: Date

    init(
        id: WorkOrderTemplateID,
        name: String,
        summary: String? = nil,
        workType: WorkType,
        deviceCategory: DeviceCategory,
        deviceBrand: String? = nil,
        deviceModel: String? = nil,
        issueDescription: String? = nil,
        priority: WorkOrderPriority,
        createdByUserId: UserID,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.name = name
        self.summary = summary
        self.workType = workType
        self.deviceCategory = deviceCategory
        self.deviceBrand = deviceBrand
        self.deviceModel = deviceModel
        self.issueDescription = issueDescription
        self.priority = priority
        self.createdByUserId = createdByUserId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
