import Foundation

/// Firestore DTO for the `workOrderNotes` collection.
struct FirestoreWorkOrderNoteDTO: Codable, Hashable, Sendable {
    let id: String
    let workOrderId: String
    let authorUserId: String
    let text: String
    let createdAt: Date
}

extension FirestoreWorkOrderNoteDTO {

    init(domain: WorkOrderNote) {
        self.id = domain.id
        self.workOrderId = domain.workOrderId.rawValue
        self.authorUserId = domain.authorUserId.rawValue
        self.text = domain.text
        self.createdAt = domain.createdAt
    }

    func toDomain() -> WorkOrderNote {
        WorkOrderNote(
            id: id,
            workOrderId: WorkOrderID(workOrderId),
            authorUserId: UserID(authorUserId),
            text: text,
            createdAt: createdAt
        )
    }
}
