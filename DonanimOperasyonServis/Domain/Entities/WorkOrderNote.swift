import Foundation

/// A note attached to a work order by its assigned technician. Notes
/// are used both for internal service documentation and to satisfy
/// the "gerekli servis notları" completion requirement.
struct WorkOrderNote: Hashable, Sendable, Identifiable, Codable {
    let id: String
    let workOrderId: WorkOrderID
    let authorUserId: UserID
    var text: String
    let createdAt: Date

    init(
        id: String,
        workOrderId: WorkOrderID,
        authorUserId: UserID,
        text: String,
        createdAt: Date
    ) {
        self.id = id
        self.workOrderId = workOrderId
        self.authorUserId = authorUserId
        self.text = text
        self.createdAt = createdAt
    }
}
