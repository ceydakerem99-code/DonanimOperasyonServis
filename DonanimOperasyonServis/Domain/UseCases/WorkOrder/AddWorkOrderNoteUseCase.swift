import Foundation

/// Appends a service note to a work order. Only the assigned
/// technician of a non-completed work order may do so.
struct AddWorkOrderNoteUseCase: Sendable {
    let workOrderRepository: WorkOrderRepository
    let noteRepository: WorkOrderNoteRepository

    init(
        workOrderRepository: WorkOrderRepository,
        noteRepository: WorkOrderNoteRepository
    ) {
        self.workOrderRepository = workOrderRepository
        self.noteRepository = noteRepository
    }

    @discardableResult
    func execute(
        actor: User,
        orderId: WorkOrderID,
        text: String,
        at now: Date = Date()
    ) async throws -> WorkOrderNote {
        guard RoleAccessPolicy.can(.addWorkOrderNote, as: actor.role) else {
            throw DomainError.unauthorized(action: .addWorkOrderNote)
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw DomainError.invalidData(reason: "note.textEmpty")
        }

        let order = try await workOrderRepository.fetch(id: orderId)
        guard RoleAccessPolicy.canAct(on: order, as: actor) else {
            throw order.isLocked
                ? DomainError.workOrderLocked(order.id)
                : DomainError.unauthorized(action: .addWorkOrderNote)
        }

        let note = WorkOrderNote(
            id: UUID().uuidString,
            workOrderId: order.id,
            authorUserId: actor.id,
            text: trimmed,
            createdAt: now
        )
        try await noteRepository.save(note)
        return note
    }
}
