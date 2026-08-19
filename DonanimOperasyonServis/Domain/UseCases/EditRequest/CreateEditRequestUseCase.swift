import Foundation

/// Opens a new `EditRequest` against a completed work order.
///
/// Rules:
/// - Only the assigned technician of a completed work order may
///   file a request (`RoleAccessPolicy.canRequestEdit`).
/// - The target field must be one of the whitelisted
///   `EditableWorkOrderField` cases.
/// - `currentValue` and `requestedValue` must differ, otherwise the
///   request is rejected as `.noChange`.
struct CreateEditRequestUseCase: Sendable {
    let workOrderRepository: WorkOrderRepository
    let editRequestRepository: EditRequestRepository

    init(
        workOrderRepository: WorkOrderRepository,
        editRequestRepository: EditRequestRepository
    ) {
        self.workOrderRepository = workOrderRepository
        self.editRequestRepository = editRequestRepository
    }

    @discardableResult
    func execute(
        actor: User,
        orderId: WorkOrderID,
        requestId: EditRequestID,
        field: EditableWorkOrderField,
        currentValue: String,
        requestedValue: String,
        reason: String,
        at now: Date = Date()
    ) async throws -> EditRequest {
        guard RoleAccessPolicy.can(.createEditRequest, as: actor.role) else {
            throw DomainError.unauthorized(action: .createEditRequest)
        }

        let order = try await workOrderRepository.fetch(id: orderId)
        guard RoleAccessPolicy.canRequestEdit(on: order, as: actor) else {
            // Distinguish "not the assigned technician" from
            // "work order not completed" so the UI can show the
            // right message.
            if !order.isLocked {
                throw DomainError.invalidEditRequest(reason: .workOrderNotCompleted)
            }
            throw DomainError.unauthorized(action: .createEditRequest)
        }

        guard currentValue != requestedValue else {
            throw DomainError.invalidEditRequest(reason: .noChange)
        }

        let trimmedReason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedReason.isEmpty else {
            throw DomainError.invalidData(reason: "editRequest.reasonEmpty")
        }

        let request = EditRequest(
            id: requestId,
            workOrderId: order.id,
            requestedByUserId: actor.id,
            createdAt: now,
            reason: trimmedReason,
            field: field.rawValue,
            currentValue: currentValue,
            requestedValue: requestedValue,
            status: .pending,
            reviewedByUserId: nil,
            reviewedAt: nil,
            decisionNote: nil
        )
        try await editRequestRepository.save(request)
        return request
    }
}
